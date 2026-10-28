import os, shutil, subprocess, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
LOADER = ROOT / "hypr/loader.lua.in"
KEYBINDS = ROOT / "hypr/gutter/keybinds.lua"


# A plain-Lua stand-in for Hyprland's `hl`: every call is a no-op except bind, exec_cmd and on, which are recorded.
# Runs the rendered loader, prints what it did at load ("BIND key action", "EXEC cmd"), then fires the
# hyprland.start handlers and prints what they did after the "START" line.
HARNESS = r"""
local function proxy()
    return setmetatable({}, { __index = function() return proxy() end, __call = function() return proxy() end })
end
local handlers = {}
hl = proxy()
hl.dsp = proxy()
hl.dsp.exec_cmd = function(c) return "exec:" .. c end
hl.bind = function(key, action) print("BIND " .. key .. " " .. tostring(type(action) == "string" and action or "")) end
hl.exec_cmd = function(c) print("EXEC " .. c) end
hl.on = function(ev, f) handlers[ev] = handlers[ev] or {}; table.insert(handlers[ev], f) end
dofile(arg[1])
print("START")
for _, f in ipairs(handlers["hyprland.start"] or {}) do f() end
"""
LUA = shutil.which("lua") or shutil.which("lua5.4")


def run_harness(loader_text, d, marker=False):
    """Runs the loader in the harness with an empty runtime dir; marker pre-creates the 'session started' file.
    Returns (lines before START, lines after START)."""
    env = dict(os.environ, HOME=d, XDG_CONFIG_HOME=d + "/config", XDG_STATE_HOME=d + "/state",
               XDG_RUNTIME_DIR=d + "/run", HYPRLAND_INSTANCE_SIGNATURE="sig")
    if marker:
        (Path(d) / "run/gutter").mkdir(parents=True)
        (Path(d) / "run/gutter/hypr-started-sig").write_text("")
    loader = Path(d) / "loader.lua"
    loader.write_text(loader_text)
    drv = Path(d) / "harness.lua"
    drv.write_text(HARNESS)
    r = subprocess.run([LUA, str(drv), str(loader)], env=env, capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stdout + r.stderr
    lines = r.stdout.splitlines()
    i = lines.index("START")
    return lines[:i], lines[i + 1:]


def verify(loader_text, d):
    """Writes the loader into d and runs Hyprland --verify-config on it. HOME and the XDG folders are empty temp
    folders: nothing of the live session is read or written."""
    env = dict(os.environ, HOME=d, XDG_CONFIG_HOME=d + "/config", XDG_STATE_HOME=d + "/state",
               XDG_CACHE_HOME=d + "/cache", XDG_DATA_HOME=d + "/data", XDG_RUNTIME_DIR=d)
    loader = Path(d) / "hyprland.lua"
    loader.write_text(loader_text)
    return subprocess.run(["Hyprland", "--verify-config", "-c", str(loader)], env=env, capture_output=True,
                          text=True, timeout=60)


class HyprLoader(unittest.TestCase):
    def render(self, repo):
        return LOADER.read_text().replace("@REPO@", str(repo))

    def test_loader_template_shape(self):
        text = LOADER.read_text()
        self.assertIn("[==[@REPO@]==] .. \"/hypr/?.lua;\"", text)
        self.assertIn('package.searchpath("gutter", package.path)', text)

    @unittest.skipUnless(shutil.which("Hyprland"), "Hyprland is not installed")
    def test_loader_loads_repo_config(self):
        with tempfile.TemporaryDirectory() as d:
            # The loader handles a failure, so only this line tells a loaded config from the fallback.
            r = verify(self.render(ROOT) + "\nif not ok then error(err) end\n", d)
            out = r.stdout + r.stderr
            self.assertEqual(r.returncode, 0, out)
            self.assertIn("config ok", out.lower(), out)
            self.assertNotIn("error", out.lower(), out)

    @unittest.skipUnless(shutil.which("Hyprland"), "Hyprland is not installed")
    def test_loader_fallback_binds_terminal(self):
        text = LOADER.read_text()
        self.assertRegex(text, r'hl\.bind\("SUPER \+ Return",\s*hl\.dsp\.exec_cmd\("foot"\)\)')
        self.assertIn("notify-send", text)
        self.assertIn("Gutter Hyprland config failed", text)
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / "repo"
            (repo / "hypr").mkdir(parents=True)
            (repo / "hypr/gutter.lua").write_text('error("boom")\n')
            # Fails the verify unless the loader really took its failure path.
            r = verify(self.render(repo) + '\nif ok or not tostring(err):find("boom", 1, true) then error("not the fallback") end\n', d)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_fallback_shell_and_notifications(self):
        text = LOADER.read_text()
        self.assertNotIn("config.reloaded", text)  # the Lua state is rebuilt on reload; the marker file carries on
        self.assertEqual(text.count("qs -c gutter"), 1)  # not started again on a reload

    @unittest.skipUnless(shutil.which("Hyprland"), "Hyprland is not installed")
    def test_loader_with_awkward_repo_path(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d) / 'my repo "quoted" \\x'
            shutil.copytree(ROOT / "hypr", repo / "hypr")
            r = verify(self.render(repo) + "\nif not ok then error(err) end\n", d)
            out = r.stdout + r.stderr
            self.assertEqual(r.returncode, 0, out)
            self.assertIn("config ok", out.lower(), out)

    def broken_repo(self, d, module, text):
        repo = Path(d) / "repo"
        shutil.copytree(ROOT / "hypr", repo / "hypr")
        (repo / "hypr" / module).write_text(text)
        return repo

    @unittest.skipUnless(LUA, "lua is not installed")
    def test_failed_load_before_start_queues_shell_and_notification(self):
        with tempfile.TemporaryDirectory() as d:
            repo = self.broken_repo(d, "gutter.lua", 'error("it\'s $(x)")\n')
            before, after = run_harness(self.render(repo), d)
            self.assertIn("BIND SUPER + Return exec:foot", before)
            self.assertFalse([l for l in before if l.startswith("EXEC")], before)
            self.assertTrue(any("mkdir -p" in l and "hypr-started-sig" in l for l in after), after)
            self.assertIn("EXEC qs -c gutter -n -d", after)
            notify = [l for l in after if "notify-send" in l]
            self.assertEqual(len(notify), 1, after)
            self.assertTrue(notify[0].startswith("EXEC sleep 2; notify-send -u critical -- 'Gutter Hyprland config failed' '"))
            self.assertIn("it'\\''s $(x)", notify[0])  # quoted, not interpreted

    @unittest.skipUnless(LUA, "lua is not installed")
    def test_failed_load_on_reload_notifies_at_once(self):
        with tempfile.TemporaryDirectory() as d:
            repo = self.broken_repo(d, "gutter.lua", 'error("boom")\n')
            before, after = run_harness(self.render(repo), d, marker=True)
            self.assertIn("BIND SUPER + Return exec:foot", before)
            notify = [l for l in before if "notify-send" in l]
            self.assertEqual(len(notify), 1, before)
            self.assertTrue(notify[0].startswith("EXEC notify-send -u critical -- "), notify)
            self.assertFalse([l for l in before + after if "qs -c" in l], before + after)
            self.assertFalse([l for l in after if "notify-send" in l], after)

    @unittest.skipUnless(LUA, "lua is not installed")
    def test_intact_load_only_writes_the_marker(self):
        with tempfile.TemporaryDirectory() as d:
            before, after = run_harness(self.render(ROOT), d)
            self.assertFalse([l for l in before if "SUPER + Return" in l and "failsafe" in l.lower()], before)
            self.assertTrue([l for l in before if l.startswith("BIND SUPER + T ")], before)
            self.assertFalse([l for l in before + after if "config failed" in l], before + after)
            self.assertEqual(len([l for l in after if "hypr-started-sig" in l]), 1, after)

    @unittest.skipUnless(LUA, "lua is not installed")
    def test_broken_keybinds_bind_terminal_and_notify(self):
        with tempfile.TemporaryDirectory() as d:
            repo = self.broken_repo(d, "gutter/keybinds.lua", 'error("boom")\n')
            before, after = run_harness(self.render(repo), d)
            self.assertIn("BIND SUPER + Return exec:foot", before)
            self.assertFalse([l for l in before if l.startswith("BIND SUPER + T ")], before)
            self.assertEqual(len([l for l in after if "qs -c gutter" in l]), 1, after)  # execs.lua's, not a second
            self.assertEqual(len([l for l in after if "notify-send" in l and "boom" in l]), 1, after)
        with tempfile.TemporaryDirectory() as d:
            repo = self.broken_repo(d, "gutter/keybinds.lua", 'error("boom")\n')
            before, after = run_harness(self.render(repo), d, marker=True)
            self.assertEqual(len([l for l in before if l.startswith("EXEC notify-send") and "boom" in l]), 1, before)

    @unittest.skipUnless(shutil.which("Hyprland"), "Hyprland is not installed")
    def test_broken_keybinds_still_verify(self):
        with tempfile.TemporaryDirectory() as d:
            repo = self.broken_repo(d, "gutter/keybinds.lua", 'error("boom")\n')
            r = verify(self.render(repo), d)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_keybinds_has_gutter_and_media_binds(self):
        text = KEYBINDS.read_text()
        for name in ("brightnessUp", "brightnessDown", "toggle", "launcher", "session", "lock", "volumeUp",
                     "volumeDown", "volumeMute", "mediaToggle", "mediaNext", "mediaPrev", "mediaStop"):
            self.assertTrue('hl.dsp.global("gutter:%s")' % name in text or 'glob("%s")' % name in text, name)
        code = "\n".join(l for l in text.lower().replace("kbclipboardpastelatest", "").splitlines()
                         if not l.strip().startswith("--"))
        for gone in ("screenshot", "record", "clipboard", "emoji", "restore", "kill", "sidebar", "clearnotifs",
                     "showpanels"):
            self.assertNotIn(gone, code)


if __name__ == "__main__":
    unittest.main()
