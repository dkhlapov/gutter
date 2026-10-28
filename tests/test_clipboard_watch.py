import os, shutil, signal, subprocess, tempfile, time, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/clipboard-watch.sh"


class ClipboardWatch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        tmp = Path(self.tmp.name)
        self.dir = tmp / "clipboard"
        stubs = tmp / "stubs"
        stubs.mkdir()
        # A wl-paste on PATH in front of the real one: the test never touches the live desktop's watchers.
        # The unique path in its command line is what watchers() looks for.
        self.stub = stubs / "wl-paste"
        self.stub.write_text("#!/bin/sh\nwhile :; do sleep 0.1; done\n")
        self.stub.chmod(0o755)
        self.env = {**os.environ, "PATH": f"{stubs}:{os.environ['PATH']}"}
        self.procs = []
        self.addCleanup(self.cleanup)

    def cleanup(self):
        subprocess.run(["pkill", "-9", "-f", str(self.tmp.name)], check=False)
        for p in self.procs:
            p.kill()
            p.wait()

    def watchers(self):
        """Pids of the stub's `--watch` processes."""
        out = subprocess.run(["pgrep", "-f", f"{self.stub} --watch"], capture_output=True, text=True).stdout
        return out.split()

    def start(self, parent=None):
        """Starts the script the way Quickshell does (as a child of the caller), or under a throwaway parent."""
        if parent:
            cmd = ["sh", "-c", f'"$0" "$1" & wait', str(SCRIPT), str(self.dir)]
        else:
            cmd = [str(SCRIPT), str(self.dir)]
        p = subprocess.Popen(cmd, env=self.env, stdout=subprocess.DEVNULL)
        self.procs.append(p)
        return p

    def wait_for(self, check, what, timeout=6):
        end = time.time() + timeout
        while time.time() < end:
            if check():
                return
            time.sleep(0.05)
        self.fail(f"timed out waiting for {what}; watchers: {self.watchers()}")

    def test_missing_wl_paste_exits_127(self):
        # With nothing but mkdir on the PATH. The guard has to answer before anything else is set up: without
        # it the script goes on to the lock and the pid file, and ends up exiting 75.
        tools = Path(self.tmp.name) / "tools"
        tools.mkdir()
        (tools / "mkdir").symlink_to(shutil.which("mkdir"))
        start = time.time()
        r = subprocess.run([shutil.which("bash"), str(SCRIPT), str(self.dir)], env={**self.env, "PATH": str(tools)}, timeout=5)
        self.assertEqual(r.returncode, 127)
        self.assertLess(time.time() - start, 2)
        self.assertEqual(list(self.dir.iterdir()), [])

    def entry(self, types, body):
        """Runs --entry against a wl-paste that lists `types` and, asked for a copy, runs `body` and exits having
        handed its output pipe to a process that holds it open for 12 s, the way wl-copy's forked source does."""
        hung = Path(self.tmp.name) / "hung"
        hung.mkdir(exist_ok=True)
        (hung / "wl-paste").write_text(
            f'#!/bin/sh\n[ "$1" = --list-types ] && {{ printf "{types}\\n"; exit 0; }}\n{body}\nsetsid sleep 12 &\nexit 0\n')
        (hung / "wl-paste").chmod(0o755)
        env = {**self.env, "PATH": f"{hung}:{os.environ['PATH']}"}
        self.dir.mkdir(parents=True, exist_ok=True)
        start = time.time()
        r = subprocess.run([str(SCRIPT), str(self.dir), "--entry"], env=env, timeout=15, capture_output=True)
        self.assertEqual(r.returncode, 0)
        self.assertLess(time.time() - start, 9)
        return r

    def test_entry_gives_up_on_an_image_source_that_never_finishes(self):
        r = self.entry("image/png", "")
        self.assertEqual(r.stdout, b"")
        self.assertEqual(list(self.dir.iterdir()), [])

    def test_entry_gives_up_on_a_text_source_that_never_finishes(self):
        r = self.entry("text/plain", "")
        self.assertEqual(r.stdout, b"")

    def test_entry_drops_a_copy_the_timeout_cut_off(self):
        # Long enough for part of it to get out: head and base64 hold back what they have read until they have a block.
        body = "head -c 60000 /dev/zero | tr '\\0' a"
        r = self.entry("image/png", body)
        self.assertEqual(r.stdout, b"")
        self.assertEqual(list(self.dir.iterdir()), [])
        r = self.entry("text/plain", body)
        self.assertEqual(r.stdout, b"")

    def ok_entry(self, types, body):
        """Runs --entry against a wl-paste that answers promptly and exits, without any hand-off."""
        ok = Path(self.tmp.name) / "ok"
        ok.mkdir(exist_ok=True)
        (ok / "wl-paste").write_text(f'#!/bin/sh\n[ "$1" = --list-types ] && {{ echo {types}; exit 0; }}\n{body}\n')
        (ok / "wl-paste").chmod(0o755)
        env = {**self.env, "PATH": f"{ok}:{os.environ['PATH']}"}
        self.dir.mkdir(parents=True, exist_ok=True)
        return subprocess.run([str(SCRIPT), str(self.dir), "--entry"], env=env, timeout=10, capture_output=True)

    def test_entry_keeps_a_complete_text_copy(self):
        # The timeout must not get in the way of a normal copy.
        self.assertEqual(self.ok_entry("text/plain", "printf hi").stdout, b"t aGk=\n")

    def test_entry_keeps_a_complete_image_copy(self):
        r = self.ok_entry("image/png", "printf png")
        pngs = list(self.dir.glob("*.png"))
        self.assertEqual(len(pngs), 1)
        self.assertEqual(pngs[0].read_bytes(), b"png")
        self.assertEqual(r.stdout, f"i {pngs[0]}\n".encode())
        self.assertEqual(len(list(self.dir.iterdir())), 1)

    def test_starts_one_watcher(self):
        self.start()
        self.wait_for(lambda: len(self.watchers()) == 1, "one watcher")

    def test_reload_leaves_one_watcher(self):
        first = self.start()
        self.wait_for(lambda: len(self.watchers()) == 1, "first watcher")
        newest = first
        for _ in range(3):
            previous, newest = newest, self.start()
            self.wait_for(lambda: previous.poll() is not None, "the previous watcher to be displaced")
            self.assertEqual(previous.returncode, 75)
            self.wait_for(lambda: len(self.watchers()) == 1, "one watcher")
        time.sleep(1)
        self.assertEqual(len(self.watchers()), 1)

    def test_reload_that_kills_the_old_watcher_outright(self):
        # Quickshell SIGKILLs the old generation's process on a hot reload: no trap runs, wl-paste is orphaned.
        first = self.start()
        self.wait_for(lambda: len(self.watchers()) == 1, "first watcher")
        first.kill()
        first.wait()
        orphan = self.watchers()
        self.assertEqual(len(orphan), 1)
        self.start()
        self.wait_for(lambda: len(self.watchers()) == 1 and self.watchers() != orphan, "the orphan replaced by a new watcher")

    def test_another_live_shell_keeps_the_watcher(self):
        owner = self.start(parent=True)
        self.wait_for(lambda: len(self.watchers()) == 1, "the owner's watcher")
        second = self.start()
        self.wait_for(lambda: second.poll() is not None, "the second shell to give up")
        self.assertEqual(second.returncode, 75)
        self.assertIsNone(owner.poll())
        self.assertEqual(len(self.watchers()), 1)

    def test_stale_watcher_of_an_older_version_is_killed(self):
        self.dir = Path(self.tmp.name) / "clip [x]+(1).d"  # regex characters in the state dir
        self.dir.mkdir(parents=True)
        old = subprocess.Popen([str(self.stub), "--watch", str(SCRIPT), str(self.dir), "--entry"], env=self.env)
        self.procs.append(old)
        self.wait_for(lambda: len(self.watchers()) == 1, "the stray")
        self.start()
        self.wait_for(lambda: old.poll() is not None, "the stray to be killed")
        self.wait_for(lambda: len(self.watchers()) == 1, "exactly one watcher")

    def test_stale_watcher_under_a_path_with_a_space_is_killed(self):
        old = subprocess.Popen([str(self.stub), "--watch", str(self.tmp.name) + "/my dir/clipboard-watch.sh", str(self.dir), "--entry"], env=self.env)
        self.procs.append(old)
        self.wait_for(lambda: len(self.watchers()) == 1, "the stray")
        self.start()
        self.wait_for(lambda: old.poll() is not None, "the stray to be killed")
        self.wait_for(lambda: len(self.watchers()) == 1, "exactly one watcher")

    def test_watcher_ends_with_the_shell(self):
        parent = self.start(parent=True)
        self.wait_for(lambda: len(self.watchers()) == 1, "the watcher")
        parent.kill()
        parent.wait()
        self.wait_for(lambda: not self.watchers(), "the watcher to follow its parent")

    def test_terminate_takes_the_watcher_along(self):
        p = self.start()
        self.wait_for(lambda: len(self.watchers()) == 1, "the watcher")
        p.send_signal(signal.SIGTERM)
        p.wait(timeout=5)
        self.wait_for(lambda: not self.watchers(), "the watcher to end")
        self.assertFalse((self.dir / "watch.pid").exists())


if __name__ == "__main__":
    unittest.main()
