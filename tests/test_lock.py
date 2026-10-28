import os, re, shlex, shutil, signal, socket, subprocess, sys, tempfile, time, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAM = ROOT / "lockscreen/pam.d"


def rules(name):
    """The non-comment, non-blank lines of a PAM stack, with runs of whitespace squeezed."""
    out = []
    for line in (PAM / name).read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(re.sub(r"\s+", " ", line))
    return out


# Commands that could reach the outer session, plus the compositor and bus a nested session starts.
STAND_IN_NAMES = ("loginctl", "systemctl", "pkill", "pgrep", "killall", "hyprctl", "qs", "busctl", "dbus-send", "gdbus",
                  "Hyprland", "dbus-daemon")


def stand_ins(base, qmlls=False):
    """Inert recording stand-ins for those commands, in a folder a test puts first on PATH (so a script that regresses
    into calling the real one is caught, not obeyed). Each call is logged as name, signature, runtime dir, display and
    arguments (tab separated) in the returned log. With `qmlls` a `qs -p <dir>` makes the dangling `.qmlls.ini` link the
    real one does. `base/safe` holds only `cat`, for a test that runs a command with PATH limited to the stand-ins."""
    bin_dir = Path(base) / "rbin"
    bin_dir.mkdir(exist_ok=True)
    safe = Path(base) / "safe"
    safe.mkdir(exist_ok=True)
    if not (safe / "cat").exists():
        (safe / "cat").symlink_to(shutil.which("cat"))
    log = Path(base) / "calls.log"
    log.touch()
    env = '"${HYPRLAND_INSTANCE_SIGNATURE-unset}" "${XDG_RUNTIME_DIR-unset}" "${WAYLAND_DISPLAY-unset}"'
    for name in STAND_IN_NAMES:
        body = f"printf '%s\\t%s\\t%s\\t%s\\t%s\\n' {name} {env} \"$*\" >> {log}\n"
        if name == "hyprctl":
            body += 'case "$*" in *monitors*) printf "Monitor A (ID 0):\\nMonitor B (ID 1):\\n" ;; esac\n'
        if name == "qs" and qmlls:
            body += 'if [ "$1" = -p ] && [ "$#" -eq 2 ]; then ln -sfn /nonexistent/gn/run/.qmlls.ini "$2/.qmlls.ini"; fi\n'
        (bin_dir / name).write_text(f"#!/bin/sh\n{body}exit 0\n")
        (bin_dir / name).chmod(0o755)
    return bin_dir, log


class PamStacks(unittest.TestCase):
    def test_header(self):
        for name in ("passwd", "fprint"):
            self.assertEqual((PAM / name).read_text().splitlines()[0], "#%PAM-1.0", name)

    def test_passwd_stack_in_order(self):
        wanted = ["pam_faillock.so preauth", "pam_unix.so", "pam_faillock.so authfail", "pam_faillock.so authsucc"]
        lines = rules("passwd")
        self.assertEqual(len(lines), len(wanted))
        for line, module in zip(lines, wanted):
            self.assertTrue(line.startswith("auth "), line)
            self.assertIn(module, line)

    def test_passwd_unix_does_not_skip_faillock(self):
        # A failure of pam_unix falls through to authfail (default=bad), never past it; authfail ends the stack.
        unix, authfail = rules("passwd")[1:3]
        self.assertIn("[success=1 default=bad]", unix)
        self.assertIn("[default=die]", authfail)

    def test_no_permit(self):
        for name in ("passwd", "fprint"):
            self.assertNotIn("pam_permit.so", (PAM / name).read_text(), name)

    def test_fprint_is_exact(self):
        self.assertEqual(rules("fprint"), ["auth required pam_fprintd.so max-tries=1"])


class TestPamScript(unittest.TestCase):
    """scripts/lock-test-pam.sh writes only fresh folders under a given parent, never over a real PAM folder."""

    script = str(ROOT / "scripts/lock-test-pam.sh")

    @staticmethod
    def clean_env(**extra):
        """The environment without the caller's GIT_* variables (they would steer git inside the script)."""
        return {**{k: v for k, v in os.environ.items() if not k.startswith("GIT_")}, **extra}

    @staticmethod
    def home_env(tmp, **extra):
        """A temp HOME and XDG_CONFIG_HOME, so no test reads the real home."""
        return {"HOME": str(tmp / "home"), "XDG_CONFIG_HOME": str(tmp / "home/.config"), **extra}

    def run_script(self, *args, env=None, script=None):
        return subprocess.run([script or self.script, *args], capture_output=True, text=True, env=self.clean_env(**(env or {})))

    def test_needs_an_argument(self):
        r = self.run_script()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("usage", r.stderr)

    def test_missing_parent(self):
        self.assertNotEqual(self.run_script("/nonexistent/parent").returncode, 0)

    def test_refuses_the_real_pam_folder_and_its_parent(self):
        before = (PAM / "passwd").read_text()
        with tempfile.TemporaryDirectory() as tmp:
            env = self.home_env(Path(tmp).resolve())
            for parent in (PAM, PAM.parent, ROOT, Path("/etc/pam.d")):
                r = self.run_script(str(parent), env=env)
                self.assertNotEqual(r.returncode, 0, parent)
                self.assertEqual(r.stdout, "", parent)
        self.assertEqual((PAM / "passwd").read_text(), before)
        self.assertFalse(list(PAM.glob("check.sh")))

    def test_makes_a_fresh_folder_in_the_parent(self):
        with tempfile.TemporaryDirectory() as parent:
            parent = Path(parent).resolve()
            env = self.home_env(parent)
            parent = str(parent)
            a = self.run_script(parent, env=env)
            b = self.run_script(parent, env=env)
            self.assertEqual(a.returncode, 0, a.stderr)
            da, db = Path(a.stdout.strip()), Path(b.stdout.strip())
            self.assertNotEqual(da, db)
            self.assertEqual(da.parent, Path(parent))
            self.assertIn("pam_exec.so", (da / "passwd").read_text())
            self.assertIn(str(da), (da / "passwd").read_text())
            ok = subprocess.run([str(da / "check.sh")], input="guttertest\n", text=True)
            bad = subprocess.run([str(da / "check.sh")], input="nope\n", text=True)
            self.assertEqual((ok.returncode, bad.returncode), (0, 1))

    def refused(self, r, parent, *words):
        self.assertNotEqual(r.returncode, 0, (parent, r.stderr))
        self.assertEqual(r.stdout, "", parent)
        self.assertIn("refusing", r.stderr)
        for word in words:
            self.assertIn(word, r.stderr)
        self.assertEqual([p for p in Path(parent).resolve().iterdir() if p.name.startswith("gutter-lock-pam.")], [])

    def test_ordinary_parent_works_with_a_temp_home(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp).resolve()
            (tmp / "home/.config/quickshell").mkdir(parents=True)
            (tmp / "parent").mkdir()
            r = self.run_script(str(tmp / "parent"), env=self.home_env(tmp))
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue((Path(r.stdout.strip()) / "passwd").is_file())

    def test_refuses_the_config_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp).resolve()
            cfg = tmp / "xdg/quickshell"
            (tmp / "home/.config/quickshell").mkdir(parents=True)
            cfg.mkdir(parents=True)
            env = self.home_env(tmp, XDG_CONFIG_HOME=str(tmp / "xdg"))
            for parent in (tmp / "home/.config/quickshell", cfg):
                self.refused(self.run_script(str(parent), env=env), parent, "config folder")

    def test_refuses_a_symlinked_config_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp).resolve()
            real = tmp / "elsewhere"
            (real / "sub").mkdir(parents=True)
            (tmp / "home/.config").mkdir(parents=True)
            (tmp / "home/.config/quickshell").symlink_to(real)
            env = self.home_env(tmp)
            for parent in (tmp / "home/.config/quickshell", real, real / "sub"):
                self.refused(self.run_script(str(parent), env=env), parent, "config folder")

    def test_refuses_where_the_gutter_install_link_points(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp).resolve()
            target = tmp / "checkout"
            (target / "sub").mkdir(parents=True)
            (tmp / "home/.config/quickshell").mkdir(parents=True)
            (tmp / "home/.config/quickshell/gutter").symlink_to(target)
            env = self.home_env(tmp)
            for parent in (tmp / "home/.config/quickshell/gutter", target, target / "sub"):
                self.refused(self.run_script(str(parent), env=env), parent, "config folder")
            # The same link under XDG_CONFIG_HOME when that is somewhere else than ~/.config.
            (tmp / "xdg/quickshell").mkdir(parents=True)
            (tmp / "xdg/quickshell/gutter").symlink_to(target)
            env["XDG_CONFIG_HOME"] = str(tmp / "xdg")
            self.refused(self.run_script(str(target / "sub"), env=env), target / "sub", "config folder")

    def test_refuses_the_main_checkout_of_a_worktree(self):
        git_env = {"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull, "GIT_AUTHOR_NAME": "t",
                   "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}

        def git(cwd, *args):
            subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, env=self.clean_env(**git_env))

        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp).resolve()
            main, wt = tmp / "main", tmp / "wt"
            (main / "scripts").mkdir(parents=True)
            shutil.copy(self.script, main / "scripts/lock-test-pam.sh")
            git(main, "init", "-q")
            git(main, "add", ".")
            git(main, "commit", "-q", "-m", "x")
            git(main, "worktree", "add", "-q", "-b", "side", str(wt))
            (main / "sub").mkdir()
            (tmp / "other").mkdir()
            env = self.home_env(tmp)
            copy = str(wt / "scripts/lock-test-pam.sh")
            for parent in (main, main / "sub"):
                self.refused(self.run_script(str(parent), env=env, script=copy), parent, "main checkout")
            r = self.run_script(str(tmp / "other"), env=env, script=copy)
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_without_a_git_repo_the_main_checkout_check_is_skipped(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp).resolve()
            (tmp / "plain/scripts").mkdir(parents=True)
            shutil.copy(self.script, tmp / "plain/scripts/lock-test-pam.sh")
            (tmp / "other").mkdir()
            # The ceiling keeps git from finding a repo above the temp folder.
            r = self.run_script(str(tmp / "other"), env=self.home_env(tmp, GIT_CEILING_DIRECTORIES=str(tmp)),
                                script=str(tmp / "plain/scripts/lock-test-pam.sh"))
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_refuses_parents_whose_path_would_break_the_pam_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp).resolve()
            env = self.home_env(tmp)
            for name in ("a#b", "a[b", "a]b", "a b", "a'b", 'a"b', "a\\b", "a%b", "a$b"):
                parent = tmp / name
                parent.mkdir()
                self.refused(self.run_script(str(parent), env=env), parent, "only letters, digits")
            parent = tmp / "a.b_c+d-e:f@g=h,i"
            parent.mkdir()
            r = self.run_script(str(parent), env=env)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn(r.stdout.strip(), (Path(r.stdout.strip()) / "passwd").read_text())


class Rescue(unittest.TestCase):
    """scripts/rescue-unlock.sh in dry run (GUTTER_RESCUE_DRY=1) against fake instance folders in a temp
    XDG_RUNTIME_DIR. The real runs put recording shims for hyprctl, qs, busctl, pkill, pgrep and killall first on PATH
    (see shims()), so nothing here calls the real ones or touches the live compositor, and nothing connects to a socket
    of the live compositor (the script only reads /proc and the live runtime dir's folders to find who holds a socket)."""

    script = str(ROOT / "scripts/rescue-unlock.sh")
    sig_old = "aaaa_1000_1"
    sig_new = "bbbb_2000_2"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.run_dir = Path(self.tmp.name).resolve()
        (self.run_dir / "hint").write_text("true\n")
        # Every run has the inert stand-ins first on PATH (the shim tests put their own folder before them): a run
        # whose dry flag regressed reaches a logged stand-in, never the real hyprctl, qs or busctl.
        (self.run_dir / "si").mkdir()
        bin_dir, _ = stand_ins(self.run_dir / "si")
        self.path = f"{bin_dir}:{os.environ['PATH']}"
        # The fake compositor: a live process that is not an ancestor of the script.
        self.compositor = subprocess.Popen(["sleep", "600"])
        self.addCleanup(lambda: (self.compositor.kill(), self.compositor.wait()))

    def instance(self, sig, display, mtime, pid=None):
        d = self.run_dir / "hypr" / sig
        d.mkdir(parents=True)
        (d / "hyprland.lock").write_text(f"{pid or self.compositor.pid}\n{display}\n")
        os.utime(d, (mtime, mtime))
        return d

    def run_script(self, *args, stdin="unlock\n", env=None, wayland=None):
        e = {"PATH": self.path, "HOME": self.tmp.name, "XDG_RUNTIME_DIR": str(self.run_dir),
             "GUTTER_RESCUE_DRY": "1", "GUTTER_RESCUE_SESSION": "3",
             # No real waiting: the poll for a lock screen that did not end and the pause after killing it.
             "GUTTER_RESCUE_POLL": "0.01", "GUTTER_RESCUE_SETTLE": "0"}
        if wayland:
            e["WAYLAND_DISPLAY"] = wayland
        e.update(env or {})
        return subprocess.run([self.script, *args], input=stdin, capture_output=True, text=True, env=e)

    def commands(self, r):
        """The commands a dry run printed, in order."""
        return [l[len("would run: "):] for l in r.stdout.splitlines() if l.startswith("would run: ")]

    def test_dry_run_prints_the_commands_in_order(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        r = self.run_script()
        self.assertEqual(r.returncode, 0, r.stderr)
        cmds = self.commands(r)
        self.assertIn(f"HYPRLAND_INSTANCE_SIGNATURE={self.sig_new}", r.stdout)
        self.assertIn("WAYLAND_DISPLAY=wayland-7", r.stdout)
        joined = "\n".join(cmds)
        restore = joined.index("allow_session_lock_restore")
        end = joined.index("qs -c gutter kill --pid")
        shell = joined.index(f"qs -p {ROOT}/lockscreen/rescue")
        hint = joined.index("SetLockedHint")
        self.assertLess(restore, end)
        self.assertLess(end, shell)
        self.assertLess(shell, hint)
        # Only the qs instances that run in the target instance are asked to quit, never a bare `qs kill`.
        self.assertIn(f"timeout -k 2 5 qs -c gutter kill --pid <each pid of qs -c gutter list --json that runs in instance {self.sig_new}>", joined)
        self.assertIn("timeout -k 2 15 qs -p", joined)
        self.assertIn(f"kill -KILL <each pid of qs -c gutter list --json that runs in instance {self.sig_new} and did not end>", r.stdout)
        self.assertIn("hyprctl", cmds[0])
        self.assertIn("/org/freedesktop/login1/session/_33 org.freedesktop.login1.Session SetLockedHint b false", joined)

    def test_picks_the_newest_instance(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        self.instance(self.sig_old, "wayland-1", 1000)
        r = self.run_script()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(f"HYPRLAND_INSTANCE_SIGNATURE={self.sig_new}", r.stdout)
        self.assertNotIn(self.sig_old, r.stdout)

    def test_a_signature_from_the_caller_wins(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        self.instance(self.sig_old, "wayland-1", 1000)
        r = self.run_script(env={"HYPRLAND_INSTANCE_SIGNATURE": self.sig_old})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(f"HYPRLAND_INSTANCE_SIGNATURE={self.sig_old}", r.stdout)
        self.assertIn("WAYLAND_DISPLAY=wayland-1", r.stdout)

    def test_session_path_is_encoded_like_idle_js(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        for session, path in (("3", "_33"), ("c2", "c2"), ("12", "_312"), ("a-b", "a_2db")):
            r = self.run_script(env={"GUTTER_RESCUE_SESSION": session})
            self.assertIn(f"/org/freedesktop/login1/session/{path} org.freedesktop.login1.Session SetLockedHint b false", r.stdout, session)

    def test_a_hint_file_replaces_logind(self):
        # The nested test setup keeps its hint in a file; its rescue must never touch the real session's hint.
        self.instance(self.sig_new, "wayland-7", 2000)
        r = self.run_script(env={"GUTTER_LOCK_HINT_FILE": str(self.run_dir / "hint")})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(f"> {self.run_dir}/hint", r.stdout)
        self.assertNotIn("busctl", r.stdout)
        self.assertEqual((self.run_dir / "hint").read_text(), "true\n")  # a dry run changes nothing

    def test_refuses_inside_a_wayland_session(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        r = self.run_script(wayland="wayland-1")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("TTY", r.stderr)
        self.assertEqual(r.stdout, "")

    def test_force_with_a_named_instance_allows_a_wayland_session(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        r = self.run_script("--force", "--instance", self.sig_new, wayland="wayland-1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("WAYLAND_DISPLAY=wayland-7", r.stdout)

    def test_force_in_a_wayland_session_never_guesses_the_instance(self):
        # Neither a signature from the environment nor "the newest" may be taken: both would be the caller's own session.
        self.instance(self.sig_new, "wayland-7", 2000)
        for env in ({}, {"HYPRLAND_INSTANCE_SIGNATURE": self.sig_new}):
            r = self.run_script("--force", wayland="wayland-1", env=env)
            self.assertEqual(r.returncode, 1, env)
            self.assertIn("--instance", r.stderr)
            self.assertIn("lock-nested.sh env", r.stderr)  # says what to do
            self.assertEqual(r.stdout, "", env)

    def test_no_instance(self):
        for make in (lambda: None, lambda: (self.run_dir / "hypr").mkdir()):
            make()
            r = self.run_script()
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("no Hyprland instance", r.stderr)
            self.assertEqual(r.stdout, "")

    def test_unknown_signature_from_the_caller(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        r = self.run_script(env={"HYPRLAND_INSTANCE_SIGNATURE": "nope"})
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("no Hyprland instance", r.stderr)

    def test_needs_the_word_unlock(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        for stdin in ("", "\n", "yes\n", "Unlock\n", "unlock now\n"):
            r = self.run_script(stdin=stdin)
            self.assertNotEqual(r.returncode, 0, repr(stdin))
            self.assertEqual(r.stdout, "", repr(stdin))

    def shims(self, qs_exit=0):
        """Fake hyprctl, qs and busctl that only log their call; PATH puts them first. pkill, pgrep and killall are
        logged too: the script must never call them."""
        bin_dir = self.run_dir / "bin"
        bin_dir.mkdir()
        log = self.run_dir / "calls.log"
        for name in ("hyprctl", "qs", "busctl", "pkill", "pgrep", "killall"):
            code = qs_exit if name == "qs" else 0
            body = f'echo "{name} $*" >> {log}\n'
            if name == "qs":
                body += f'echo "$QT_QPA_PLATFORM" >> {log}.qs-platform\n'
            if name == "hyprctl":
                body += 'case "$1" in -j) echo \'{"option": "misc:allow_session_lock_restore", "bool": true}\' ;; esac\n'
            (bin_dir / name).write_text(f"#!/bin/sh\n{body}exit {code}\n")
            (bin_dir / name).chmod(0o755)
        return bin_dir, log

    def test_real_run_with_shims_runs_in_order_and_clears_the_hint(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        bin_dir, log = self.shims()
        r = self.run_script(env={"GUTTER_RESCUE_DRY": "", "PATH": f"{bin_dir}:{self.path}",
                                 "GUTTER_LOCK_HINT_FILE": str(self.run_dir / "hint")})
        self.assertEqual(r.returncode, 0, r.stderr)
        calls = log.read_text().splitlines()
        self.assertTrue(calls[0].startswith("hyprctl eval "), calls)
        self.assertEqual(calls[-1], f"qs -p {ROOT}/lockscreen/rescue")
        self.assertEqual((self.run_dir / "hint").read_text(), "false\n")

    def test_the_rescue_shell_is_started_with_the_wayland_platform(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        bin_dir, log = self.shims()
        # A TTY environment may carry another platform or none: the rescue shell must still be started on wayland.
        r = self.run_script(env={"GUTTER_RESCUE_DRY": "", "PATH": f"{bin_dir}:{self.path}",
                                 "QT_QPA_PLATFORM": "xcb", "GUTTER_LOCK_HINT_FILE": str(self.run_dir / "hint")})
        self.assertEqual(r.returncode, 0, r.stderr)
        seen = Path(f"{log}.qs-platform").read_text().splitlines()
        self.assertEqual(seen[-1], "wayland")  # the last qs call is the rescue shell

    def test_a_failing_rescue_shell_leaves_the_hint(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        bin_dir, log = self.shims(qs_exit=3)
        r = self.run_script(env={"GUTTER_RESCUE_DRY": "", "PATH": f"{bin_dir}:{self.path}",
                                 "GUTTER_LOCK_HINT_FILE": str(self.run_dir / "hint")})
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual((self.run_dir / "hint").read_text(), "true\n")
        self.assertNotIn("busctl", log.read_text())

    def test_real_run_clears_logind_hint_after_the_shell(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        bin_dir, log = self.shims()
        r = self.run_script(env={"GUTTER_RESCUE_DRY": "", "PATH": f"{bin_dir}:{self.path}"})
        self.assertEqual(r.returncode, 0, r.stderr)
        calls = log.read_text().splitlines()
        self.assertTrue(calls[-2].startswith("qs -p "), calls)
        self.assertEqual(calls[-1], "busctl --system call org.freedesktop.login1 /org/freedesktop/login1/session/_33 org.freedesktop.login1.Session SetLockedHint b false")

    def test_unknown_argument(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        r = self.run_script("--bogus")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("usage", r.stderr)

    def test_the_lock_screen_to_end_and_the_timeouts_can_be_chosen(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        r = self.run_script(env={"GUTTER_RESCUE_QS": "-p /some/repo", "GUTTER_RESCUE_KILL_TIMEOUT": "3",
                                 "GUTTER_RESCUE_TIMEOUT": "9"})
        joined = "\n".join(self.commands(r))
        self.assertIn("timeout -k 2 3 qs -p /some/repo kill --pid <each pid of qs -p /some/repo list --json", joined)
        self.assertIn("timeout -k 2 9 qs -p " + str(ROOT), joined)
        self.assertIn("qs -p /some/repo list --json", r.stdout)
        r = self.run_script(env={"GUTTER_RESCUE_KILL_CMD": "my-kill --now"})
        cmds = "\n".join(self.commands(r))
        self.assertIn("timeout -k 2 5 my-kill --now", cmds)  # replaces the default wholesale
        self.assertNotIn("kill --pid", cmds)

    def test_the_lock_screen_is_ended_only_by_the_targets_registry_never_by_name(self):
        # Behaviour: a qs of the target instance that its registry does not name survives a real run, and no
        # by-name killer is called; only `qs kill --pid` and `kill -KILL` for the pid `qs list --json` names are used.
        self.instance(self.sig_new, "wayland-7", 2000)
        bin_dir, log = self.shims()
        fake = self.run_dir / "fakebin"
        fake.mkdir()
        (fake / "qs").symlink_to(shutil.which("sleep"))  # processes whose name (comm) is qs
        env = {**os.environ, "HYPRLAND_INSTANCE_SIGNATURE": self.sig_new}
        named = subprocess.Popen([str(fake / "qs"), "60"], env=env)
        decoy = subprocess.Popen([str(fake / "qs"), "60"], env=env)  # same name, same instance, not in the registry
        for p in (named, decoy):
            self.addCleanup(lambda p=p: (p.kill(), p.wait()))
        self.list_shim(bin_dir, log, named.pid)
        r = self.run_script(env=self.real_env(bin_dir))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(named.wait(timeout=5), -9)
        with self.assertRaises(subprocess.TimeoutExpired):
            decoy.wait(timeout=0.3)  # still running
        calls = log.read_text().splitlines()
        self.assertIn(f"qs -c gutter kill --pid {named.pid}", calls)
        self.assertFalse([c for c in calls if " kill" in c and re.search(rf"\b{decoy.pid}\b", c)], calls)
        self.assertIn("qs -c gutter list --json", calls)
        for call in calls:
            self.assertNotRegex(call, r"^(pkill|pgrep|killall) ", call)

    def test_no_by_name_killer_appears_in_the_script(self):
        # A static backstop for the branches a run cannot reach (a registry that cannot be read, a missing qs).
        text = Path(self.script).read_text()
        code = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))
        self.assertNotIn("pkill", code)
        self.assertNotIn("pgrep", code)
        self.assertNotIn("killall", code)

    def test_a_stale_instance_is_skipped_and_refused(self):
        dead = subprocess.Popen(["true"])
        dead.wait()
        self.instance(self.sig_old, "wayland-1", 1000)
        self.instance(self.sig_new, "wayland-7", 2000, pid=dead.pid)  # newest, but its compositor is gone
        r = self.run_script()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(f"HYPRLAND_INSTANCE_SIGNATURE={self.sig_old}", r.stdout)
        r = self.run_script("--instance", self.sig_new)
        self.assertEqual(r.returncode, 1)
        self.assertIn("not running", r.stderr)

    def test_the_compositor_this_shell_runs_in_is_refused_even_when_named(self):
        # The test process is an ancestor of the script: its pid in hyprland.lock means "this is my own session".
        self.instance(self.sig_new, "wayland-7", 2000, pid=os.getpid())
        for args in (("--force", "--instance", self.sig_new), ("--instance", self.sig_new), ()):
            r = self.run_script(*args)
            self.assertEqual(r.returncode, 1, args)
            self.assertIn("ancestor", r.stderr)
            self.assertEqual(r.stdout, "", args)

    def test_the_live_sessions_own_runtime_dir_refuses_its_instance_but_not_a_different_one(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        self.instance(self.sig_old, "wayland-1", 1000)
        live = {"GUTTER_RESCUE_LIVE_RUNTIME": str(self.run_dir)}
        for name in (self.sig_new, self.sig_old):  # the newest one, and the caller's own
            env = {**live, "HYPRLAND_INSTANCE_SIGNATURE": self.sig_old}
            r = self.run_script("--force", "--instance", name, wayland="wayland-1", env=env)
            self.assertEqual(r.returncode, 1, name)
            self.assertIn("live session", r.stderr)
        other = subprocess.Popen(["sleep", "600"])  # a compositor of its own: the pid is what is compared
        self.addCleanup(lambda: (other.kill(), other.wait()))
        run = Path(self.tmp.name) / "elsewhere"  # its own runtime dir, like a nested compositor's
        d = run / "hypr" / "cccc_500_3"
        d.mkdir(parents=True)
        (d / "hyprland.lock").write_text(f"{other.pid}\nwayland-3\n")
        r = self.run_script("--force", "--instance", "cccc_500_3", wayland="wayland-1",
                            env={**live, "XDG_RUNTIME_DIR": str(run), "HYPRLAND_INSTANCE_SIGNATURE": self.sig_old})
        self.assertEqual(r.returncode, 0, r.stderr)

    def live_setup(self):
        """The live session's runtime dir (added with GUTTER_RESCUE_LIVE_RUNTIME): its newest instance is the caller's."""
        self.instance(self.sig_new, "wayland-7", 2000)
        return {"GUTTER_RESCUE_LIVE_RUNTIME": str(self.run_dir), "HYPRLAND_INSTANCE_SIGNATURE": self.sig_new}

    def assert_refused(self, r, what, text="refusing"):
        self.assertEqual(r.returncode, 1, (what, r.stderr))
        self.assertIn(text, r.stderr, what)
        self.assertEqual(r.stdout, "", what)  # refused before the prompt: nothing would run

    def test_the_live_instance_is_refused_however_its_signature_is_spelled(self):
        env = self.live_setup()
        for spelled in (f"{self.sig_new}/", f"./{self.sig_new}", f"../hypr/{self.sig_new}", f"{self.sig_new}//"):
            r = self.run_script("--force", "--instance", spelled, wayland="wayland-7", env=env, stdin="no\n")
            self.assert_refused(r, spelled, "bare signature")

    def test_a_signature_with_other_characters_is_refused(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        for bad in ("a b", "a-b", "a.b", "a;b", "$(id)", "a\nb", ".", ".."):
            r = self.run_script("--instance", bad, stdin="no\n")
            self.assert_refused(r, bad, "bare signature")
            r = self.run_script(stdin="no\n", env={"HYPRLAND_INSTANCE_SIGNATURE": bad})
            self.assert_refused(r, f"env {bad!r}", "not a Hyprland instance signature")

    def test_the_live_runtime_dir_is_refused_however_it_is_spelled(self):
        env = self.live_setup()
        link = Path(self.tmp.name) / "live-link"
        link.symlink_to(self.run_dir)
        for spelled in (f"{self.run_dir}/", f"{self.run_dir}//", f"{self.run_dir}/hypr/..", str(link), f"{link}/"):
            r = self.run_script("--force", "--instance", self.sig_new, wayland="wayland-7", stdin="no\n",
                                env={**env, "XDG_RUNTIME_DIR": spelled})
            self.assert_refused(r, spelled, "live session")
            # The added live dir may be spelled any way too.
            r = self.run_script("--force", "--instance", self.sig_new, wayland="wayland-7", stdin="no\n",
                                env={**env, "GUTTER_RESCUE_LIVE_RUNTIME": spelled})
            self.assert_refused(r, f"live {spelled}", "live session")

    def test_the_live_compositor_is_refused_through_another_folder_by_its_pid(self):
        env = self.live_setup()
        other = Path(self.tmp.name) / "other"
        d = other / "hypr" / "zzzz_9_9"
        d.mkdir(parents=True)
        (d / "hyprland.lock").write_text(f"{self.compositor.pid}\nwayland-7\n")  # the live compositor's pid
        r = self.run_script("--force", "--instance", "zzzz_9_9", wayland="wayland-7", stdin="no\n",
                            env={**env, "XDG_RUNTIME_DIR": str(other)})
        self.assert_refused(r, "same pid", f"compositor pid {self.compositor.pid}")
        # Also when only the newest live instance has that pid (the caller's signature names none there).
        r = self.run_script("--force", "--instance", "zzzz_9_9", wayland="wayland-7", stdin="no\n",
                            env={**env, "XDG_RUNTIME_DIR": str(other), "HYPRLAND_INSTANCE_SIGNATURE": "nope_1_1"})
        self.assert_refused(r, "same pid, newest", "live session")
        # A pid written with a leading zero is the same pid.
        (d / "hyprland.lock").write_text(f"0{self.compositor.pid}\nwayland-7\n")
        r = self.run_script("--force", "--instance", "zzzz_9_9", wayland="wayland-7", stdin="no\n",
                            env={**env, "XDG_RUNTIME_DIR": str(other)})
        self.assert_refused(r, "same pid, leading zero", f"compositor pid {self.compositor.pid}")

    def test_a_nested_compositor_is_accepted(self):
        # As after `eval "$(scripts/lock-nested.sh env)"`: its own runtime dir, signature, display and compositor pid.
        env = self.live_setup()
        nested = subprocess.Popen(["sleep", "600"])
        self.addCleanup(lambda: (nested.kill(), nested.wait()))
        run = Path(self.tmp.name) / "gn" / "run"
        d = run / "hypr" / "nest_1_1"
        d.mkdir(parents=True)
        (d / "hyprland.lock").write_text(f"{nested.pid}\nwayland-1\n")
        r = self.run_script("--force", "--instance", "nest_1_1", wayland="wayland-1",
                            env={**env, "XDG_RUNTIME_DIR": str(run), "HYPRLAND_INSTANCE_SIGNATURE": "nest_1_1"})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("would use: HYPRLAND_INSTANCE_SIGNATURE=nest_1_1 WAYLAND_DISPLAY=wayland-1", r.stdout)

    def test_the_real_runtime_dir_is_checked_even_with_a_test_live_dir(self):
        # GUTTER_RESCUE_LIVE_RUNTIME only adds a dir: the real /run/user/<uid> is still compared. Dry run, answer "no",
        # and only to see the refusal; skipped without a live Hyprland.
        real = Path(f"/run/user/{os.getuid()}/hypr")
        newest = None
        if real.is_dir():
            for d in sorted(real.iterdir(), key=lambda d: d.stat().st_mtime, reverse=True):
                try:
                    pid = int((d / "hyprland.lock").read_text().split("\n")[0])
                    os.kill(pid, 0)
                except (OSError, ValueError):
                    continue
                if re.fullmatch(r"[A-Za-z0-9_]+", d.name):
                    newest = d.name
                break
        if newest is None:
            self.skipTest("no live Hyprland instance")
        r = self.run_script("--force", "--instance", newest, wayland="wayland-x", stdin="no\n",
                            env={"XDG_RUNTIME_DIR": f"/run/user/{os.getuid()}/",
                                 "GUTTER_RESCUE_LIVE_RUNTIME": str(self.run_dir)})
        self.assert_refused(r, "real live dir", "live session")

    def test_force_with_a_named_instance_or_another_one_goes_on(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        self.instance(self.sig_old, "wayland-1", 1000)
        r = self.run_script("--force", "--instance", self.sig_new, wayland="wayland-7",
                            env={"HYPRLAND_INSTANCE_SIGNATURE": self.sig_new})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(f"HYPRLAND_INSTANCE_SIGNATURE={self.sig_new}", r.stdout)
        r = self.run_script("--force", "--instance", self.sig_old, wayland="wayland-7",
                            env={"HYPRLAND_INSTANCE_SIGNATURE": self.sig_new})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("WAYLAND_DISPLAY=wayland-1", r.stdout)
        self.assertEqual(self.run_script("--instance").returncode, 2)

    def test_the_restart_advice_goes_through_the_compositor(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        bin_dir, log = self.shims()
        r = self.run_script(env={"GUTTER_RESCUE_DRY": "", "PATH": f"{bin_dir}:{self.path}"})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("""hyprctl eval 'hl.exec_cmd("qs -c gutter -n -d")'""", r.stderr)
        self.assertIn(f"HYPRLAND_INSTANCE_SIGNATURE={self.sig_new}", r.stderr)

    def fake_qs(self, sig):
        """A live process whose name (comm) is qs and whose environment names that Hyprland instance."""
        fake = self.run_dir / "fakebin"
        fake.mkdir(exist_ok=True)
        if not (fake / "qs").exists():
            (fake / "qs").symlink_to(shutil.which("sleep"))
        env = {k: v for k, v in os.environ.items() if k != "HYPRLAND_INSTANCE_SIGNATURE"}
        if sig:
            env["HYPRLAND_INSTANCE_SIGNATURE"] = sig
        p = subprocess.Popen([str(fake / "qs"), "60"], env=env)
        self.addCleanup(lambda: (p.kill(), p.wait()))
        return p

    def test_real_run_ends_the_lock_screen_before_the_rescue_shell(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        bin_dir, log = self.shims()
        lock_screen = self.fake_qs(self.sig_new)
        self.list_shim(bin_dir, log, lock_screen.pid)
        r = self.run_script(env=self.real_env(bin_dir))
        self.assertEqual(r.returncode, 0, r.stderr)
        calls = log.read_text().splitlines()
        self.assertLess(calls.index(f"qs -c gutter kill --pid {lock_screen.pid}"), calls.index(f"qs -p {ROOT}/lockscreen/rescue"))
        self.assertIn("qs -c gutter list --json", calls)

    def list_shim(self, bin_dir, log, *pids):
        """A `qs` that logs its call and answers `list --json` with one instance of each of those pids."""
        entries = ",\n".join(f'    {{\n        "id": "x{pid}",\n        "pid": {pid}\n    }}' for pid in pids)
        (bin_dir / "qs").write_text(f"""#!/bin/sh
echo "qs $*" >> {log}
case "$*" in
  *"list --json"*) cat <<JSON
[
{entries}
]
JSON
;;
esac
exit 0
""")

    def real_env(self, bin_dir, **extra):
        return {"GUTTER_RESCUE_DRY": "", "PATH": f"{bin_dir}:{self.path}",
                "GUTTER_LOCK_HINT_FILE": str(self.run_dir / "hint"), **extra}

    def test_a_lock_screen_that_does_not_end_is_killed_by_the_pid_the_registry_names(self):
        # A hung client ignores `kill`; the pid `qs list --json` names (the target's registry) is SIGKILLed.
        self.instance(self.sig_new, "wayland-7", 2000)
        bin_dir, log = self.shims()
        fake = self.run_dir / "fakebin"
        fake.mkdir()
        (fake / "qs").symlink_to(shutil.which("sleep"))  # a process whose name (comm) is qs
        hung = subprocess.Popen([str(fake / "qs"), "60"], env={**os.environ, "HYPRLAND_INSTANCE_SIGNATURE": self.sig_new})
        self.addCleanup(lambda: (hung.kill(), hung.wait()))
        self.list_shim(bin_dir, log, hung.pid)
        r = self.run_script(env=self.real_env(bin_dir))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(f"pid {hung.pid}", r.stderr)
        self.assertEqual(hung.wait(timeout=5), -9)
        self.assertIn(f"qs -c gutter kill --pid {hung.pid}", log.read_text().splitlines())  # asked first

    def test_a_qs_of_another_instance_is_left_running(self):
        # The registry is the target's, but the pid's own environment must also name the target instance.
        self.instance(self.sig_new, "wayland-7", 2000)
        bin_dir, log = self.shims()
        fake = self.run_dir / "fakebin"
        fake.mkdir()
        (fake / "qs").symlink_to(shutil.which("sleep"))
        for env_sig in (self.sig_old, None):
            env = {k: v for k, v in os.environ.items() if k != "HYPRLAND_INSTANCE_SIGNATURE"}
            if env_sig:
                env["HYPRLAND_INSTANCE_SIGNATURE"] = env_sig
            other = subprocess.Popen([str(fake / "qs"), "60"], env=env)
            self.addCleanup(lambda p=other: (p.kill(), p.wait()))
            self.list_shim(bin_dir, log, other.pid)
            r = self.run_script(env=self.real_env(bin_dir))
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("left running", r.stderr)
            self.assertIsNone(other.poll(), env_sig)
            self.assertNotIn(f"kill --pid {other.pid}", log.read_text(), env_sig)  # not even asked to quit

    def test_a_pid_that_is_not_a_qs_is_left_alone(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        other = subprocess.Popen(["sleep", "60"])
        self.addCleanup(lambda: (other.kill(), other.wait()))
        bin_dir, log = self.shims()
        self.list_shim(bin_dir, log, other.pid)
        r = self.run_script(env=self.real_env(bin_dir))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIsNone(other.poll())

    def test_a_rescue_shell_that_times_out_says_so_and_keeps_the_hint(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        bin_dir, log = self.shims()
        (bin_dir / "qs").write_text(f"""#!/bin/sh
echo "qs $*" >> {log}
case "$*" in
  *lockscreen/rescue*) exec sleep 30 ;;
esac
exit 0
""")
        r = self.run_script(env={"GUTTER_RESCUE_DRY": "", "PATH": f"{bin_dir}:{self.path}",
                                 "GUTTER_LOCK_HINT_FILE": str(self.run_dir / "hint"), "GUTTER_RESCUE_TIMEOUT": "0.2"})
        self.assertEqual(r.returncode, 124)
        self.assertIn("did not finish within 0.2 s", r.stderr)
        self.assertIn("still locked", r.stderr)
        self.assertEqual((self.run_dir / "hint").read_text(), "true\n")
        self.assertNotIn("Unlocked", r.stderr)

    def test_a_failing_rescue_shell_says_so(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        bin_dir, log = self.shims(qs_exit=3)
        r = self.run_script(env={"GUTTER_RESCUE_DRY": "", "PATH": f"{bin_dir}:{self.path}",
                                 "GUTTER_LOCK_HINT_FILE": str(self.run_dir / "hint")})
        self.assertEqual(r.returncode, 3)
        self.assertIn("rescue shell failed (exit 3)", r.stderr)

    def test_a_missing_restore_option_aborts_before_anything_is_ended(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        bin_dir, log = self.shims()
        (bin_dir / "hyprctl").write_text(f"""#!/bin/sh
echo "hyprctl $*" >> {log}
case "$1" in -j) echo '{{"option": "misc:allow_session_lock_restore", "bool": false}}' ;; esac
exit 1
""")
        r = self.run_script(env=self.real_env(bin_dir))
        self.assertEqual(r.returncode, 1)
        self.assertIn("could not turn on misc:allow_session_lock_restore", r.stderr)
        self.assertIn("nothing was ended", r.stderr)
        calls = log.read_text()
        self.assertIn("hyprctl keyword misc:allow_session_lock_restore 1", calls)
        self.assertNotIn("qs ", calls)  # no kill, no list, no rescue shell
        self.assertNotIn("busctl", calls)
        self.assertEqual((self.run_dir / "hint").read_text(), "true\n")
        self.assertNotIn("Unlocked", r.stderr)

    def test_a_dry_run_still_prints_everything_without_the_option_check(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        r = self.run_script()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.commands(r)), 5, r.stdout)

    def test_the_prompt_says_it_ends_the_lock_screen(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        r = self.run_script(stdin="no\n")
        self.assertEqual(r.returncode, 2)
        self.assertIn("ends the Gutter lock screen", r.stderr)

    def test_the_rescue_shell_gives_up_instead_of_hanging(self):
        # A refused lock (a live client holds it) or an unconfirmed one ends the rescue shell with status 1.
        qml = (ROOT / "lockscreen/rescue/shell.qml").read_text()
        self.assertRegex(qml, r"Qt\.exit\(1\)")
        self.assertRegex(qml, r"onLockedChanged:")
        self.assertRegex(qml, r"id: giveUp")
        self.assertRegex(qml, r"giveUpMs:\s*5000")

    def test_rescue_shell_has_a_lock_surface_and_releases_by_locked(self):
        # WlSessionLock needs a WlSessionLockSurface (a plain Item as `surface` is refused: "does not create a
        # WlSessionLockSurface. Aborting lock"), and has no callable unlock(): the nested run found both.
        qml = (ROOT / "lockscreen/rescue/shell.qml").read_text()
        self.assertRegex(qml, r"WlSessionLockSurface\s*\{")
        self.assertNotRegex(qml, r"surface:\s*Rectangle")
        self.assertNotIn(".unlock()", qml)
        self.assertRegex(qml, r"locked:\s*root\.wanted")
        self.assertRegex(qml, r"root\.wanted\s*=\s*false")


    # --- which pid is the compositor's -------------------------------------------------------------------------

    def set_lock(self, sig, text):
        """Replace what an instance's hyprland.lock says (its second line is the display)."""
        (self.run_dir / "hypr" / sig / "hyprland.lock").write_text(text)

    def test_a_lock_that_names_no_plain_pid_above_one_is_stale(self):
        # kill -0 0 signals this process group and kill -0 -N a whole group, so a "live" answer for them would be false.
        self.instance(self.sig_old, "wayland-1", 1000)
        self.instance(self.sig_new, "wayland-7", 2000)
        for first in ("0", "00", "-1", "-0", "1", "abc", "", "1 2", "1e3", "+5", "99999999999999999999"):
            self.set_lock(self.sig_new, f"{first}\nwayland-7\n")
            r = self.run_script("--instance", self.sig_new)
            self.assert_refused(r, first, "rescue-unlock:")
            self.assertRegex(r.stderr, "not running|does not name", first)
            # Not picked as the newest live instance either: the older one is.
            r = self.run_script()
            self.assertEqual(r.returncode, 0, (first, r.stderr))
            self.assertIn(f"HYPRLAND_INSTANCE_SIGNATURE={self.sig_old}", r.stdout, first)
        self.set_lock(self.sig_new, "-1\n")  # not even a display line
        self.assert_refused(self.run_script("--instance", self.sig_new), "-1 only", "rescue-unlock:")

    def test_a_live_pid_written_with_leading_zeros_is_fine(self):
        self.instance(self.sig_new, "wayland-7", 2000, pid=f"000{self.compositor.pid}")
        r = self.run_script("--instance", self.sig_new)
        self.assertEqual(r.returncode, 0, r.stderr)

    def bind(self, sig, root=None):
        """A listening unix socket at <root>/hypr/<sig>/.socket.sock served by THIS process (the test's)."""
        path = (root or self.run_dir) / "hypr" / sig / ".socket.sock"
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.bind(str(path))
        sock.listen(8)
        self.addCleanup(sock.close)
        return sock

    def serve(self, sig, root=None, *also):
        """The instance's socket (and any other listed paths) held by another live process, which counts the
        connections it accepts in self.accepted(); returns the process."""
        paths = [str((root or self.run_dir) / "hypr" / sig / ".socket.sock"), *map(str, also)]
        counter = self.run_dir / f"accepted-{len(list(self.run_dir.glob('accepted-*')))}"
        counter.touch()  # claims the name (a second serve() in the same test gets the next one)
        proc = subprocess.Popen(
            [sys.executable, "-c", "import selectors,socket,sys\n"
             "sel=selectors.DefaultSelector()\n"
             "for p in sys.argv[2:]:\n"
             "    s=socket.socket(socket.AF_UNIX);s.bind(p);s.listen(8);sel.register(s,selectors.EVENT_READ)\n"
             "print('ready',flush=True)\n"
             "while True:\n"
             "    for k,_ in sel.select():\n"
             "        c=k.fileobj.accept()[0];open(sys.argv[1],'a').write('x');c.close()\n", str(counter), *paths],
            stdout=subprocess.PIPE, text=True)
        self.addCleanup(lambda: (proc.kill(), proc.wait(), proc.stdout.close()))
        self.assertEqual(proc.stdout.readline().strip(), "ready")
        proc.counter = counter
        return proc

    def accepted(self, proc):
        """How many connections the process served by self.serve() has accepted."""
        return len(proc.counter.read_text())

    def test_the_socket_holder_is_the_compositor_not_the_pid_in_the_lock(self):
        # The lock names an ordinary live process, but the socket is served by this very test process, an ancestor of
        # the script: the socket tells the truth, so the instance is this shell's own compositor.
        self.instance(self.sig_new, "wayland-7", 2000)
        self.bind(self.sig_new)
        for args in (("--instance", self.sig_new), ()):
            r = self.run_script(*args)
            self.assert_refused(r, args, "ancestor")
            self.assertIn(f"names pid {self.compositor.pid}, but the socket of instance {self.sig_new} is held by pid {os.getpid()}; trusting the socket", r.stderr)

    def test_a_stale_lock_pid_does_not_matter_when_the_socket_is_served_by_another_process(self):
        # The lock names a pid that is an ancestor (a reused pid, say); the socket's real server is not.
        self.instance(self.sig_new, "wayland-7", 2000, pid=os.getpid())
        server = self.serve(self.sig_new)
        r = self.run_script("--instance", self.sig_new)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("trusting the socket", r.stderr)
        self.assertIn(f"held by pid {server.pid}", r.stderr)
        # A dead pid in the lock too.
        dead = subprocess.Popen(["true"])
        dead.wait()
        self.set_lock(self.sig_new, f"{dead.pid}\nwayland-7\n")
        r = self.run_script("--instance", self.sig_new)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_a_lock_and_a_socket_that_agree_say_nothing(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        server = self.serve(self.sig_new)
        self.set_lock(self.sig_new, f"{server.pid}\nwayland-7\n")
        r = self.run_script("--instance", self.sig_new)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stderr.count("trusting"), 0)

    def test_without_a_usable_socket_the_lock_is_trusted(self):
        # No socket file: the lock's pid (an ancestor here) decides, as before.
        self.instance(self.sig_new, "wayland-7", 2000, pid=os.getpid())
        self.assert_refused(self.run_script("--instance", self.sig_new), "no socket", "ancestor")
        # A socket file nobody serves any more (nothing holds it), and a plain file in its place.
        sock = self.bind(self.sig_new)
        sock.close()
        r = self.run_script("--instance", self.sig_new)
        self.assert_refused(r, "stale socket", "ancestor")
        self.assertNotIn("trusting", r.stderr)
        (self.run_dir / "hypr" / self.sig_new / ".socket.sock").unlink()
        (self.run_dir / "hypr" / self.sig_new / ".socket.sock").write_text("")
        self.assert_refused(self.run_script("--instance", self.sig_new), "not a socket", "ancestor")

    def test_without_python3_the_lock_is_trusted(self):
        self.instance(self.sig_new, "wayland-7", 2000, pid=os.getpid())
        self.serve(self.sig_new)  # would make the instance acceptable if it were asked
        # A PATH with the tools the script needs, but no python3.
        tools = self.run_dir / "tools"
        tools.mkdir()
        for name in ("sed", "cat", "tr", "grep", "ls", "id", "timeout", "sleep", "kill", "dirname", "env", "bash"):
            if shutil.which(name):
                (tools / name).symlink_to(shutil.which(name))
        r = self.run_script("--instance", self.sig_new, env={"PATH": str(tools)})
        self.assert_refused(r, "no python3", "ancestor")

    def test_the_script_never_connects_to_a_socket(self):
        # Finding the compositor's pid must not talk to the compositor: a listening socket in the instance folder (and
        # the Wayland one) sees no connection in any mode, for the target and for every live instance compared with it.
        env = self.live_setup()
        server = self.serve(self.sig_new, None, self.run_dir / "wayland-7")
        self.set_lock(self.sig_new, f"{server.pid}\nwayland-7\n")
        other = subprocess.Popen(["sleep", "600"])
        self.addCleanup(lambda: (other.kill(), other.wait()))
        run = self.other_runtime("t_nest", other.pid)
        self.assertEqual(self.run_script("--instance", self.sig_new, env={"HYPRLAND_INSTANCE_SIGNATURE": ""}).returncode, 0)
        self.assertEqual(self.run_script(stdin="no\n").returncode, 2)
        r = self.run_script("--force", "--instance", "t_nest", wayland="wayland-1", env={**env, "XDG_RUNTIME_DIR": str(run)})
        self.assertEqual(r.returncode, 0, r.stderr)
        r = self.run_script("--force", "--instance", self.sig_new, wayland="wayland-1", stdin="no\n", env=env)
        self.assertEqual(r.returncode, 1)  # refused: it is the live instance, found through the held socket
        self.assertNotIn("trusting", r.stderr)  # the refusal above shows the server was found as the holder
        # Now the test connects once to each of the two served paths itself and reads to EOF: the server counts a
        # connection before it closes it, and a socket's backlog is first in, first out, so by then every earlier
        # connection (the script's, if it had made any) is counted and the total is exact.
        for path in (self.run_dir / "hypr" / self.sig_new / ".socket.sock", self.run_dir / "wayland-7"):
            with socket.socket(socket.AF_UNIX) as c:
                c.settimeout(5)
                c.connect(str(path))
                self.assertEqual(c.recv(1), b"")
        self.assertEqual(self.accepted(server), 2)
        # And the script's text has no way to connect.
        code = "\n".join(l for l in Path(self.script).read_text().splitlines() if not l.lstrip().startswith("#"))
        for word in ("connect", "SO_PEERCRED", "nc ", "socat", "/dev/tcp"):
            self.assertNotIn(word, code)

    def test_a_forged_line_in_a_socket_path_does_not_name_a_holder(self):
        # A socket whose path holds a newline and a made-up /proc/net/unix line for the instance's socket (it can only
        # reuse an inode that a real line has too). The lock is then trusted, as when no holder is found.
        self.instance(self.sig_new, "wayland-7", 2000)
        target = self.run_dir / "hypr" / self.sig_new / ".socket.sock"
        self.bind(self.sig_new).close()  # the socket file stays, nobody listens: no real holder
        evil_root = self.run_dir / "evil"
        evil_root.mkdir()
        evil = subprocess.Popen(
            [sys.executable, "-c", "import os,socket,sys\n"
             "s=socket.socket(socket.AF_UNIX)\n"
             "ino=os.fstat(s.fileno()).st_ino\n"
             "forged='x\\n0: 2 0 10000 1 1 %d %s' % (ino, sys.argv[1])\n"  # relative: starts under the cwd
             "os.makedirs(os.path.dirname(forged))\n"
             "s.bind(forged);s.listen(1)\n"
             "print('ready',flush=True);import time;time.sleep(600)\n", str(target)],
            cwd=evil_root, stdout=subprocess.PIPE, text=True)
        self.addCleanup(lambda: (evil.kill(), evil.wait(), evil.stdout.close()))
        self.assertEqual(evil.stdout.readline().strip(), "ready")
        listing = Path("/proc/net/unix").read_bytes()
        self.assertIn(b"\n0: 2 0 10000 1 1 ", listing)  # the fake line really is in the table
        r = self.run_script("--instance", self.sig_new)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("trusting", r.stderr)  # the forged holder was not taken for the compositor
        self.assertNotIn(str(evil.pid), r.stderr)

    def test_the_wayland_display_must_be_a_bare_name(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        for display in ("../x", "/run/user/1/wayland-0", "a/b", ".", "..", "a b", "wayland-1;id", "\x1b[31mred"):
            self.set_lock(self.sig_new, f"{self.compositor.pid}\n{display}\n")
            r = self.run_script("--instance", self.sig_new)
            self.assert_refused(r, display, "not a bare socket name")
            self.assertEqual(len(r.stderr.splitlines()), 1, (display, r.stderr))
            self.assertNotIn("\x1b", r.stderr)
        for display in ("wayland-1", "wayland-1.x", "w_0", "x11"):
            self.set_lock(self.sig_new, f"{self.compositor.pid}\n{display}\n")
            r = self.run_script("--instance", self.sig_new)
            self.assertEqual(r.returncode, 0, (display, r.stderr))
            self.assertIn(f"WAYLAND_DISPLAY={display}", r.stdout)

    def test_the_wayland_socket_must_be_held_by_the_compositor(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        compositor = self.serve(self.sig_new)  # holds the instance's socket: the compositor
        # The Wayland socket named in the lock is held by some other process: refused.
        stranger = subprocess.Popen([sys.executable, "-c", "import socket,sys,time;s=socket.socket(socket.AF_UNIX);"
                                     "s.bind(sys.argv[1]);s.listen(1);print('ready',flush=True);time.sleep(600)",
                                     str(self.run_dir / "wayland-7")], stdout=subprocess.PIPE, text=True)
        self.addCleanup(lambda: (stranger.kill(), stranger.wait(), stranger.stdout.close()))
        self.assertEqual(stranger.stdout.readline().strip(), "ready")
        r = self.run_script("--instance", self.sig_new)
        self.assert_refused(r, "stranger", f"held by pid {stranger.pid}, not by the compositor pid {compositor.pid}")
        # Another display, whose socket nobody serves, goes on (the holder cannot be found).
        self.set_lock(self.sig_new, f"{compositor.pid}\nwayland-8\n")
        r = self.run_script("--instance", self.sig_new)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_the_wayland_socket_held_by_the_compositor_goes_on(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        compositor = self.serve(self.sig_new, None, self.run_dir / "wayland-7")
        self.set_lock(self.sig_new, f"{compositor.pid}\nwayland-7\n")
        r = self.run_script("--instance", self.sig_new)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("refusing", r.stderr)

    def test_a_time_setting_that_is_no_number_is_refused_before_the_prompt(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        for name in ("GUTTER_RESCUE_POLL", "GUTTER_RESCUE_SETTLE", "GUTTER_RESCUE_KILL_TIMEOUT", "GUTTER_RESCUE_TIMEOUT"):
            for bad in ("abc", "-1", "1e3", ".5", "5.", "1 2", "5s", "\x1b[31m", "0x10"):
                r = self.run_script(env={name: bad})
                self.assertEqual(r.returncode, 2, (name, bad, r.stderr))
                self.assertIn(name, r.stderr)
                self.assertEqual(r.stdout, "")
                self.assertNotIn("\x1b", r.stderr)
                self.assertNotIn("Type the word", r.stderr)  # before the prompt
            for good in ("5", "0.25", "10.5", "0.1"):
                self.assertEqual(self.run_script(env={name: good}).returncode, 0, (name, good))
        for name in ("GUTTER_RESCUE_POLL", "GUTTER_RESCUE_SETTLE"):  # no wait at all is fine
            self.assertEqual(self.run_script(env={name: "0"}).returncode, 0, name)
        for name in ("GUTTER_RESCUE_KILL_TIMEOUT", "GUTTER_RESCUE_TIMEOUT"):  # `timeout 0` has no limit: refused
            for zero in ("0", "00", "0.0", "0.000"):
                r = self.run_script(env={name: zero})
                self.assertEqual(r.returncode, 2, (name, zero))
                self.assertIn("above 0", r.stderr)
                self.assertEqual(r.stdout, "")
                self.assertNotIn("Type the word", r.stderr)  # before the prompt

    def test_a_socket_with_an_odd_path_elsewhere_does_not_end_the_lookup(self):
        # Anyone can bind a socket at a path that is not UTF-8 (or holds a newline); /proc/net/unix lists it too.
        self.instance(self.sig_new, "wayland-7", 2000)
        base = os.fsencode(str(self.run_dir))
        for odd in (b"/\xff\xfe.sock", b"/line\n0000000000000000: 00000002 00000000 00010000 0001 01 1 x.sock"):
            sock = socket.socket(socket.AF_UNIX)
            sock.bind(base + odd)
            sock.listen(1)
            self.addCleanup(sock.close)
        server = self.serve(self.sig_new)
        r = self.run_script("--instance", self.sig_new)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(f"is held by pid {server.pid}; trusting the socket", r.stderr)

    # --- the live session: every live instance ------------------------------------------------------------------

    def other_runtime(self, sig, pid):
        """A runtime dir of its own (like a nested compositor's) holding one instance of that compositor pid."""
        run = Path(self.tmp.name) / f"run-{sig}"
        d = run / "hypr" / sig
        d.mkdir(parents=True)
        (d / "hyprland.lock").write_text(f"{pid}\nwayland-9\n")
        return run

    def test_every_live_instance_is_compared_not_only_the_callers_and_the_newest(self):
        env = self.live_setup()  # sig_new: the caller's and the newest
        middle = subprocess.Popen(["sleep", "600"])
        oldest = subprocess.Popen(["sleep", "600"])
        for p in (middle, oldest):
            self.addCleanup(lambda p=p: (p.kill(), p.wait()))
        self.instance("mmmm_1500_5", "wayland-5", 1500, pid=middle.pid)
        self.instance(self.sig_old, "wayland-1", 1000, pid=oldest.pid)
        for compositor in (middle, oldest):
            run = self.other_runtime(f"t_{compositor.pid}", compositor.pid)
            r = self.run_script("--force", "--instance", f"t_{compositor.pid}", wayland="wayland-1", stdin="no\n",
                                env={**env, "XDG_RUNTIME_DIR": str(run)})
            self.assert_refused(r, compositor.pid, f"compositor pid {compositor.pid}")
            self.assertIn("live session", r.stderr)
        # A compositor none of them has is still fine, and so is a dead instance's folder.
        free = subprocess.Popen(["sleep", "600"])
        self.addCleanup(lambda: (free.kill(), free.wait()))
        run = self.other_runtime("t_free", free.pid)
        r = self.run_script("--force", "--instance", "t_free", wayland="wayland-1", env={**env, "XDG_RUNTIME_DIR": str(run)})
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_the_live_comparison_goes_by_the_socket_pid_too(self):
        env = self.live_setup()
        # A live instance whose lock is stale (names the ordinary process) but whose socket is served by the real one.
        real = self.serve(self.sig_new)
        self.assertNotEqual(real.pid, self.compositor.pid)
        run = self.other_runtime("t_real", real.pid)
        r = self.run_script("--force", "--instance", "t_real", wayland="wayland-1", stdin="no\n",
                            env={**env, "XDG_RUNTIME_DIR": str(run)})
        self.assert_refused(r, "socket pid", f"compositor pid {real.pid}")
        # The lock's pid alone no longer makes an instance the live one: its socket says another process serves it.
        run = self.other_runtime("t_stale", self.compositor.pid)
        r = self.run_script("--force", "--instance", "t_stale", wayland="wayland-1", env={**env, "XDG_RUNTIME_DIR": str(run)})
        self.assertEqual(r.returncode, 0, r.stderr)

    # --- ending only the target's lock screen ------------------------------------------------------------------

    def test_a_lock_screen_of_another_hyprland_instance_is_never_sent_kill(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        bin_dir, log = self.shims()
        mine = self.fake_qs(self.sig_new)
        theirs = self.fake_qs(self.sig_old)
        nobody = self.fake_qs(None)
        self.list_shim(bin_dir, log, theirs.pid, mine.pid, nobody.pid)
        r = self.run_script(env=self.real_env(bin_dir))
        self.assertEqual(r.returncode, 0, r.stderr)
        calls = log.read_text().splitlines()
        self.assertIn(f"qs -c gutter kill --pid {mine.pid}", calls)
        self.assertNotIn("qs -c gutter kill", calls)  # never the bare one, which asks only the oldest instance
        for other in (theirs, nobody):
            self.assertFalse([c for c in calls if " kill" in c and str(other.pid) in c], (other.pid, calls))
            self.assertIsNone(other.poll())
        self.assertEqual(mine.wait(timeout=5), -9)  # it ignored the request, so it was killed by pid
        self.assertIn("left running", r.stderr)

    def test_a_replaced_kill_command_runs_wholesale_and_alone(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        bin_dir, log = self.shims()
        (bin_dir / "my-kill").write_text(f'#!/bin/sh\necho "my-kill $*" >> {log}\n')
        (bin_dir / "my-kill").chmod(0o755)
        mine = self.fake_qs(self.sig_new)
        self.list_shim(bin_dir, log, mine.pid)
        r = self.run_script(env=self.real_env(bin_dir, GUTTER_RESCUE_KILL_CMD="my-kill --now"))
        self.assertEqual(r.returncode, 0, r.stderr)
        calls = log.read_text().splitlines()
        self.assertEqual([c for c in calls if c.startswith("my-kill")], ["my-kill --now"])
        self.assertFalse([c for c in calls if " kill " in c], calls)

    # --- what a refusal echoes ---------------------------------------------------------------------------------

    def test_refusals_never_echo_raw_escape_sequences_or_newlines(self):
        self.instance(self.sig_new, "wayland-7", 2000)
        evil = "\x1b[31mred\nsecond line\r\x07"
        for how in ("arg", "env"):
            if how == "arg":
                r = self.run_script("--instance", evil, stdin="no\n")
            else:
                r = self.run_script(stdin="no\n", env={"HYPRLAND_INSTANCE_SIGNATURE": evil})
            self.assert_refused(r, how)
            self.assertIn("??31mred?second?line??", r.stderr, how)
            self.assertEqual(len(r.stderr.splitlines()), 1, (how, r.stderr))
            for bad in ("\x1b", "\r", "\x07"):
                self.assertNotIn(bad, r.stderr, how)

    def test_a_long_bad_signature_is_cut(self):
        for how in ("arg", "env"):
            long = "a-" * 100
            if how == "arg":
                r = self.run_script("--instance", long, stdin="no\n")
            else:
                r = self.run_script(stdin="no\n", env={"HYPRLAND_INSTANCE_SIGNATURE": long})
            self.assert_refused(r, how)
            self.assertIn("'" + "a?" * 20 + "...'", r.stderr, how)
            self.assertLess(len(r.stderr), 300, how)
        # A short, valid-looking one is shown whole.
        r = self.run_script("--instance", "ab-cd", stdin="no\n")
        self.assertIn("'ab?cd'", r.stderr)


class LockRelease(unittest.TestCase):
    """The real lock is released by clearing `held` (WlSessionLock.locked is bound to it). Source-level, because
    LockScreen needs a compositor's session-lock protocol and cannot be instantiated in qmltestrunner; the nested
    run (scripts/lock-nested-check.sh) is the behavioural check, except for finishUnlock (the password path), which it
    still does not cover. WlSessionLock has no callable unlock(): calling it is a TypeError that left the screen faded
    and locked. Issue #23: stable Quickshell 0.3.2 sends no `lockedChanged` after a release or a lock that was ended,
    so the state Lock publishes follows `held` and `confirmed`, never `lock.locked` / `lock.secure` read back."""

    def setUp(self):
        self.qml = (ROOT / "lockscreen/LockScreen.qml").read_text()

    def finish_unlock(self):
        m = re.search(r"function finishUnlock\(\): void \{.*?\n    \}\n", self.qml, re.S)
        self.assertIsNotNone(m)
        return m.group(0)

    def secure_changed(self):
        m = re.search(r"onSecureChanged: \{\n(.*?)\n        \}\n", self.qml, re.S)
        self.assertIsNotNone(m)
        return m.group(1)

    def test_no_unlock_call(self):
        code = "\n".join(l for l in self.qml.splitlines() if not l.lstrip().startswith("//"))
        self.assertNotRegex(code, r"\bunlock\s*\(")

    def test_unlock_path_clears_held_and_locked_follows_it(self):
        self.assertRegex(self.finish_unlock(), r"persisted\.held\s*=\s*false")
        self.assertRegex(self.qml, r"locked:\s*persisted\.held")

    def test_published_state_is_not_bound_to_the_lock_object(self):
        # A binding on `lock.locked` would stay true on stable after the release (no notify).
        values = dict(re.findall(r'Binding \{\n\s*target: Lock\n\s*property: "(\w+)"\n\s*value: ([^\n]*)\n', self.qml))
        self.assertEqual(set(values), {"locked", "secure"})
        for prop, value in values.items():
            with self.subTest(prop=prop):
                self.assertNotRegex(value, r"\block\.(locked|secure)\b")

    def test_release_clears_confirmed_before_held(self):
        # Lock does not wait for a signal stable never sends: our PAM success says the lock is over.
        body = self.finish_unlock()
        confirmed = body.find("root.confirmed = false;")
        held = body.find("persisted.held = false;")
        self.assertNotEqual(confirmed, -1)
        self.assertNotEqual(held, -1)
        self.assertLess(confirmed, held)

    def test_secure_changed_sets_confirmed_first(self):
        statements = [l.strip() for l in self.secure_changed().splitlines()
                      if l.strip() and not l.lstrip().startswith("//")]
        self.assertEqual(statements[0], "root.confirmed = secure;")

    def test_secure_lost_looks_again_for_the_ended_lock(self):
        # Stable sends no `lockedChanged` when a lock is ended: the false branch must schedule releaseEnded itself.
        m = re.search(r"\} else \{\n(.*?)\n            \}", self.secure_changed(), re.S)
        self.assertIsNotNone(m)
        code = "\n".join(l for l in m.group(1).splitlines() if not l.lstrip().startswith("//"))
        self.assertIn("Qt.callLater(root.releaseEnded)", code)


class NestedHarness(unittest.TestCase):
    """scripts/lock-nested.sh: its guard rails, and in dry run (GUTTER_NESTED_DRY=1) the commands it would run. The
    tests that run it for real put recording stand-ins first on PATH (for loginctl, pkill, hyprctl and the like, and
    a Hyprland, a dbus-daemon and a qs that only play their part), so no test starts a real Hyprland, qs or bus."""

    script = str(ROOT / "scripts/lock-nested.sh")
    outer_sig = "outer0000_1_1"

    def setUp(self):
        # A short base under /tmp whatever TMPDIR is: the harness refuses a long folder (socket paths), except in dry run.
        self.tmp = tempfile.TemporaryDirectory(prefix="gnt", dir="/tmp")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.dir = self.base / "gn"
        # Every run has the stand-ins first on PATH: a regression into a real hyprctl, qs or loginctl is logged, not run.
        self.bin_dir, self.log = stand_ins(self.base)

    def run_script(self, *args, env=None, wayland="wayland-9", sig=outer_sig):
        e = {"PATH": f"{self.bin_dir}:{os.environ['PATH']}", "HOME": self.tmp.name, "XDG_RUNTIME_DIR": str(self.base),
             "GUTTER_NESTED_DIR": str(self.dir)}
        if wayland:
            e["WAYLAND_DISPLAY"] = wayland
        if sig:
            e["HYPRLAND_INSTANCE_SIGNATURE"] = sig
        e.update(env or {})
        return subprocess.run([self.script, *args], capture_output=True, text=True, env=e, stdin=subprocess.DEVNULL)

    def dry(self, *args, **kw):
        kw.setdefault("env", {})["GUTTER_NESTED_DRY"] = "1"
        return self.run_script("start", *args, **kw)

    def commands(self, r):
        return [l[len("would run: "):] for l in r.stdout.splitlines() if l.startswith("would run: ")]

    def test_start_needs_a_wayland_display(self):
        r = self.run_script("start", wayland=None)
        self.assertEqual(r.returncode, 1)
        self.assertIn("WAYLAND_DISPLAY", r.stderr)
        self.assertFalse(self.dir.exists())

    def test_start_needs_the_instance_signature(self):
        r = self.run_script("start", sig=None)
        self.assertEqual(r.returncode, 1)
        self.assertIn("HYPRLAND_INSTANCE_SIGNATURE", r.stderr)
        self.assertFalse(self.dir.exists())

    def test_dry_run_creates_nothing_and_prints_the_commands(self):
        r = self.dry()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(self.dir.exists())
        cmds = self.commands(r)
        joined = "\n".join(cmds)
        self.assertIn(f"{ROOT}/scripts/lock-test-pam.sh {self.dir}", joined)
        self.assertIn(f"Hyprland -c {self.dir}/hyprland.lua", joined)
        self.assertIn(f"qs -p {ROOT}", joined)
        self.assertIn("hyprctl output create headless", joined)

    def test_the_compositor_never_gets_the_outer_signature_and_its_window_the_outer_display(self):
        r = self.dry()
        line = next(c for c in self.commands(r) if "Hyprland -c" in c)
        self.assertIn("-u HYPRLAND_INSTANCE_SIGNATURE", line)
        self.assertIn(f"XDG_RUNTIME_DIR={self.dir}/run", line)
        # A relative outer display is made absolute against the outer runtime dir.
        self.assertIn(f"WAYLAND_DISPLAY={self.base}/wayland-9", line)
        self.assertNotIn(self.outer_sig, line)

    def test_every_hyprctl_and_qs_call_names_the_nested_session(self):
        r = self.dry()
        calls = [c for c in self.commands(r) if "hyprctl" in c or " qs -p " in c]
        self.assertEqual(len(calls), 2)
        for c in calls:
            self.assertIn(f"XDG_RUNTIME_DIR={self.dir}/run", c)
            self.assertIn("HYPRLAND_INSTANCE_SIGNATURE=", c)
            self.assertIn("WAYLAND_DISPLAY=", c)
            self.assertNotIn(self.outer_sig, c)
            self.assertNotIn("XDG_RUNTIME_DIR=" + str(self.base) + " ", c)

    def test_gutter_gets_the_test_settings_and_not_the_smoke_flag(self):
        # GUTTER_SMOKE=1 would make Lock inert (it never locks), so the sealed-off environment does the job instead.
        r = self.dry()
        qs = next(c for c in self.commands(r) if " qs -p " in c)
        for want in ("GUTTER_LOCK_PAM_DIR=", f"GUTTER_LOCK_HINT_FILE={self.dir}/hint", "GUTTER_IDLE_DRY_RUN=1",
                     f"HOME={self.dir}/home", f"DBUS_SESSION_BUS_ADDRESS=unix:path={self.dir}/run/bus", "-u GUTTER_SMOKE",
                     "-u GUTTER_LOCK_DRY_RUN", f"PATH={self.dir}/shim:"):
            self.assertIn(want, qs)
        self.assertNotIn("GUTTER_SMOKE=1", qs)

    def test_the_power_menu_and_launcher_only_log_and_the_host_cannot_be_powered_off(self):
        r = self.dry()
        qs = next(c for c in self.commands(r) if " qs -p " in c)
        self.assertIn("GUTTER_POWER_DRY_RUN=1", qs)
        self.assertIn("GUTTER_LAUNCHER_DRY_RUN=1", qs)
        self.assertNotIn("-u GUTTER_POWER_DRY_RUN", qs)
        self.assertNotIn("-u GUTTER_LAUNCHER_DRY_RUN", qs)
        self.assertIn("-u DISPLAY", qs)
        # Every nested command gets them: hyprctl too (they cost nothing there).
        for c in self.commands(r):
            if " qs -p " in c:
                self.assertIn(f"PATH={self.dir}/shim:", c)

    def test_no_shell_option(self):
        r = self.dry("--no-shell")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(any(" qs -p " in c for c in self.commands(r)))

    def test_the_watchdog_wraps_the_compositor(self):
        r = self.dry(env={"GUTTER_NESTED_TIMEOUT": "77"})
        line = next(c for c in self.commands(r) if "Hyprland -c" in c)
        self.assertTrue(line.startswith("timeout 77 "), line)
        r = self.dry(env={"GUTTER_NESTED_TIMEOUT": "soon"})
        self.assertEqual(r.returncode, 1)

    def test_unknown_start_option_and_unknown_command(self):
        self.assertEqual(self.dry("--bogus").returncode, 2)
        r = self.run_script("bogus")
        self.assertEqual(r.returncode, 2)
        self.assertIn("Usage", r.stderr)

    def test_the_folder_must_be_named_for_it_and_short(self):
        r = self.run_script("start", env={"GUTTER_NESTED_DIR": str(self.base / "precious")})
        self.assertEqual(r.returncode, 1)
        self.assertIn("gn*", r.stderr)
        r = self.run_script("start", env={"GUTTER_NESTED_DIR": str(self.base / ("gn" + "x" * 40))})
        self.assertEqual(r.returncode, 1)
        self.assertIn("too long", r.stderr)

    def test_start_refuses_over_a_session_record(self):
        self.dir.mkdir()
        (self.dir / "env").write_text("sig=x\n")
        r = self.run_script("start")
        self.assertEqual(r.returncode, 1)
        self.assertIn("record exists", r.stderr)
        self.assertEqual(sorted(p.name for p in self.dir.iterdir()), ["env"])

    def test_other_commands_need_a_running_session(self):
        for args in (("ctl", "monitors"), ("ipc", "call", "lock", "lock"), ("env",), ("shell",), ("shell", "kill9")):
            r = self.run_script(*args)
            self.assertEqual(r.returncode, 1, args)
            self.assertIn("no nested session is running", r.stderr)
        r = self.run_script("stop")
        self.assertEqual(r.returncode, 1)
        self.assertIn("no nested session", r.stderr)

    def record(self, sig, pid):
        self.dir.mkdir(exist_ok=True)
        (self.dir / "env").write_text(f"sig={sig}\nwl=wayland-1\npam=/x\nhpid={pid}\ncpid={pid}\ndpid={pid}\nrunner={pid}\n")

    def test_ctl_and_ipc_refuse_the_callers_own_instance(self):
        self.record(self.outer_sig, os.getpid())
        for args in (("ctl", "dispatch", "x"), ("ipc", "call", "lock", "lock"), ("shell",), ("env",)):
            r = self.run_script(*args)
            self.assertEqual(r.returncode, 1, args)
            self.assertIn("own", r.stderr)

    def test_a_dead_compositor_is_refused(self):
        p = subprocess.Popen(["true"])
        p.wait()
        self.record("nested0000_2_2", p.pid)
        r = self.run_script("ctl", "monitors")
        self.assertEqual(r.returncode, 1)
        self.assertIn("is not running", r.stderr)

    def test_env_prints_the_nested_values(self):
        self.record("nested0000_2_2", os.getpid())
        r = self.run_script("env")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("export HYPRLAND_INSTANCE_SIGNATURE=nested0000_2_2", r.stdout)
        self.assertIn("export WAYLAND_DISPLAY=wayland-1", r.stdout)
        self.assertIn(f"export XDG_RUNTIME_DIR={self.dir}/run", r.stdout)
        self.assertNotIn(self.outer_sig, r.stdout)

    def logged(self, log):
        return [tuple(l.split("\t", 4)) for l in log.read_text().splitlines()]

    def test_no_subcommand_calls_a_command_aimed_at_the_outer_session(self):
        log = self.log
        nested = "nested0000_2_2"
        # A dry run only prints: it creates nothing and calls nothing.
        for extra in ((), ("--no-shell",)):
            r = self.dry(*extra)
            self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(self.dir.exists())
        self.assertEqual(self.logged(log), [])
        self.record(nested, os.getpid())
        (self.dir / "logind.in").write_text("")
        for args in (("ctl", "monitors"), ("ipc", "call", "lock", "lock"), ("env",), ("logind", "sleep"),
                     ("logind", "resume"), ("shell", "start"), ("shell", "hang"), ("shell", "cont"), ("shell", "kill"),
                     ("shell", "kill9"), ("stop",)):
            self.run_script(*args)
        deadline = time.time() + 5  # `shell start` starts qs in the background
        while time.time() < deadline and (f"-p {ROOT}",) not in [c[4:] for c in self.logged(log)]:
            time.sleep(0.05)
        calls = self.logged(log)
        self.assertIn(("qs", nested, f"{self.dir}/run", "wayland-1", f"-p {ROOT}"), calls)
        for name, sig, run, wl, args in calls:
            self.assertIn(name, ("hyprctl", "qs"), calls)  # nothing that locks, suspends or kills by name
            # Aimed at the nested session by its own environment, never the caller's.
            self.assertEqual((sig, run, wl), (nested, f"{self.dir}/run", "wayland-1"), (name, args))
            self.assertNotIn("lock-session", args)
        self.assertEqual({c[0] for c in calls}, {"hyprctl", "qs"})
        # The caller's own instance is refused by every subcommand before anything is run.
        before = len(calls)
        self.record(self.outer_sig, os.getpid())
        logind_before = (self.dir / "logind.in").read_text()
        for args in (("ctl", "monitors"), ("ipc", "call", "lock", "lock"), ("logind", "sleep"), ("shell", "start"),
                     ("shell", "kill9"), ("stop",)):
            self.assertEqual(self.run_script(*args).returncode, 1, args)
        self.assertEqual(len(self.logged(log)), before)
        self.assertEqual((self.dir / "logind.in").read_text(), logind_before)

    def test_the_nested_gutter_gets_a_logind_monitor_that_follows_a_file_in_the_session_folder(self):
        import json
        r = self.dry()
        qs = next(c for c in self.commands(r) if " qs -p " in c)
        want = ["sh", "-c", 'exec tail -n 0 -F --pid=$PPID -- "$1"', "sh", f"{self.dir}/logind.in"]
        got = [t for t in shlex.split(qs) if t.startswith("GUTTER_IDLE_MONITOR_CMD=")]
        self.assertEqual(len(got), 1, qs)
        self.assertEqual(json.loads(got[0].split("=", 1)[1]), want)
        self.assertNotIn("86400", qs)

    def test_a_folder_that_would_need_json_escaping_is_refused(self):
        for bad in ('gn"x', "gn\\x", "gn\nx"):
            with self.subTest(bad):
                r = self.dry(env={"GUTTER_NESTED_DIR": str(self.base / bad)})
                self.assertEqual(r.returncode, 1)
                self.assertIn("printable ASCII" if "\n" in bad else "quote or a backslash", r.stderr)

    def wait_until_following(self, parent_pid, path, timeout=10):
        """Waits until a child of `parent_pid` (the monitor's tail) holds `path` open and has an inotify watch: only then
        does it see every line appended (it starts at the end, so earlier ones are lost)."""
        end = time.time() + timeout
        while time.time() < end:
            try:
                kids = [int(k) for t in Path(f"/proc/{parent_pid}/task").iterdir()
                        for k in (t / "children").read_text().split()]
            except OSError:
                kids = []
            for pid in kids:
                try:
                    links = [os.readlink(f"/proc/{pid}/fd/{fd}") for fd in os.listdir(f"/proc/{pid}/fd")]
                except OSError:
                    continue
                if str(path) in links and "anon_inode:inotify" in links:
                    return
            time.sleep(0.05)
        self.fail("the monitor never started following the file")

    def test_a_folder_with_non_ascii_bytes_is_refused(self):
        r = self.dry(env={"GUTTER_NESTED_DIR": str(self.base / "gn\u00e9")})
        self.assertEqual(r.returncode, 1)
        self.assertIn("printable ASCII", r.stderr)

    def test_the_fake_monitor_command_runs_and_ends_with_its_parent(self):
        import json, select
        # wait_until_following reads /proc/<pid>/task/*/children and the fds of a GNU tail (inotify): elsewhere, skip.
        if not Path(f"/proc/{os.getpid()}/task/{os.getpid()}/children").exists():
            self.skipTest("no /proc/<pid>/task/<tid>/children on this kernel")
        if "GNU coreutils" not in subprocess.run(["tail", "--version"], capture_output=True, text=True).stdout:
            self.skipTest("tail is not GNU tail")
        self.record("nested0000_2_2", os.getpid())
        log = self.dir / "logind.in"
        log.write_text("an old line\n")
        env = self.run_script("env").stdout
        line = next(l for l in env.splitlines() if l.startswith("export GUTTER_IDLE_MONITOR_CMD="))
        argv = json.loads(shlex.split(line)[1].split("=", 1)[1])
        # Parent (stands for qs) -> monitor; the monitor's stdout is ours.
        parent = subprocess.Popen(["bash", "-c", '"$@" & wait', "bash", *argv], stdout=subprocess.PIPE)
        self.addCleanup(lambda: (parent.kill(), parent.wait(), parent.stdout.close()))
        self.wait_until_following(parent.pid, log)
        for _ in range(2):
            self.run_script("logind", "sleep")
            self.run_script("logind", "resume")
        got = b""
        deadline = time.time() + 10
        while got.count(b"\n") < 4 and time.time() < deadline:
            if select.select([parent.stdout], [], [], 0.5)[0]:
                got += os.read(parent.stdout.fileno(), 4096)
        sleep_l = b"/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)\n"
        resume_l = sleep_l.replace(b"true", b"false")
        # Only what was appended after it started; the old line is not replayed.
        self.assertEqual(got, (sleep_l + resume_l) * 2)
        # Killing the parent ends the monitor (tail --pid): its end of the pipe closes.
        parent.kill()
        parent.wait()
        end = time.time() + 10
        eof = False
        while time.time() < end and not eof:
            if select.select([parent.stdout], [], [], 0.5)[0]:
                eof = os.read(parent.stdout.fileno(), 4096) == b""
        self.assertTrue(eof, "the monitor outlived its parent")

    def test_logind_needs_a_running_session(self):
        for args in (("logind", "sleep"), ("logind", "resume"), ("logind",), ("logind", "bogus")):
            r = self.run_script(*args)
            self.assertEqual(r.returncode, 1, args)
            self.assertIn("no nested session is running", r.stderr)

    def test_logind_refuses_the_callers_own_instance_and_a_dead_compositor(self):
        self.record(self.outer_sig, os.getpid())
        (self.dir / "logind.in").write_text("")
        r = self.run_script("logind", "sleep")
        self.assertEqual(r.returncode, 1)
        self.assertIn("own", r.stderr)
        self.assertEqual((self.dir / "logind.in").read_text(), "")
        dead = subprocess.Popen(["true"])
        dead.wait()
        self.record("nested0000_2_2", dead.pid)
        r = self.run_script("logind", "sleep")
        self.assertEqual(r.returncode, 1)
        self.assertIn("is not running", r.stderr)
        self.assertEqual((self.dir / "logind.in").read_text(), "")

    def test_logind_sleep_and_resume_append_the_exact_lines(self):
        self.record("nested0000_2_2", os.getpid())
        log = self.dir / "logind.in"
        log.write_text("")
        for what in ("sleep", "resume", "sleep"):
            r = self.run_script("logind", what)
            self.assertEqual(r.returncode, 0, r.stderr)
        # The lines tests/tst_idle.qml feeds lib/idle.js' logindEvent as a sleep and a resume.
        qml = (ROOT / "tests/tst_idle.qml").read_text()
        sleep_l = re.search(r'property string sleepLine: "([^"]+)"', qml).group(1) + "\n"
        resume_l = re.search(r'property string resumeLine: "([^"]+)"', qml).group(1) + "\n"
        self.assertEqual(log.read_text(), sleep_l + resume_l + sleep_l)

    def test_logind_with_a_wrong_argument_prints_usage_and_writes_nothing(self):
        self.record("nested0000_2_2", os.getpid())
        log = self.dir / "logind.in"
        log.write_text("")
        for args in (("logind",), ("logind", "bogus"), ("logind", "sleep", "now"), ("logind", "")):
            r = self.run_script(*args)
            self.assertEqual(r.returncode, 2, args)
            self.assertIn("Usage", r.stderr)
            self.assertIn("logind sleep|resume", r.stderr)
        self.assertEqual(log.read_text(), "")

    def test_logind_needs_the_monitor_file_the_session_makes_at_start(self):
        self.record("nested0000_2_2", os.getpid())
        r = self.run_script("logind", "sleep")
        self.assertEqual(r.returncode, 1)
        self.assertIn("logind.in is missing", r.stderr)
        self.assertFalse((self.dir / "logind.in").exists())

    def test_a_start_makes_the_monitor_file(self):
        text = Path(self.script).read_text()
        self.assertRegex(text, r'(?m)^: >"\$dir/logind\.in"$')

    def test_the_script_never_locks_or_rescues_the_outer_session(self):
        # A static backstop for the die and failure branches of `start` that no run reaches.
        text = Path(self.script).read_text()
        code = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))
        self.assertNotIn("lock-session", code)
        self.assertNotIn("rescue-unlock", code)
        # loginctl appears only as the name of a harmless stand-in.
        for l in code.splitlines():
            if "loginctl" in l:
                self.assertIn("for name in pkill", l)

    def test_a_long_folder_is_refused_for_a_real_start_but_not_in_dry_run(self):
        long = self.base / ("gn" + "x" * 40)
        r = self.run_script("start", env={"GUTTER_NESTED_DIR": str(long)})
        self.assertEqual(r.returncode, 1)
        self.assertIn("too long", r.stderr)
        r = self.dry(env={"GUTTER_NESTED_DIR": str(long)})
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_stop_checks_like_the_other_commands(self):
        self.record(self.outer_sig, os.getpid())
        r = self.run_script("stop")
        self.assertEqual(r.returncode, 1)
        self.assertIn("own", r.stderr)
        dead = subprocess.Popen(["true"])
        dead.wait()
        self.record("nested0000_2_2", dead.pid)
        r = self.run_script("stop")
        self.assertEqual(r.returncode, 1)
        self.assertIn("is not running", r.stderr)

    def test_the_shell_is_found_by_its_recorded_pid_never_by_name(self):
        self.record("nested0000_2_2", os.getpid())
        # A qs-named process that runs in the session's folder and so looks just like Gutter, but is not recorded.
        fake = self.base / "fakebin"
        fake.mkdir()
        (fake / "qs").symlink_to(shutil.which("sleep"))
        decoy = subprocess.Popen([str(fake / "qs"), "60"], cwd=str(self.dir))
        self.addCleanup(lambda: (decoy.kill(), decoy.wait()))
        # A recorded pid that is not a qs (this Python) is not Gutter: nothing to signal.
        (self.dir / "qs.pid").write_text(f"{os.getpid()}\n")
        for what in ("kill", "kill9", "hang", "cont"):
            r = self.run_script("shell", what)
            self.assertEqual(r.returncode, 0, (what, r.stderr))
            self.assertIn("not running", r.stderr)
        self.assertEqual(self.run_script("shell", "bogus").returncode, 2)
        self.assertIsNone(decoy.poll())  # not ended,
        state = Path(f"/proc/{decoy.pid}/stat").read_text().rpartition(")")[2].split()[0]
        self.assertNotEqual(state, "T")  # nor stopped
        self.assertEqual(self.logged(self.log), [])  # and no pkill or pgrep was asked

    def test_stop_only_ends_a_runner_that_is_a_lock_nested_start(self):
        self.record("nested0000_2_2", os.getpid())  # a live pid that is not the harness
        r = self.run_script("stop")
        self.assertEqual(r.returncode, 1)
        self.assertIn("not this session's lock-nested.sh start", r.stderr)

    def test_the_recorded_shell_pid_must_also_run_in_the_sessions_folder(self):
        # A sleep named qs, recorded as Gutter's pid but running elsewhere: it is not signalled.
        self.record("nested0000_2_2", os.getpid())
        fake = self.base / "fakebin"
        fake.mkdir()
        (fake / "qs").symlink_to(shutil.which("sleep"))
        p = subprocess.Popen([str(fake / "qs"), "60"], cwd="/")
        self.addCleanup(lambda: (p.kill(), p.wait()))
        (self.dir / "qs.pid").write_text(f"{p.pid}\n")
        r = self.run_script("shell", "kill9")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("not running", r.stderr)
        self.assertIsNone(p.poll())
        q = subprocess.Popen([str(fake / "qs"), "60"], cwd=str(self.dir))
        self.addCleanup(lambda: (q.kill(), q.wait()))
        (self.dir / "qs.pid").write_text(f"{q.pid}\n")
        r = self.run_script("shell", "kill9")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(q.wait(timeout=5), -9)

    def qmlls_run(self, before, during, keep=False, fails=False, inside=False, tmpenv=None, after="", env=None):
        """Runs the script's save_qmlls / restore_qmlls (cut out of it) in a temp checkout: `before` sets up
        .qmlls.ini, `during` is what the nested qs does to it; returns the checkout (the process is self.proc). The
        temp folder the file is kept in (mktemp -d, under a TMPDIR of its own here) must be gone afterwards, unless
        `keep`. `fails`: the run is expected to die (exit 1) instead of finishing; `inside`: TMPDIR is in the checkout;
        `tmpenv(co)` gives TMPDIR itself; `after` runs once restore_qmlls has returned; `env` is added to the
        environment."""
        text = Path(self.script).read_text()
        m = re.search(r'^qmlls="\$here/\.qmlls\.ini"\n.*?^restore_qmlls\(\) \{\n.*?^\}\n', text, re.S | re.M)
        self.assertIsNotNone(m)
        co, tmp = self.base / "co", self.base / "tmp"
        for d in (co, tmp):
            if d.exists():
                os.chmod(d, 0o700)
            shutil.rmtree(d, ignore_errors=True)
            d.mkdir()
        if inside:
            tmp = co / "tmp"
            tmp.mkdir()
        unset = re.search(r"^unset CDPATH$", text, re.M)
        self.assertIsNotNone(unset)
        code = (f"set -euo pipefail\n{unset.group(0)}\nhere={shlex.quote(str(co))}\ndie() {{ echo \"$*\" >&2; exit 1; }}\n{m.group(0)}\n"
                f"cd \"$here\"\n{before}\nsave_qmlls\n{during}\nrestore_qmlls\n{after}\n")
        # The stand-ins first on PATH, as for every run here (the cut-out functions only copy, link and remove).
        run_env = {**os.environ, "PATH": f"{self.bin_dir}:{os.environ['PATH']}",
                   "TMPDIR": tmpenv(co) if tmpenv else str(tmp), **(env or {})}
        self.proc = subprocess.run(["bash", "-c", code], capture_output=True, text=True, env=run_env)
        self.addCleanup(lambda: os.chmod(co, 0o700))
        self.assertEqual(self.proc.returncode, 1 if fails else 0, self.proc.stderr)
        self.tmp_left = sorted(tmp.iterdir())
        if not keep:
            self.assertEqual(self.tmp_left, [], "the saved copy is left behind")
        return co

    def test_a_dangling_qmlls_link_made_by_the_session_is_removed(self):
        co = self.qmlls_run("", "ln -s /nonexistent/gn/run/quickshell/vfs/x/.qmlls.ini .qmlls.ini")
        self.assertFalse(os.path.lexists(co / ".qmlls.ini"))

    def test_a_qmlls_link_made_by_the_session_is_removed_while_its_target_still_exists(self):
        # The session's folder is removed after restore_qmlls runs, so the link is not dangling yet at that point.
        (self.base / "target").write_text("x")
        co = self.qmlls_run("", f"ln -s {shlex.quote(str(self.base / 'target'))} .qmlls.ini")
        self.assertFalse(os.path.lexists(co / ".qmlls.ini"))

    def test_the_qmlls_link_or_file_from_before_is_put_back(self):
        co = self.qmlls_run("ln -s /live/vfs/.qmlls.ini .qmlls.ini", "ln -sfn /nonexistent/gn/.qmlls.ini .qmlls.ini")
        self.assertEqual(os.readlink(co / ".qmlls.ini"), "/live/vfs/.qmlls.ini")
        co = self.qmlls_run("printf '[General]\\n' > .qmlls.ini", "rm .qmlls.ini; ln -s /nonexistent/x .qmlls.ini")
        self.assertFalse((co / ".qmlls.ini").is_symlink())
        self.assertEqual((co / ".qmlls.ini").read_text(), "[General]\n")

    hyprland = """#!{python}
import os, socket, sys, time
e = os.environ.get
with open("{log}", "a") as f:
    f.write("\\t".join(["Hyprland", e("HYPRLAND_INSTANCE_SIGNATURE", "unset"), e("XDG_RUNTIME_DIR", "unset"),
                        e("WAYLAND_DISPLAY", "unset"), " ".join(sys.argv[1:])]) + "\\n")
run = e("XDG_RUNTIME_DIR")
sock = socket.socket(socket.AF_UNIX)
sock.bind(run + "/wayland-nest")
os.makedirs(run + "/hypr/nest_1_1")
with open(run + "/hypr/nest_1_1/hyprland.lock", "w") as f:
    f.write(str(os.getpid()) + "\\nwayland-nest\\n")
parent = os.getppid()
for _ in range(600):  # at most 60 s, and not past the `timeout` that runs it
    if os.getppid() != parent:
        break
    time.sleep(0.1)
"""

    def session(self, qmlls_before=None):
        """A real `lock-nested.sh start` in a copy of the checkout's two scripts (so the repo's .qmlls.ini is never
        touched), with the stand-ins on PATH and a Hyprland that only makes its instance folder and socket. Waits
        until the session is up; returns (copy of the checkout, stand-ins folder, log, environment for the subcommands)."""
        co = self.base / "co"
        (co / "scripts").mkdir(parents=True)
        for name in ("lock-nested.sh", "lock-test-pam.sh"):
            shutil.copy2(ROOT / "scripts" / name, co / "scripts" / name)
        if qmlls_before:
            (co / ".qmlls.ini").symlink_to(qmlls_before)
        bin_dir, log = stand_ins(self.base, qmlls=True)
        (bin_dir / "Hyprland").write_text(self.hyprland.format(python=sys.executable, log=log))
        (bin_dir / "Hyprland").chmod(0o755)
        env = {"PATH": f"{bin_dir}:{os.environ['PATH']}", "HOME": self.tmp.name, "XDG_RUNTIME_DIR": str(self.base),
               "GUTTER_NESTED_DIR": str(self.dir), "WAYLAND_DISPLAY": "wayland-9",
               "HYPRLAND_INSTANCE_SIGNATURE": self.outer_sig, "GUTTER_NESTED_TIMEOUT": "60"}
        out = open(self.base / "start.out", "w")
        self.addCleanup(out.close)
        runner = subprocess.Popen([str(co / "scripts/lock-nested.sh"), "start"], env=env, stdout=out, stderr=out,
                                  stdin=subprocess.DEVNULL, start_new_session=True)
        self.runner = runner
        self.addCleanup(self.reap, runner)
        deadline = time.time() + 20
        while time.time() < deadline and not (self.dir / "env").exists() and runner.poll() is None:
            time.sleep(0.05)
        self.assertTrue((self.dir / "env").exists(), (self.base / "start.out").read_text())
        while time.time() < deadline and (f"-p {co}",) not in [c[4:] for c in self.logged(log)]:
            time.sleep(0.05)  # the shell stand-in has been started too
        return co, bin_dir, log, env

    def reap(self, runner):
        """However a session test ended: TERM the runner so its trap ends the compositor (which `timeout` put in a
        group of its own), then the runner's group, then the compositor by its recorded pid if that pid is still this
        test's stand-in."""
        lock = self.dir / "run/hypr/nest_1_1/hyprland.lock"
        try:
            compositor = int(lock.read_text().split()[0])
        except (OSError, ValueError, IndexError):
            compositor = None
        if runner.poll() is None:
            runner.terminate()
            try:
                runner.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        try:
            os.killpg(runner.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        runner.wait()
        try:
            # Only this test's own stand-in (its script path is in the cmdline), never another process that took the pid.
            if compositor and str(self.base / "rbin/Hyprland") in Path(f"/proc/{compositor}/cmdline").read_text().split("\0"):
                os.kill(compositor, signal.SIGKILL)
        except OSError:
            pass

    def end(self, co, env):
        """`stop`, and waits for the runner to have cleaned up."""
        r = subprocess.run([str(co / "scripts/lock-nested.sh"), "stop"], env=env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.runner.wait(timeout=15), 0, (self.base / "start.out").read_text())

    def test_a_real_start_only_ever_aims_at_the_nested_session_and_stop_cleans_up(self):
        co, bin_dir, log, env = self.session()
        compositor = int((self.dir / "run/hypr/nest_1_1/hyprland.lock").read_text().split()[0])
        for args in (("ctl", "monitors"), ("ipc", "call", "lock", "lock"), ("shell", "kill"), ("env",)):
            r = subprocess.run([str(co / "scripts/lock-nested.sh"), *args], env=env, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, (args, r.stderr))
        self.end(co, env)
        calls = self.logged(log)
        self.assertEqual({c[0] for c in calls}, {"Hyprland", "dbus-daemon", "hyprctl", "qs"})  # nothing else was called
        for name, sig, run, wl, args in calls:
            self.assertNotIn("lock-session", args)
            if name == "Hyprland":  # the compositor never sees the outer signature; its window needs the outer display
                self.assertEqual((sig, run, wl), ("unset", f"{self.dir}/run", f"{self.base}/wayland-9"))
            elif name != "dbus-daemon":
                self.assertEqual((sig, run, wl), ("nest_1_1", f"{self.dir}/run", "wayland-nest"), (name, args))
        self.assertIn(("hyprctl", "nest_1_1", f"{self.dir}/run", "wayland-nest", "output create headless"), calls)
        self.assertIn(("qs", "nest_1_1", f"{self.dir}/run", "wayland-nest", f"-p {co} ipc call lock lock"), calls)
        # Stopped: the session's folder is gone and so is its compositor.
        self.assertFalse(self.dir.exists())
        deadline = time.time() + 5
        while time.time() < deadline and Path(f"/proc/{compositor}").exists():
            time.sleep(0.05)
        self.assertFalse(Path(f"/proc/{compositor}").exists())

    def test_commands_that_could_suspend_or_power_off_are_shimmed(self):
        co, bin_dir, log, env = self.session()
        shim_log = self.dir / "shim.log"
        before = log.read_text()
        # Run with PATH limited to the recording stand-ins (and `cat`): a shim that passed its call on would reach
        # one of them and leave a line in their log, instead of suspending anything.
        only = {"PATH": f"{bin_dir}:{self.base / 'safe'}"}
        for name in ("systemctl", "loginctl", "shutdown", "reboot", "poweroff", "pkill", "gsettings", "xdg-open", "pw-play"):
            r = subprocess.run([str(self.dir / "shim" / name), "--gutter-test"], capture_output=True, text=True, env=only)
            self.assertEqual(r.returncode, 0, (name, r.stderr))
            self.assertIn(f"{name} --gutter-test", shim_log.read_text().splitlines())
        # systemd-inhibit holds with `cat`, taking no inhibitor from logind.
        r = subprocess.run([str(self.dir / "shim" / "systemd-inhibit"), "--gutter-test"], input="held\n",
                           capture_output=True, text=True, env=only)
        self.assertEqual((r.returncode, r.stdout), (0, "held\n"))
        self.assertIn("systemd-inhibit --gutter-test", shim_log.read_text().splitlines())
        self.assertEqual(log.read_text(), before)  # none reached a stand-in
        self.end(co, env)

    def test_a_qmlls_file_comes_back_byte_for_byte(self):
        contents = {
            "no trailing newline": b"[General]\nbuildDir=/x",
            "two trailing newlines": b"[General]\nbuildDir=/x\n\n",
            "only newlines": b"\n\n\n",
            "empty": b"",
            "binary-ish": b"\x00\xff\xfe\r\n\x01 \t\x00\n\x80",
        }
        seed = self.base / "seed"
        for name, data in contents.items():
            with self.subTest(name):
                seed.write_bytes(data)
                before = f"cp {shlex.quote(str(seed))} .qmlls.ini; chmod 640 .qmlls.ini"
                # `during`: the nested qs replaces the file with its link.
                co = self.qmlls_run(before, "rm .qmlls.ini; ln -s /nonexistent/x .qmlls.ini")
                f = co / ".qmlls.ini"
                self.assertFalse(f.is_symlink())
                self.assertEqual(f.read_bytes(), data)
                self.assertEqual(f.stat().st_mode & 0o777, 0o640)

    def test_a_qmlls_file_the_session_left_alone_is_unchanged(self):
        co = self.qmlls_run("printf 'a\\n\\n' > .qmlls.ini", ":")
        self.assertEqual((co / ".qmlls.ini").read_bytes(), b"a\n\n")

    def test_a_qmlls_link_target_comes_back_exactly_even_with_trailing_newlines(self):
        co = self.qmlls_run("ln -s $'/live/x\\n\\n' .qmlls.ini", "ln -sfn /nonexistent/gn/.qmlls.ini .qmlls.ini")
        self.assertEqual(os.readlink(co / ".qmlls.ini"), "/live/x\n\n")
        co = self.qmlls_run("ln -s -- -dash .qmlls.ini", "ln -sfn /nonexistent/gn/.qmlls.ini .qmlls.ini")
        self.assertEqual(os.readlink(co / ".qmlls.ini"), "-dash")

    def test_the_saved_qmlls_copy_survives_a_failed_restore(self):
        if os.geteuid() == 0:
            self.skipTest("root ignores directory permissions")
        # The file is gone and the checkout turned read-only, as the session ends: the copy is the only one left.
        co = self.qmlls_run("printf 'keep\\n' > .qmlls.ini", "rm .qmlls.ini; chmod a-w .", keep=True)
        self.assertFalse(os.path.lexists(co / ".qmlls.ini"))
        self.assertEqual(len(self.tmp_left), 1)
        self.assertTrue(self.tmp_left[0].name.startswith("gutter-qmlls."))
        self.assertEqual((self.tmp_left[0] / "ini").read_bytes(), b"keep\n")
        self.assertIn(f"the saved copy is {self.tmp_left[0]}/ini", self.proc.stderr)

    def test_a_qmlls_that_is_neither_file_nor_link_is_left_alone(self):
        co = self.qmlls_run("mkdir .qmlls.ini; touch .qmlls.ini/x", ":")
        self.assertTrue((co / ".qmlls.ini" / "x").is_file())

    def test_an_unreadable_qmlls_file_stops_the_start_and_leaves_no_copy(self):
        if os.geteuid() == 0:
            self.skipTest("root reads anything")
        co = self.qmlls_run("printf 'x' > .qmlls.ini; chmod 000 .qmlls.ini", ":", fails=True)
        self.assertIn("cannot save", self.proc.stderr)
        self.assertTrue(os.path.lexists(co / ".qmlls.ini"))

    def test_a_message_that_cannot_be_written_does_not_stop_what_comes_after_the_restore(self):
        if os.geteuid() == 0:
            self.skipTest("root ignores directory permissions")
        # stderr is closed (as when the terminal hangs up) while the restore fails: the EXIT trap must still go on.
        done = self.base / "after-done"
        self.qmlls_run("printf 'keep\\n' > .qmlls.ini", "rm .qmlls.ini; chmod a-w .; exec 2>&-", keep=True,
                       after=f"echo ran > {shlex.quote(str(done))}")
        self.assertEqual(done.read_text(), "ran\n")
        self.assertEqual(len(self.tmp_left), 1)

    def test_a_link_that_cannot_be_read_stops_the_start_and_leaves_it_alone(self):
        co = self.qmlls_run("ln -s /x .qmlls.ini; readlink() { return 1; }", ":", fails=True)
        self.assertIn("cannot read", self.proc.stderr)
        self.assertEqual(os.readlink(co / ".qmlls.ini"), "/x")

    def test_an_exported_cdpath_does_not_garble_the_resolved_temp_folder(self):
        # TMPDIR is relative to where the script runs (moved out of the checkout here). With CDPATH=. a plain `cd` prints
        # the folder it went to, which `$(cd ... && pwd -P)` would then get twice and the copy could not be made.
        co = self.qmlls_run(f"printf 'x' > .qmlls.ini; cd {shlex.quote(str(self.base))}", ":",
                            tmpenv=lambda co: "tmp", env={"CDPATH": "."})
        self.assertEqual((co / ".qmlls.ini").read_bytes(), b"x")

    def test_a_relative_tmpdir_or_a_link_into_the_checkout_is_still_inside_it(self):
        # A relative TMPDIR as when run from the checkout (the helper changes into it); the link is outside, its target in.
        self.qmlls_run("printf 'x' > .qmlls.ini; mkdir tmp", ":", fails=True, tmpenv=lambda co: "tmp")
        self.assertIn("TMPDIR is inside the checkout", self.proc.stderr)
        self.assertEqual(list((self.base / "co" / "tmp").iterdir()), [])

        def link(co):
            (co / "tmp").mkdir()
            (self.base / "lnk").unlink(missing_ok=True)
            (self.base / "lnk").symlink_to(co / "tmp")
            return str(self.base / "lnk")
        self.qmlls_run("printf 'x' > .qmlls.ini", ":", fails=True, tmpenv=link)
        self.assertIn("TMPDIR is inside the checkout", self.proc.stderr)
        self.assertEqual(list((self.base / "co" / "tmp").iterdir()), [])

    def test_the_saved_qmlls_copy_is_never_kept_inside_the_checkout(self):
        self.qmlls_run("printf 'x' > .qmlls.ini", ":", fails=True, inside=True)
        self.assertIn("TMPDIR is inside the checkout", self.proc.stderr)
        self.assertEqual(self.tmp_left, [])

    def test_a_session_puts_the_qmlls_link_back(self):
        # The nested qs makes a dangling .qmlls.ini link in the checkout; the end of the session puts back what was there.
        co, bin_dir, log, env = self.session(qmlls_before="/live/vfs/.qmlls.ini")
        self.assertEqual(os.readlink(co / ".qmlls.ini"), "/nonexistent/gn/run/.qmlls.ini")
        self.end(co, env)
        self.assertEqual(os.readlink(co / ".qmlls.ini"), "/live/vfs/.qmlls.ini")

    def test_a_session_leaves_no_qmlls_link_where_there_was_none(self):
        co, bin_dir, log, env = self.session()
        self.assertTrue(os.path.islink(co / ".qmlls.ini"))
        self.end(co, env)
        self.assertFalse(os.path.lexists(co / ".qmlls.ini"))


class NestedCheck(unittest.TestCase):
    """scripts/lock-nested-check.sh needs a Wayland session and opens a nested compositor in it, so it is opt-in and
    these tests only cover its guard rails and the failure of a session that does not start. None of them starts a
    compositor (the script stops at the guard, or runs against the stand-ins first on PATH, which only record a call)."""

    script = str(ROOT / "scripts/lock-nested-check.sh")

    def run_script(self, *args, **env):
        with tempfile.TemporaryDirectory(prefix="gnt", dir="/tmp") as tmp:
            bin_dir, log = stand_ins(tmp)
            # No session variable unless a test names it: the environment this suite runs in may well have one.
            e = {"PATH": f"{bin_dir}:{os.environ['PATH']}", "HOME": tmp, "XDG_RUNTIME_DIR": tmp, **env}
            r = subprocess.run([self.script, *args], capture_output=True, text=True, env=e, stdin=subprocess.DEVNULL, timeout=30)
            return r, log.read_text()

    def test_it_refuses_without_a_session(self):
        r, calls = self.run_script()
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("WAYLAND_DISPLAY", r.stderr)
        self.assertNotIn("SKIP", r.stdout + r.stderr)
        self.assertEqual(calls, "")

    def test_it_refuses_with_only_half_a_session(self):
        for env in ({"WAYLAND_DISPLAY": "wayland-9"}, {"HYPRLAND_INSTANCE_SIGNATURE": "outer0000_1_1"}):
            r, calls = self.run_script(**env)
            self.assertEqual(r.returncode, 1, (env, r.stderr))
            self.assertEqual(calls, "", env)

    def test_skip_if_no_session_exits_0_with_skip(self):
        for env in ({}, {"WAYLAND_DISPLAY": "wayland-9"}, {"HYPRLAND_INSTANCE_SIGNATURE": "outer0000_1_1"}):
            r, calls = self.run_script("--skip-if-no-session", **env)
            self.assertEqual(r.returncode, 0, (env, r.stderr))
            self.assertIn("SKIP", r.stdout)
            self.assertEqual(calls, "", env)

    def test_bad_usage_is_refused(self):
        for args in (("--bogus",), ("--skip-if-no-session", "extra")):
            r, calls = self.run_script(*args)
            self.assertEqual(r.returncode, 2, (args, r.stderr))
            self.assertIn("usage", r.stderr)
            self.assertEqual(calls, "", args)

    def test_a_session_that_does_not_start_fails_and_leaves_nothing(self):
        # With the stand-ins first on PATH the harness's Hyprland exits at once: no compositor is started. The check
        # must say so (never OK), end with the failure's exit code, and remove its folders.
        with tempfile.TemporaryDirectory(prefix="gnt", dir="/tmp") as tmp:
            bin_dir, log = stand_ins(tmp)
            e = {"PATH": f"{bin_dir}:{os.environ['PATH']}", "HOME": tmp, "XDG_RUNTIME_DIR": tmp,
                 "WAYLAND_DISPLAY": "wayland-9", "HYPRLAND_INSTANCE_SIGNATURE": "outer0000_1_1"}
            r = subprocess.run([self.script], capture_output=True, text=True, env=e, stdin=subprocess.DEVNULL, timeout=60)
            calls = log.read_text()
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("FAIL", r.stdout)
        self.assertNotIn("lock-nested-check: OK", r.stdout)
        self.assertNotIn("ok - the nested session is up", r.stdout)
        self.assertNotIn("lock-session", calls)
        folder = re.search(r"in (/tmp/gn-chk-\d+) ", r.stdout).group(1)  # the run's own folders, by its pid
        for path in (folder, folder + ".src", folder + ".out"):
            self.assertFalse(os.path.exists(path), path)

    def test_the_settle_time_is_whole_decimal_seconds(self):
        # Not whole seconds: bad usage, refused before anything runs.
        for bad in ("1s", "-1", "1.5", " 1"):
            r, calls = self.run_script(GUTTER_NESTED_CHECK_SETTLE=bad)
            self.assertEqual(r.returncode, 2, (bad, r.stderr))
            self.assertIn("GUTTER_NESTED_CHECK_SETTLE", r.stderr)
            self.assertEqual(calls, "", bad)
        # 08 is eight seconds, not a bad octal number: with the stand-ins the session fails to start (no compositor)
        # and the teardown runs to its end.
        r, calls = self.run_script(GUTTER_NESTED_CHECK_SETTLE="08", WAYLAND_DISPLAY="wayland-9",
                                   HYPRLAND_INSTANCE_SIGNATURE="outer0000_1_1")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertNotIn("value too great", r.stderr)
        self.assertIn("ok - no process of the session is left", r.stdout)
        self.assertIn("lock-nested-check: FAIL", r.stdout)
        self.assertNotIn("lock-session", calls)
        folder = re.search(r"in (/tmp/gn-chk-\d+) ", r.stdout).group(1)
        for path in (folder, folder + ".src", folder + ".out"):
            self.assertFalse(os.path.exists(path), path)

    def test_teardown_ends_only_the_sessions_processes(self):
        # Stand-in processes (children of this test, never of the check) while a session fails to start: every process
        # with the session's runtime dir in its environment is ended and fails the run, a `sleep 86400` too (the old
        # fake logind monitor that outlived its shell; the harness's monitor now ends with it, so nothing is exempt),
        # and a process that only names the session's folder in its command line (a `tail -f` of its log, say) or has a
        # different runtime dir is left alone. The stand-in compositor exits (the session fails to start) only once the
        # decoys are in place, and the wait for the session's processes to end by themselves is cut to a second: the
        # decoys never do.
        with tempfile.TemporaryDirectory(prefix="gnt", dir="/tmp") as tmp:
            bin_dir, _ = stand_ins(tmp)
            go = Path(tmp) / "go"
            (bin_dir / "Hyprland").write_text(  # a compositor that never comes up
                f"#!/bin/sh\ni=0\nwhile [ ! -e {go} ] && [ $i -lt 200 ]; do sleep 0.05; i=$((i + 1)); done\nexit 0\n")
            e = {"PATH": f"{bin_dir}:{os.environ['PATH']}", "HOME": tmp, "XDG_RUNTIME_DIR": tmp,
                 "WAYLAND_DISPLAY": "wayland-9", "HYPRLAND_INSTANCE_SIGNATURE": "outer0000_1_1",
                 "GUTTER_NESTED_CHECK_SETTLE": "1"}
            check = subprocess.Popen([self.script], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=e,
                                     stdin=subprocess.DEVNULL)
            folder = f"/tmp/gn-chk-{check.pid}"
            decoys = {}
            try:
                end = time.monotonic() + 10
                while not os.path.isdir(folder + ".out") and time.monotonic() < end:
                    time.sleep(0.05)
                self.assertTrue(os.path.isdir(folder + ".out"))
                path = {"PATH": os.environ["PATH"]}
                decoys["orphan"] = subprocess.Popen(["sleep", "86400"], env={**path, "XDG_RUNTIME_DIR": folder + "/run"})
                decoys["orphan2"] = subprocess.Popen([shutil.which("sleep"), "86400"],  # as Quickshell runs it
                                                     env={**path, "XDG_RUNTIME_DIR": folder + "/run"})
                decoys["stray"] = subprocess.Popen(["sleep", "300"], env={**path, "XDG_RUNTIME_DIR": folder + "/run"})
                decoys["near"] = subprocess.Popen(["sleep", "300"], env={**path, "XDG_RUNTIME_DIR": folder + "/run/x"})
                decoys["foreign"] = subprocess.Popen(
                    [sys.executable, "-c", "import time; time.sleep(300)", folder + "/qs.log"], env=path)
                go.touch()
                out, _ = check.communicate(timeout=60)
                for name in ("orphan", "orphan2", "stray"):  # ended by the check (reaped here)
                    try:
                        decoys[name].wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        self.fail(f"{name} was not ended\n{out}")
                for name in ("near", "foreign"):
                    self.assertIsNone(decoys[name].poll(), f"{name} was ended\n{out}")
            finally:
                if check.poll() is None:
                    check.terminate()
                    try:
                        check.wait(timeout=30)
                    except subprocess.TimeoutExpired:  # a check that hangs in its teardown: its folders go here
                        check.kill()
                        check.wait()
                        for path in (folder, folder + ".src", folder + ".out"):
                            shutil.rmtree(path, ignore_errors=True)
                for p in decoys.values():
                    if p.poll() is None:
                        p.kill()
                        p.wait()
        self.assertEqual(check.returncode, 1, out)
        self.assertNotIn("lock-nested-check: OK", out)
        stray = [l for l in out.splitlines() if "not ended by the harness's stop" in l]
        self.assertEqual(len(stray), 1, out)
        self.assertIn(f" {decoys['stray'].pid} (sleep 300)", stray[0])
        for name in ("orphan", "orphan2"):
            self.assertIn(f" {decoys[name].pid} (", stray[0], name)
        self.assertNotIn("leaked", out)
        self.assertNotIn(str(decoys["near"].pid), out)
        self.assertIn(f"note - not ours, left alone: {decoys['foreign'].pid} (", out)
        self.assertNotIn("No such file", out)  # a process that ended while /proc was read is no error

    def test_every_signal_goes_to_a_pid_checked_again_as_ours(self):
        # Kills are by pid only, each right after `still_ours` confirms that pid (its own jobs included: bash reaps a
        # job that ended, and its pid may then be another process's). Nothing is matched by name. A reused pid cannot
        # be made to happen in a test, so this part is checked on the code: the jobs are recorded as they are launched.
        signals = 0
        for line in self.code_lines():
            # every kill but `kill -0` (a liveness test) is `still_ours "$x" && kill -SIG "$x"`
            for call in re.findall(r"\bkill -(?!0\b)[^;|&]*", line):
                call = call.strip()
                signals += 1
                m = re.fullmatch(r'kill -(?:TERM|KILL) "\$(pid|runner|rescue_pid)" 2>/dev/null', call)
                self.assertTrue(m, line)
                self.assertIn(f'still_ours "${m.group(1)}" && {call}', line)
        self.assertGreaterEqual(signals, 5)  # end_ours TERM and KILL, the rescue job, the runner TERM and KILL
        lines = list(self.code_lines())
        for job in ("runner", "rescue_pid"):
            i = lines.index(f"{job}=$!")
            self.assertEqual(lines[i + 1], f'remember "${job}"', job)
        text = Path(self.script).read_text()
        self.assertNotRegex(text, r"\b(pkill|killall|pgrep)\b")

        def body(name):
            start = text.index(f"\n{name}() {{")
            return text[start:text.index("\n}\n", start)]

        # The command-line match only feeds the report (foreign_pids), never what is ended (ours_pids, still_ours).
        self.assertEqual(text.count("/proc/[0-9]*/cmdline"), 1)
        self.assertIn("/proc/[0-9]*/cmdline", body("foreign_pids"))
        for name in ("ours_pids", "env_ours", "snap_ours", "end_ours"):
            self.assertNotIn("foreign_pids", body(name), name)
            self.assertNotIn("/proc/[0-9]*/cmdline", body(name), name)
        self.assertIn("still_ours", body("end_ours"))

    def test_it_is_opt_in(self):
        self.assertTrue(os.access(self.script, os.X_OK))
        self.assertNotIn("lock-nested-check", (ROOT / "scripts/test.sh").read_text())

    def code_lines(self):
        for line in Path(self.script).read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                yield line

    def test_it_reaches_the_session_only_through_the_harness(self):
        # None of these command names appears as a word in the code (file names like qs.log and variable names are
        # not words), whatever precedes it (`timeout 8 hyprctl`, `env X=1 qs`, `exec`, `command`):
        # hyprctl, qs, the rescue script and the rest go through lock-nested.sh (which gives them the nested
        # compositor's runtime dir and signature) or run in a subshell that has the nested environment, and nothing
        # locks, suspends or types into the outer session. The one list of tools it checks for is exempt.
        names = "hyprctl|qs|loginctl|systemctl|pkill|killall|busctl|ydotool|wtype|swaymsg|dbus-send|gdbus"
        command = re.compile(rf"(?<![\w.$/-])({names})(?![\w.=/-])")
        for line in self.code_lines():
            if line.startswith("for tool in "):
                continue
            self.assertIsNone(command.search(line), line)
            self.assertNotIn("lock-session", line)
        text = Path(self.script).read_text()
        self.assertIn('nl="$src/scripts/lock-nested.sh"', text)
        # Every rescue run names the nested instance and its own copy of the script, and there is one.
        rescues = [l for l in self.code_lines() if "rescue-unlock.sh" in l and "echo unlock" in l]
        self.assertGreaterEqual(len(rescues), 1)
        for line in rescues:
            self.assertIn('--force --instance "$sig"', line)
            self.assertIn('"$src/scripts/rescue-unlock.sh"', line)


class AuthHarness(unittest.TestCase):
    """scripts/auth.sh is part of the test run and never lets a check reach the account's own PAM stack."""

    script = ROOT / "scripts/auth.sh"

    def test_it_is_run_by_the_test_script(self):
        self.assertTrue(os.access(self.script, os.X_OK))
        self.assertIn('"$dir/scripts/auth.sh"', (ROOT / "scripts/test.sh").read_text())

    def test_a_failed_test_pam_folder_stops_the_run_before_qs(self):
        text = self.script.read_text()
        calls = [line for line in text.splitlines() if 'lock-test-pam.sh" ' in line]
        self.assertGreaterEqual(len(calls), 3)
        for line in calls:
            self.assertIn("|| { fail", line)
        # And an empty folder name never reaches Quickshell, which would then use the account's own stack.
        self.assertIn('[ -n "$pam" ] || { fail', text)
        self.assertLess(text.index('[ -n "$pam" ] || { fail'), text.index('"$qs_bin" -p'))

    def test_the_run_is_private_and_names_a_user_that_does_not_exist(self):
        text = self.script.read_text()
        self.assertIn("env -i", text)
        self.assertIn("USER=gutter-test", text)
        self.assertIn('GUTTER_LOCK_PAM_DIR="$pam"', text)
        self.assertNotIn("lockscreen/pam.d", text)


class ReadmeDocs(unittest.TestCase):
    """The README's Lock screen section: what it tells the user to run exists and answers, what it names is read by
    the code, and the settings table says what lib/config.js defaults to. The README side is parsed, not hardcoded."""

    @classmethod
    def setUpClass(cls):
        cls.readme = (ROOT / "README.md").read_text()
        m = re.search(r"^## Lock screen\n.*?(?=^## |\Z)", cls.readme, re.S | re.M)
        if not m:
            raise AssertionError("README has no '## Lock screen' section")
        cls.section = m.group(0)

    def code_lines(self):
        """The non-comment lines of the code (QML, JS, shell, Lua, Python) outside tests, docs and the README."""
        for path in sorted(ROOT.rglob("*")):
            rel = path.relative_to(ROOT)
            if rel.parts[0].startswith(".") or rel.parts[0] in ("tests", "docs") or path.suffix not in (".qml", ".js", ".sh", ".lua", ".py"):
                continue
            for line in path.read_text().splitlines():
                if not line.lstrip().startswith(("#", "//", "--")):
                    yield line

    def test_every_script_the_section_names_exists_and_is_executable(self):
        names = set(re.findall(r"scripts/([A-Za-z0-9_.-]+\.sh)", self.section))
        self.assertTrue({"rescue-unlock.sh", "lock-test-pam.sh", "lock-nested.sh"} <= names, names)
        for name in names:
            path = ROOT / "scripts" / name
            self.assertTrue(path.is_file(), f"README names scripts/{name}")
            self.assertTrue(os.access(path, os.X_OK), f"scripts/{name} is not executable")

    def test_the_lock_nested_commands_the_section_names_are_commands(self):
        script = str(ROOT / "scripts/lock-nested.sh")
        with tempfile.TemporaryDirectory(prefix="gnt", dir="/tmp") as tmp:
            bin_dir, _ = stand_ins(tmp)  # inert, in case a command ever got as far as running one
            env = {"PATH": f"{bin_dir}:{os.environ['PATH']}", "HOME": tmp, "XDG_RUNTIME_DIR": tmp,
                   "GUTTER_NESTED_DIR": f"{tmp}/gn"}

            def run(*args):
                return subprocess.run([script, *args], env=env, capture_output=True, text=True, stdin=subprocess.DEVNULL)

            usage = run("bogus")
            self.assertEqual(usage.returncode, 2)
            known = set(re.findall(r"lock-nested\.sh (\w+)", usage.stderr))  # the commands the script's usage lists
            # The paragraphs about the harness: every `lock-nested.sh <word>` is a command, and so is the first word of
            # every backticked span of theirs that the usage lists (`logind sleep|resume` names `logind`).
            text = "\n\n".join(para for para in self.section.split("\n\n") if "lock-nested.sh" in para)
            after = set(re.findall(r"lock-nested\.sh (\w+)", text))
            words = after | (set(re.findall(r"`(\w+)[ `|]", text)) & known)
            self.assertTrue({"start", "ipc", "shell", "ctl", "env", "logind"} <= words, words)
            for word in sorted(words):
                # A command refuses (exit 1: no session, no Wayland display); an unknown word prints the usage (exit 2).
                r = run(word)
                self.assertEqual(r.returncode, 1, (word, r.stderr))
                self.assertNotIn("Usage", r.stderr, word)
            self.assertEqual(Path(tmp, "calls.log").read_text(), "")

    def test_the_rescue_flags_the_section_names_are_the_scripts_own(self):
        flags = set(re.findall(r"(?<![\w-])(--[a-z]+)\b", self.section.partition("### The way out")[2].partition("###")[0]))
        self.assertTrue({"--force", "--instance"} <= flags, flags)  # (it also names `--value` of loginctl)
        with tempfile.TemporaryDirectory() as tmp:
            bin_dir, _ = stand_ins(tmp)  # inert, in case the script ever got past its usage
            r = subprocess.run([str(ROOT / "scripts/rescue-unlock.sh"), "--bogus"], capture_output=True, text=True,
                               env={"PATH": f"{bin_dir}:{os.environ['PATH']}", "HOME": tmp, "XDG_RUNTIME_DIR": tmp, "GUTTER_RESCUE_DRY": "1"},
                               stdin=subprocess.DEVNULL)
        self.assertEqual(r.returncode, 2)
        for flag in ("--force", "--instance"):
            self.assertIn(flag, r.stderr)  # the usage line

    def test_every_environment_variable_the_section_names_is_read_by_the_code(self):
        names = set(re.findall(r"\bGUTTER_[A-Z_]+\b", self.section))
        self.assertTrue({"GUTTER_LOCK_PAM_DIR", "GUTTER_LOCK_DRY_RUN", "GUTTER_RESCUE_DRY"} <= names, names)
        lines = list(self.code_lines())
        for name in sorted(names):
            # Read: `env("NAME")`, `environ.get("NAME")` or `$NAME` / `${NAME`; not `NAME=value`, which sets it.
            read = re.compile(rf"""(["'])({name})\1|\$\{{?{name}\b""")
            self.assertTrue(any(read.search(l) for l in lines), f"the README names {name}, but nothing reads it")

    def test_every_lock_and_idle_variable_the_code_reads_is_documented(self):
        read = set()
        for line in self.code_lines():
            read |= set(re.findall(r"""["'](GUTTER_(?:LOCK|IDLE)_[A-Z_]+)["']""", line))
            read |= set(re.findall(r"\$\{?(GUTTER_(?:LOCK|IDLE)_[A-Z_]+)\b", line))
        self.assertGreaterEqual(len(read), 5, read)
        for name in sorted(read):
            self.assertIn(name, self.section, f"the code reads {name}, but the README does not name it")

    def test_the_settings_table_gives_the_defaults_in_config_js(self):
        table = dict(re.findall(r"^\| `(lockscreen\.[A-Za-z.]+)` \| `([^`]*)` \|", self.section, re.M))
        text = (ROOT / "lib/config.js").read_text()
        # The rows of the defaults table: a line that starts `"lockscreen.x": {` (its spec: `type: ..., def: ..., ...}`).
        row = r'^\s*"(lockscreen\.[A-Za-z.]+)"\s*:\s*\{'
        keys = re.findall(row, text, re.M)
        # Defaults: true, false, a number or a quoted string; anything else fails here rather than being skipped.
        config = {k: v.strip('"') for k, v in re.findall(
            row + r'[^}\n]*?\bdef:\s*(true|false|-?\d+(?:\.\d+)?|"[^"]*")\s*[,}]', text, re.M)}
        self.assertGreaterEqual(len(keys), 6)
        self.assertEqual(sorted(config), sorted(keys), "a lockscreen default in lib/config.js is not true, false, a number or a string")
        self.assertEqual(table, config)  # every key is documented, with the default it has


if __name__ == "__main__":
    unittest.main()
