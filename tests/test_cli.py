import json, os, shutil, subprocess, tempfile, unittest
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "tools/gutter"

V1_SAMPLE = {
    "version": 1, "source": "", "ink": "#0e0d0e", "paper": "#fbf6d3",
    "accents": {"navy": "#224969", "teal": "#22a5a6", "magenta": "#8e3fa0", "coral": "#e2492f",
                "sun": "#f6d14b", "lime": "#a3d23a", "pink": "#e8739d"},
    "roles": {"active": "sun", "urgent": "coral", "focusBorder": "teal", "ok": "lime", "special": "magenta", "muted": "navy"},
}

def blocks(path, colours):
    img = Image.new("RGB", (70 * len(colours), 70))
    for i, c in enumerate(colours):
        img.paste(c, (70 * i, 0, 70 * (i + 1), 70))
    img.save(path)

class Cli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.state = self.dir / "state"
        self.hypr_out = self.dir / "hypr-gutter.lua"
        self.log = self.dir / "calls.log"
        self.log.touch()
        stubs = self.dir / "stubs"
        stubs.mkdir()
        # Stubs go in front of the real PATH, so every command apply can run needs one: an unstubbed pkill or
        # gsettings would signal or reconfigure the user's live desktop, and an unstubbed qs would flip the live shell.
        for name in ("hyprctl", "notify-send", "pkill", "gsettings", "qs"):
            stub = stubs / name
            stub.write_text('#!/bin/sh\necho "%s $*" >> "%s"\n' % (name, self.log))
            stub.chmod(0o755)
        self.config = self.dir / ".config"
        self.icons = self.dir / "icons"
        self.icons.mkdir()
        self.env = dict(os.environ,
                        HOME=str(self.dir),
                        XDG_STATE_HOME=str(self.state),
                        XDG_CONFIG_HOME=str(self.config),
                        GUTTER_ICONS_DIR=str(self.icons),
                        GUTTER_HYPR_OUT=str(self.hypr_out),
                        PATH="%s:%s" % (stubs, os.environ["PATH"]))
        self.blocks_image = self.dir / "blocks.png"
        blocks(self.blocks_image, [(230, 70, 45), (245, 205, 60), (160, 210, 60), (30, 165, 165),
                                   (35, 70, 110), (140, 60, 160), (235, 115, 155), (10, 10, 10), (250, 245, 210)])
        self.mono_image = self.dir / "mono.png"
        Image.new("RGB", (70, 70), (128, 128, 128)).save(self.mono_image)

    def cli(self, *args):
        return subprocess.run([str(CLI), *args], capture_output=True, text=True, env=self.env)

    # Replaces a stub with one that logs and exits 1.
    def failing_stub(self, name):
        stub = self.dir / "stubs" / name
        stub.write_text('#!/bin/sh\necho "%s $*" >> "%s"\nexit 1\n' % (name, self.log))

    def test_wall_set_writes_path_palette_and_lua(self):
        r = self.cli("wall", "set", str(self.blocks_image))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((self.state / "gutter/wallpaper").read_text().strip(), str(self.blocks_image))
        self.assertTrue((self.state / "gutter/palette.json").exists())
        self.assertIn("rounding = 0", self.hypr_out.read_text())
        self.assertIn("hyprctl reload", self.log.read_text())

    def test_wall_set_with_spaces_in_path(self):
        img = self.dir / "my wall.png"
        shutil.copy(self.blocks_image, img)
        r = self.cli("wall", "set", str(img))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((self.state / "gutter/wallpaper").read_text().strip(), str(img))

    def test_relative_path_is_stored_absolute(self):
        r = subprocess.run([str(CLI), "wall", "set", "blocks.png"], capture_output=True, text=True,
                           env=self.env, cwd=self.dir)
        self.assertEqual(r.returncode, 0, r.stderr)
        stored = (self.state / "gutter/wallpaper").read_text().strip()
        self.assertTrue(os.path.isabs(stored))
        self.assertEqual(os.path.realpath(stored), os.path.realpath(self.blocks_image))

    def test_monochrome_notifies_and_keeps_palette(self):
        self.cli("palette", "default")
        before = (self.state / "gutter/palette.json").read_text()
        self.log.write_text("")
        r = self.cli("wall", "set", str(self.mono_image))
        self.assertEqual(r.returncode, 1)
        self.assertEqual((self.state / "gutter/palette.json").read_text(), before)
        log = self.log.read_text()
        self.assertIn("notify-send", log)
        self.assertNotIn("hyprctl", log)
        self.assertIn("palette:", r.stderr)

    def test_missing_image_is_usage_error(self):
        r = self.cli("wall", "set", "/nope.jpg")
        self.assertEqual(r.returncode, 2)
        self.assertIn("usage", r.stderr.lower())
        self.assertEqual(self.log.read_text(), "")

    def test_directory_is_usage_error(self):
        self.assertEqual(self.cli("wall", "set", str(self.dir)).returncode, 2)

    def test_bad_arguments_are_usage_errors(self):
        for args in ([], ["wall"], ["wall", "set"], ["palette"], ["palette", "bogus"], ["bogus"]):
            r = self.cli(*args)
            self.assertEqual(r.returncode, 2, args)
            self.assertIn("usage", r.stderr.lower())
        self.assertEqual(self.log.read_text(), "")

    def test_default_restores_hand_tuned(self):
        r = self.cli("palette", "default")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads((self.state / "gutter/palette.json").read_text())["light"]["accents"]["teal"], "#22a5a6")
        self.assertIn("rounding = 0", self.hypr_out.read_text())
        self.assertIn("hyprctl reload", self.log.read_text())

    def test_regen_uses_stored_wallpaper(self):
        self.cli("wall", "set", str(self.blocks_image))
        self.cli("palette", "default")
        r = self.cli("palette", "regen")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads((self.state / "gutter/palette.json").read_text())["source"], str(self.blocks_image))

    def test_regen_without_wallpaper_fails(self):
        r = self.cli("palette", "regen")
        self.assertEqual(r.returncode, 1)
        self.assertIn("gutter: no wallpaper set", r.stderr)
        self.assertIn("notify-send", self.log.read_text())
        self.assertNotIn("hyprctl", self.log.read_text())

    def test_regen_with_empty_wallpaper_fails(self):
        (self.state / "gutter").mkdir(parents=True)
        (self.state / "gutter/wallpaper").write_text("\n")
        r = self.cli("palette", "regen")
        self.assertEqual(r.returncode, 1)
        self.assertIn("gutter: no wallpaper set", r.stderr)

    def test_hyprctl_failure_notifies_and_exits_1(self):
        stub = self.dir / "stubs/hyprctl"
        stub.write_text('#!/bin/sh\necho "hyprctl $*" >> "%s"\nexit 3\n' % self.log)
        r = self.cli("palette", "default")
        self.assertEqual(r.returncode, 1)
        self.assertIn("notify-send", self.log.read_text())

    def test_theme_apply_writes_theme_json_and_reloads(self):
        self.cli("palette", "default")
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads((self.state / "gutter/theme.json").read_text()), {"version": 1, "mode": "dark"})
        self.assertIn("hyprctl reload", self.log.read_text())
        dark = json.loads((ROOT / "theme/default-palette.json").read_text())["dark"]
        light = json.loads((ROOT / "theme/default-palette.json").read_text())["light"]
        self.assertNotEqual(dark["ink"], light["ink"])
        lua = self.hypr_out.read_text()
        self.assertIn('inactive_border = "rgb(%s)"' % dark["ink"].lstrip("#"), lua)
        self.assertIn('color = "rgba(%sff)"' % dark["accents"]["teal"].lstrip("#"), lua)
        self.assertEqual(self.cli("theme", "apply", "light").returncode, 0)
        lua = self.hypr_out.read_text()
        self.assertIn('inactive_border = "rgb(%s)"' % light["ink"].lstrip("#"), lua)
        self.assertNotIn(dark["ink"].lstrip("#"), lua)

    def test_hypr_output_defaults_to_the_state_folder(self):
        env = {k: v for k, v in self.env.items() if k != "GUTTER_HYPR_OUT"}
        r = subprocess.run([str(CLI), "hypr"], capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("rounding = 0", (self.state / "gutter/hypr-gutter.lua").read_text())

    def test_theme_apply_follows_the_shadow_setting(self):
        (self.config / "gutter").mkdir(parents=True)
        (self.config / "gutter/config.json").write_text('{"shadow": {"color": "ink"}}')
        self.assertEqual(self.cli("theme", "apply", "dark").returncode, 0)
        dark = json.loads((ROOT / "theme/default-palette.json").read_text())["dark"]
        self.assertIn('color = "rgba(%sff)"' % dark["ink"].lstrip("#"), self.hypr_out.read_text())

    def shadow_setting(self, colour):
        (self.config / "gutter").mkdir(parents=True, exist_ok=True)
        (self.config / "gutter/config.json").write_text('{"shadow": {"color": "%s"}}' % colour)

    def test_hypr_writes_for_mode_on_screen_and_reloads(self):
        (self.state / "gutter").mkdir(parents=True)
        (self.state / "gutter/theme.json").write_text('{"version": 1, "mode": "dark"}')
        self.shadow_setting("ink")
        r = self.cli("hypr")
        self.assertEqual(r.returncode, 0, r.stderr)
        dark = json.loads((ROOT / "theme/default-palette.json").read_text())["dark"]
        self.assertIn('color = "rgba(%sff)"' % dark["ink"].lstrip("#"), self.hypr_out.read_text())
        self.assertIn("hyprctl reload", self.log.read_text())

    def test_hypr_unchanged_does_not_reload(self):
        self.assertEqual(self.cli("hypr").returncode, 0)
        self.log.write_text("")
        r = self.cli("hypr")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("hyprctl reload", self.log.read_text())
        self.shadow_setting("coral")
        self.assertEqual(self.cli("hypr").returncode, 0)
        self.assertIn("hyprctl reload", self.log.read_text())

    def test_hypr_without_palette_or_config(self):
        r = self.cli("hypr")
        self.assertEqual(r.returncode, 0, r.stderr)
        light = json.loads((ROOT / "theme/default-palette.json").read_text())["light"]
        self.assertIn('color = "rgba(%sff)"' % light["accents"]["teal"].lstrip("#"), self.hypr_out.read_text())
        self.assertFalse((self.state / "gutter/palette.json").exists())

    def test_hypr_bad_arguments_are_usage(self):
        self.assertEqual(self.cli("hypr", "x").returncode, 2)

    def test_hypr_failure_notifies_and_exits_1(self):
        self.failing_stub("hyprctl")
        r = self.cli("hypr")
        self.assertEqual(r.returncode, 1)
        self.assertIn("notify-send", self.log.read_text())

    def test_apply_without_palette_uses_the_default(self):
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.returncode, 0, r.stderr)
        dark = json.loads((ROOT / "theme/default-palette.json").read_text())["dark"]
        self.assertIn('inactive_border = "rgb(%s)"' % dark["ink"].lstrip("#"), self.hypr_out.read_text())
        self.assertIn("@define-color window_bg_color %s;" % dark["paper"], (self.config / "gtk-3.0/gtk.css").read_text())
        self.assertEqual(json.loads((self.state / "gutter/theme.json").read_text())["mode"], "dark")
        self.assertFalse((self.state / "gutter/palette.json").exists())     # used, not written into place
        self.assertNotIn("notify-send", self.log.read_text())

    def test_apply_upgrades_v1_palette(self):
        (self.state / "gutter").mkdir(parents=True)
        (self.state / "gutter/palette.json").write_text(json.dumps(V1_SAMPLE))
        self.assertEqual(self.cli("theme", "apply", "light").returncode, 0)
        self.assertEqual(json.loads((self.state / "gutter/palette.json").read_text())["version"], 2)

    def test_theme_apply_writes_apps_and_signals(self):
        self.cli("palette", "default")
        self.log.write_text("")
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.returncode, 0, r.stderr)
        for rel in ("foot/gutter.ini", "fuzzel/gutter.ini", "gtk-3.0/gtk.css", "gtk-4.0/thunar.css",
                    "qtengine/config.json"):
            self.assertTrue((self.config / rel).exists(), rel)
        self.assertIn("initial-color-theme=dark", (self.config / "foot/gutter.ini").read_text())
        log = self.log.read_text().splitlines()
        self.assertIn("pkill -USR1 -x foot", log)
        self.assertIn("gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark", log)
        self.assertIn("gsettings set org.gnome.desktop.interface color-scheme prefer-dark", log)
        self.assertFalse((self.config / "btop").exists())
        self.assertFalse(any("btop" in line for line in log))
        self.assertFalse(any("icon-theme" in line for line in log))
        self.assertEqual(self.cli("theme", "apply", "light").returncode, 0)
        self.assertIn("pkill -USR2 -x foot", self.log.read_text().splitlines())
        self.assertIn("initial-color-theme=light", (self.config / "foot/gutter.ini").read_text())

    def test_theme_apply_icon_theme_and_btop(self):
        (self.icons / "Papirus-Dark").mkdir()
        (self.config / "btop").mkdir(parents=True)
        self.cli("palette", "default")
        self.log.write_text("")
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.returncode, 0, r.stderr)
        log = self.log.read_text().splitlines()
        self.assertIn("gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark", log)
        self.assertIn("pkill -USR2 -x btop", log)
        self.assertTrue((self.config / "btop/themes/gutter.theme").exists())
        self.assertEqual((self.config / "btop/btop.conf").read_text(), 'color_theme = "gutter"\n')

    def test_no_foot_running_is_fine(self):
        stub = self.dir / "stubs/pkill"
        stub.write_text('#!/bin/sh\necho "pkill $*" >> "%s"\nexit 1\n' % self.log)
        self.cli("palette", "default")
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("pkill -USR1 -x foot", self.log.read_text())

    @unittest.skipIf(os.geteuid() == 0, "root writes through the mode")
    def test_one_app_failing(self):
        gtk4 = self.config / "gtk-4.0"
        gtk4.mkdir(parents=True)
        gtk4.chmod(0o500)
        self.addCleanup(gtk4.chmod, 0o755)
        self.cli("palette", "default")
        self.log.write_text("")
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.returncode, 1)
        self.assertIn("apps: failed: gtk", r.stderr)
        self.assertTrue((self.config / "foot/gutter.ini").exists())
        self.assertTrue((self.config / "fuzzel/gutter.ini").exists())
        log = self.log.read_text()
        self.assertIn("pkill -USR1 -x foot", log)
        self.assertNotIn("gsettings", log)
        self.assertEqual(json.loads((self.state / "gutter/theme.json").read_text())["mode"], "dark")
        self.assertIn("notify-send", log)

    def test_malformed_palette_is_a_clear_error(self):
        (self.state / "gutter").mkdir(parents=True)
        pal = json.loads((ROOT / "theme/default-palette.json").read_text())
        del pal["dark"]["accents"]["magenta"]
        (self.state / "gutter/palette.json").write_text(json.dumps(pal))
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.returncode, 1)
        self.assertIn("apps: the dark half has no accent 'magenta'", r.stderr)
        self.assertNotIn("Traceback", r.stderr)
        self.assertIn("notify-send", self.log.read_text())
        self.assertFalse((self.config / "foot").exists())

    def test_theme_apply_bad_mode_is_usage(self):
        for args in (("theme", "apply", "dusk"), ("theme", "apply"), ("theme", "apply", "dark", "x"), ("theme",)):
            self.assertEqual(self.cli(*args).returncode, 2, args)
        self.assertEqual(self.log.read_text(), "")

    def test_regen_keeps_current_mode(self):
        self.cli("palette", "default"); self.cli("theme", "apply", "dark")
        self.cli("wall", "set", str(self.blocks_image))
        self.assertEqual(json.loads((self.state / "gutter/theme.json").read_text())["mode"], "dark")

    def test_default_keeps_current_mode(self):
        self.cli("palette", "default"); self.cli("theme", "apply", "dark")
        self.cli("palette", "default")
        self.assertEqual(json.loads((self.state / "gutter/theme.json").read_text())["mode"], "dark")

    def test_invalid_theme_json_means_light(self):
        (self.state / "gutter").mkdir(parents=True)
        (self.state / "gutter/theme.json").write_text("not json")
        self.assertEqual(self.cli("palette", "default").returncode, 0)
        self.assertEqual(json.loads((self.state / "gutter/theme.json").read_text())["mode"], "light")

    def test_theme_toggle_calls_ipc(self):
        self.assertEqual(self.cli("theme", "toggle").returncode, 0)
        self.assertIn("qs -c gutter ipc call gutter themeToggle", self.log.read_text())

    def test_theme_light_calls_ipc(self):
        self.assertEqual(self.cli("theme", "light").returncode, 0)
        self.assertIn("qs -c gutter ipc call gutter themeSet light", self.log.read_text())

    def test_theme_dark_calls_ipc(self):
        self.assertEqual(self.cli("theme", "dark").returncode, 0)
        self.assertIn("qs -c gutter ipc call gutter themeSet dark", self.log.read_text())
        self.assertFalse((self.state / "gutter/theme.json").exists())

    def test_theme_flip_without_shell(self):
        self.failing_stub("qs")
        r = self.cli("theme", "dark")
        self.assertEqual(r.returncode, 1)
        self.assertIn("Gutter is not running; use gutter theme apply <mode>", r.stderr)
        self.assertIn("notify-send", self.log.read_text())

    def test_no_notify_prints_only(self):
        self.failing_stub("hyprctl")
        r = subprocess.run([str(CLI), "theme", "apply", "dark"], capture_output=True, text=True,
                           env=dict(self.env, GUTTER_NO_NOTIFY="1"))
        self.assertEqual(r.returncode, 1)
        self.assertTrue(r.stderr.strip())
        self.assertNotIn("notify-send", self.log.read_text())

    # An abort that fail() did not report (here the `realpath` of the image failing, under set -e) exits 1, which the
    # shell takes for "the tool notified": so the tool notifies, once.
    def abort_stub(self, status=1):
        stub = self.dir / "stubs" / "realpath"
        stub.write_text("#!/bin/sh\nexit %d\n" % status)
        stub.chmod(0o755)

    def test_unexpected_abort_notifies_once(self):
        self.abort_stub()
        r = self.cli("wall", "set", str(self.blocks_image))
        self.assertEqual(r.returncode, 1)
        self.assertIn("gutter: unexpected failure (status 1)", r.stderr)
        self.assertEqual(len(self.notifications()), 1)

    # An abort with another status (here a `realpath` stub that exits 127) is reported once as well and exits 1 all
    # the same, so the shell never takes it for a tool that could not start (126 or 127 is `env`'s alone).
    def test_unexpected_abort_with_another_status_exits_1_and_notifies_once(self):
        self.abort_stub(127)
        r = self.cli("wall", "set", str(self.blocks_image))
        self.assertEqual(r.returncode, 1)
        self.assertIn("gutter: unexpected failure (status 127)", r.stderr)
        self.assertEqual(len(self.notifications()), 1)

    def test_unexpected_abort_with_no_notify_prints_only(self):
        self.abort_stub()
        r = subprocess.run([str(CLI), "wall", "set", str(self.blocks_image)], capture_output=True, text=True,
                           env=dict(self.env, GUTTER_NO_NOTIFY="1"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("gutter: unexpected failure (status 1)", r.stderr)
        self.assertEqual(self.notifications(), [])

    def test_usage_error_does_not_notify(self):
        r = self.cli("bogus")
        self.assertEqual(r.returncode, 2)
        self.assertNotIn("unexpected failure", r.stderr)
        self.assertEqual(self.notifications(), [])

    # A failure fail() reported is not reported again by the exit trap.
    def test_reported_failure_notifies_once(self):
        self.failing_stub("hyprctl")
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.returncode, 1)
        self.assertNotIn("unexpected failure", r.stderr)
        self.assertEqual(len(self.notifications()), 1)

    def test_theme_flip_bad_arguments_are_usage(self):
        for args in (("theme", "toggle", "x"), ("theme", "light", "dark"), ("theme", "dusk")):
            r = self.cli(*args)
            self.assertEqual(r.returncode, 2, args)
            self.assertIn("usage", r.stderr.lower())
        self.assertEqual(self.log.read_text(), "")

    def notifications(self):
        return [l for l in self.log.read_text().splitlines() if l.startswith("notify-send")]

    def test_failure_notifies_once_with_double_dash(self):
        r = self.cli("palette", "regen")
        self.assertEqual(self.notifications(), ["notify-send -a gutter -- Gutter gutter: no wallpaper set"])
        self.assertEqual(r.stderr.strip(), "gutter: no wallpaper set")

    def test_message_starting_with_a_dash_is_not_an_option(self):
        self.write_stub("hyprctl", 'echo "-h bad" >&2; exit 1')
        r = self.cli("palette", "default")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stderr.strip(), "-h bad")
        self.assertEqual(self.notifications(), ["notify-send -a gutter -- Gutter -h bad"])

    def test_fail_message_that_looks_like_an_echo_option(self):
        self.write_stub("hyprctl", "printf '%s\\n' -n >&2; exit 1")
        r = self.cli("palette", "default")
        self.assertEqual(r.stderr, "-n\n")

    def write_stub(self, name, body):
        stub = self.dir / "stubs" / name
        stub.write_text('#!/bin/sh\necho "%s $*" >> "%s"\n%s\n' % (name, self.log, body))

    def test_hyprctl_failure_message(self):
        self.write_stub("hyprctl", "exit 3")
        r = self.cli("palette", "default")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stderr.strip(), "hyprctl reload failed")
        self.assertEqual(self.notifications(), ["notify-send -a gutter -- Gutter hyprctl reload failed"])

    def test_hyprctl_stderr_is_the_message(self):
        self.write_stub("hyprctl", "echo 'no instance' >&2; exit 1")
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.stderr.strip(), "no instance")
        self.assertFalse((self.state / "gutter/theme.json").exists())

    # `hyprctl reload` answers ok whatever the config holds; `hyprctl configerrors` lists the errors.
    def config_errors_stub(self, errors):
        self.write_stub("hyprctl", 'if [ "$1" = configerrors ]; then echo "%s"; else echo ok; fi' % errors)

    def test_config_errors_in_gutters_file_fail_the_apply_after_it_finishes(self):
        msg = "Config error in file %s line 3: bad" % self.hypr_out
        self.config_errors_stub(msg)
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stderr.strip(), "Hyprland config error: " + msg)
        self.assertEqual(len(self.notifications()), 1)
        self.assertIn("hyprctl configerrors", self.log.read_text())
        # The same file would fail the same way again: reloaded once, and apply still did the rest.
        self.assertTrue((self.state / "gutter/hypr-reloaded").exists())
        self.assertEqual(json.loads((self.state / "gutter/theme.json").read_text())["mode"], "dark")
        self.assertTrue((self.config / "foot/gutter.ini").exists())

    def test_lasting_config_error_is_reloaded_once(self):
        msg = "Config error in file %s line 3: bad" % self.hypr_out
        self.config_errors_stub(msg)
        r = self.cli("hypr")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stderr.strip(), "Hyprland config error: " + msg)
        self.assertEqual(len(self.notifications()), 1)
        self.log.write_text("")
        self.assertEqual(self.cli("hypr").returncode, 0)
        self.assertNotIn("hyprctl", self.log.read_text())

    def test_config_errors_in_the_users_files_are_not_ours(self):
        self.config_errors_stub("Config error in file /home/u/.config/gutter/hypr-user.lua line 1: bad")
        r = self.cli("hypr")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.notifications(), [])
        self.assertIn("hyprctl configerrors", self.log.read_text())
        self.assertTrue((self.state / "gutter/hypr-reloaded").exists())

    def test_hyprctl_reload_ok_passes(self):
        self.write_stub("hyprctl", 'case "$1" in configerrors) ;; *) echo ok ;; esac')
        r = self.cli("hypr")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.notifications(), [])

    def test_lasting_config_error_in_apply_is_reloaded_once(self):
        msg = "Config error in file %s line 3: bad" % self.hypr_out
        self.config_errors_stub(msg)
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stderr.strip(), "Hyprland config error: " + msg)
        # ThemeMode retries the apply: the file is unchanged, so no reload, and the rest of the apply runs again.
        self.log.write_text("")
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("hyprctl", self.log.read_text())
        self.assertIn("pkill -USR1 -x foot", self.log.read_text())
        self.assertEqual(self.notifications(), [])

    def test_apply_after_a_mode_change_reloads(self):
        self.assertEqual(self.cli("theme", "apply", "dark").returncode, 0)
        self.log.write_text("")
        self.assertEqual(self.cli("theme", "apply", "dark").returncode, 0)
        self.assertNotIn("hyprctl reload", self.log.read_text())
        self.assertEqual(self.cli("theme", "apply", "light").returncode, 0)
        self.assertEqual(self.log.read_text().count("hyprctl reload"), 1)

    def test_config_errors_survive_a_failing_apps_step(self):
        msg = "Config error in file %s line 3: bad" % self.hypr_out
        self.config_errors_stub(msg)
        (self.state / "gutter").mkdir(parents=True)
        pal = json.loads((ROOT / "theme/default-palette.json").read_text())
        del pal["dark"]["accents"]["magenta"]
        (self.state / "gutter/palette.json").write_text(json.dumps(pal))
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.returncode, 1)
        self.assertIn("apps: the dark half has no accent 'magenta'", r.stderr)
        self.assertIn("Hyprland config error: " + msg, r.stderr)

    @unittest.skipIf(os.geteuid() == 0, "root writes through the mode")
    def test_config_errors_survive_a_failing_app(self):
        msg = "Config error in file %s line 3: bad" % self.hypr_out
        self.config_errors_stub(msg)
        gtk4 = self.config / "gtk-4.0"
        gtk4.mkdir(parents=True)
        gtk4.chmod(0o500)
        self.addCleanup(gtk4.chmod, 0o755)
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.returncode, 1)
        self.assertIn("apps: failed: gtk", r.stderr)
        self.assertIn("Hyprland config error: " + msg, r.stderr)
        self.assertIn("Hyprland config error: " + msg, self.log.read_text())

    def test_reload_reply_that_is_not_ok_fails(self):
        self.write_stub("hyprctl", "echo err")
        r = self.cli("theme", "apply", "dark")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stderr.strip(), "hyprctl reload: err")
        self.assertFalse((self.state / "gutter/theme.json").exists())
        self.assertFalse((self.state / "gutter/hypr-reloaded").exists())
        self.assertEqual(self.notifications(), ["notify-send -a gutter -- Gutter hyprctl reload: err"])

    def test_unreadable_checksum_fails_with_prefix(self):
        self.write_stub("cksum", "echo 'cksum: boom' >&2; exit 1")
        (self.dir / "stubs/cksum").chmod(0o755)
        for args in (("hypr",), ("theme", "apply", "dark")):
            self.log.write_text("")
            r = self.cli(*args)
            self.assertEqual(r.returncode, 1, args)
            self.assertTrue(r.stderr.startswith("gutter: cannot read "), (args, r.stderr))
            self.assertNotIn("cksum:", r.stderr)
            self.assertEqual(len(self.notifications()), 1, args)
            self.assertNotIn("hyprctl", self.log.read_text())

    def test_hypr_retries_a_failed_reload(self):
        self.failing_stub("hyprctl")
        self.assertEqual(self.cli("hypr").returncode, 1)
        self.assertTrue(self.hypr_out.exists())          # written, but not loaded
        self.write_stub("hyprctl", "exit 0")
        self.log.write_text("")
        self.assertEqual(self.cli("hypr").returncode, 0)
        self.assertIn("hyprctl reload", self.log.read_text())
        self.log.write_text("")
        self.assertEqual(self.cli("hypr").returncode, 0)
        self.assertNotIn("hyprctl", self.log.read_text())

    def test_hypr_retries_a_reload_that_failed_inside_apply(self):
        self.failing_stub("hyprctl")
        self.assertEqual(self.cli("theme", "apply", "light").returncode, 1)
        self.assertFalse((self.state / "gutter/theme.json").exists())
        self.write_stub("hyprctl", "exit 0")
        self.log.write_text("")
        self.assertEqual(self.cli("hypr").returncode, 0)
        self.assertIn("hyprctl reload", self.log.read_text())

    def test_hypr_py_failure_notifies_and_skips_reload(self):
        blocker = self.dir / "blocker"
        blocker.write_text("a file")
        env = dict(self.env, GUTTER_HYPR_OUT=str(blocker / "hypr-gutter.lua"))
        for args in (("hypr",), ("theme", "apply", "dark")):
            self.log.write_text("")
            r = subprocess.run([str(CLI), *args], capture_output=True, text=True, env=env)
            self.assertEqual(r.returncode, 1, args)
            self.assertTrue(r.stderr.startswith("hypr: "), (args, r.stderr))
            self.assertEqual(len(self.notifications()), 1, args)
            self.assertNotIn("hyprctl", self.log.read_text())
            self.assertFalse((self.state / "gutter/theme.json").exists())

    def test_runs_through_a_symlink(self):
        link = self.dir / "bin/gutter"
        link.parent.mkdir()
        link.symlink_to(CLI)
        r = subprocess.run([str(link), "palette", "default"], capture_output=True, text=True, env=self.env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads((self.state / "gutter/palette.json").read_text())["light"]["accents"]["teal"],
                         "#22a5a6")
        self.assertIn("rounding = 0", self.hypr_out.read_text())

    def test_missing_default_palette_fails_with_prefix(self):
        tools = self.dir / "repo/tools"
        shutil.copytree(ROOT / "tools", tools)       # no theme/ beside it
        r = subprocess.run([str(tools / "gutter"), "palette", "default"], capture_output=True, text=True, env=self.env)
        self.assertEqual(r.returncode, 1)
        self.assertTrue(r.stderr.startswith("gutter: cannot read "), r.stderr)
        self.assertIn("default-palette.json", r.stderr)
        self.assertEqual(len(self.notifications()), 1)
        self.assertNotIn("hyprctl", self.log.read_text())
        self.assertFalse((self.state / "gutter/palette.json").exists())

    def test_state_folder_is_made_once_per_run(self):
        # mkdir is stubbed through PATH so the calls can be counted.
        stub = self.dir / "stubs/mkdir"
        stub.write_text('#!/bin/sh\necho "mkdir $*" >> "%s"\nexec "%s" "$@"\n' % (self.log, shutil.which("mkdir")))
        stub.chmod(0o755)
        for args in (("palette", "default"), ("wall", "set", str(self.blocks_image))):
            self.log.write_text("")
            self.assertEqual(self.cli(*args).returncode, 0, args)
            mkdirs = [l for l in self.log.read_text().splitlines()
                      if l.startswith("mkdir") and str(self.state / "gutter") in l]
            self.assertEqual(len(mkdirs), 1, (args, mkdirs))

    def assert_failed_cleanly(self, r):
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertTrue(r.stderr.startswith("gutter: "), r.stderr)
        self.assertIn("notify-send", self.log.read_text())
        self.assertNotIn("hyprctl", self.log.read_text())

    @unittest.skipIf(os.geteuid() == 0, "root writes through the mode")
    def test_unwritable_state_dir_fails_with_prefix(self):
        state = self.state / "gutter"
        state.mkdir(parents=True)
        state.chmod(0o555)
        self.addCleanup(state.chmod, 0o755)
        r = self.cli("wall", "set", str(self.blocks_image))
        self.assert_failed_cleanly(r)
        self.assertEqual(list(state.iterdir()), [])

    def test_uncreatable_state_dir_fails_with_prefix(self):
        self.state.write_text("not a directory")
        self.assert_failed_cleanly(self.cli("palette", "default"))

    # The rename fails after the temp file exists: the temp file still goes.
    def test_failed_rename_leaves_no_temp_file(self):
        state = self.state / "gutter"
        (state / "wallpaper").mkdir(parents=True)
        (state / "wallpaper/keep").write_text("")
        r = self.cli("wall", "set", str(self.blocks_image))
        self.assert_failed_cleanly(r)
        self.assertEqual(sorted(p.name for p in state.iterdir()), ["wallpaper"])
        self.assertEqual(sorted(p.name for p in (state / "wallpaper").iterdir()), ["keep"])

if __name__ == "__main__":
    unittest.main()
