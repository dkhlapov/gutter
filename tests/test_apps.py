import contextlib, io, json, os, re, stat, subprocess, sys, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import apps
import palette

DEFAULT = json.loads((ROOT / "theme/default-palette.json").read_text())


def hue(hex_):
    return palette._lch(palette.rgb_to_oklab(palette.hex_to_rgb(hex_)[None])[0])[2]


def rendered(mode, app, name):
    return dict(apps.render_all(DEFAULT, mode)[app])[name]


class Apps(unittest.TestCase):
    def test_golden(self):
        for mode in ("light", "dark"):
            for app, files in apps.render_all(DEFAULT, mode).items():
                for rel, text in files:
                    golden = ROOT / "tests/golden" / ("%s-%s-%s" % (app, mode, Path(rel).name))
                    self.assertEqual(text, golden.read_text(), golden.name)

    def test_every_path_is_listed(self):
        got = {app: [rel for rel, _ in files] for app, files in apps.render_all(DEFAULT, "light").items()}
        self.assertEqual(got, {
            "foot": ["foot/gutter.ini"], "fuzzel": ["fuzzel/gutter.ini"],
            "gtk": ["gtk-3.0/gtk.css", "gtk-4.0/gtk.css"], "thunar": ["gtk-3.0/thunar.css", "gtk-4.0/thunar.css"],
            "qt": ["qtengine/gutter.colors", "qtengine/config.json"], "btop": ["btop/themes/gutter.theme"],
            "deezer": ["deezer/gutter.css"]})

    def test_nothing_is_left_unfilled(self):
        for mode in ("light", "dark"):
            for files in apps.render_all(DEFAULT, mode).values():
                for rel, text in files:
                    self.assertNotIn("{{", text, rel)

    def test_foot_has_both_sections_and_initial_theme(self):
        text = rendered("dark", "foot", "foot/gutter.ini")
        self.assertIn("[colors-light]", text); self.assertIn("[colors-dark]", text)
        self.assertIn("initial-color-theme=dark", text)
        self.assertIn("initial-color-theme=light", rendered("light", "foot", "foot/gutter.ini"))

    def test_foot_sections_do_not_depend_on_the_mode(self):
        def sections(mode):
            return rendered(mode, "foot", "foot/gutter.ini").split("[colors-light]", 1)[1]
        self.assertEqual(sections("light"), sections("dark"))

    def foot_colours(self, section):
        text = rendered("light", "foot", "foot/gutter.ini")
        body = text.split("[%s]" % section, 1)[1].split("[", 1)[0]
        return dict(line.split("=") for line in body.strip().splitlines())

    def test_foot_light_colours(self):
        c = self.foot_colours("colors-light")
        self.assertEqual(c["background"], "fbf6d3"); self.assertEqual(c["foreground"], "0e0d0e")
        self.assertEqual(c["regular0"], "0e0d0e")
        self.assertEqual(c["regular1"], "e2492f"); self.assertEqual(c["regular6"], "22a5a6")
        self.assertEqual(c["regular7"], palette.shift_l("#fbf6d3", -0.15).lstrip("#"))
        self.assertEqual(c["bright1"], palette.shift_l("#e2492f", 0.08).lstrip("#"))
        self.assertEqual(c["selection-background"], "f6d14b"); self.assertEqual(c["selection-foreground"], "0e0d0e")

    def test_foot_dark_colours(self):
        c = self.foot_colours("colors-dark")
        self.assertEqual(c["background"], "151e26"); self.assertEqual(c["foreground"], "e4dfbd")
        self.assertEqual(c["regular0"], palette.shift_l("#151e26", -0.05).lstrip("#"))
        self.assertNotEqual(c["regular0"], "fbf6d3")
        self.assertEqual(c["regular7"], "fbf6d3")
        self.assertEqual(c["regular4"], "5780a3")
        self.assertEqual(c["selection-background"], "9b6400"); self.assertEqual(c["selection-foreground"], "fbf6d3")

    def test_dark_terminal_text_uses_the_bright_accents(self):
        # The dark accents are deepened to carry cream text on chips; drawn as text on the night page they read at
        # only ~3.4:1, so the terminal's colours 1-6 are the light accents, which read at ~4:1 or better
        c = self.foot_colours("colors-dark")
        for i, name in enumerate(apps.FOOT_NORMAL, 1):
            self.assertEqual(c["regular%d" % i], DEFAULT["light"]["accents"][name].lstrip("#"), name)
            self.assertGreaterEqual(palette.contrast("#" + c["regular%d" % i], "#151e26"), 3.9, name)

    def test_text_on_accent_is_black_in_light_and_cream_in_dark(self):
        # One text colour per mode on every accent: the light ink (black) in light mode, the light paper (full cream,
        # not the dark half's soft cream text) in dark mode
        for role in palette.ACCENTS:
            q = json.loads(json.dumps(DEFAULT)); q["roles"]["active"] = role
            for mode, want in (("light", "0e0d0e"), ("dark", "fbf6d3")):
                files = apps.render_all(q, mode)
                fuzzel = dict(files["fuzzel"])["fuzzel/gutter.ini"]
                self.assertIn("selection-text=%sff" % want, fuzzel, (mode, role))
                foot = dict(files["foot"])["foot/gutter.ini"].split("[colors-%s]" % mode)[1].split("[")[0]
                self.assertIn("selection-foreground=%s" % want, foot, (mode, role))
                self.assertIn("@define-color theme_selected_fg_color #%s;" % want, dict(files["gtk"])["gtk-3.0/gtk.css"],
                              (mode, role))

    def test_dark_bright_black_reads_on_the_dark_paper(self):
        c = self.foot_colours("colors-dark")
        self.assertGreaterEqual(palette.contrast("#" + c["bright0"], "#" + c["background"]), 3.0)
        self.assertEqual(c["regular0"], palette.shift_l("#151e26", -0.05).lstrip("#"))
        self.assertEqual(self.foot_colours("colors-light")["bright0"], palette.shift_l("#0e0d0e", 0.08).lstrip("#"))

    def test_light_lime_and_sun_read_on_the_light_paper(self):
        # lime and sun are too light for text on cream: regular2/3 and bright2/3 are darkened to 3:1, hue kept, and
        # stop there so their background uses change as little as they can; dark mode keeps the accents as they are
        c, paper = self.foot_colours("colors-light"), "#fbf6d3"
        for i, accent in ((2, "#a3d23a"), (3, "#f6d14b")):
            for key in ("regular%d" % i, "bright%d" % i):
                self.assertGreaterEqual(palette.contrast("#" + c[key], paper), 3.0, key)
                self.assertLess(palette.contrast(palette.shift_l("#" + c[key], 0.02), paper), 3.0, key)
                self.assertAlmostEqual(hue("#" + c[key]), hue(accent), delta=2, msg=key)
        self.assertEqual(c["regular1"], "e2492f"); self.assertEqual(c["selection-background"], "f6d14b")
        d = self.foot_colours("colors-dark")
        self.assertEqual(d["regular2"], "a3d23a"); self.assertEqual(d["regular3"], "f6d14b")
        self.assertEqual(d["bright3"], palette.shift_l("#f6d14b", 0.08).lstrip("#"))

    def test_fuzzel_prompt_and_match_use_the_readable_special(self):
        q = json.loads(json.dumps(DEFAULT)); q["roles"]["special"] = "lime"
        text = dict(apps.render_all(q, "light")["fuzzel"])["fuzzel/gutter.ini"]
        v = apps.half_values(q, "light")
        self.assertNotEqual(v["special_text"], v["lime"])
        self.assertIn("prompt=%sff" % v["special_text"].lstrip("#"), text)
        self.assertIn("match=%sff" % v["special_text"].lstrip("#"), text)

    def test_fuzzel_square_border(self):
        text = rendered("light", "fuzzel", "fuzzel/gutter.ini")
        self.assertIn("width=3", text); self.assertIn("radius=0", text)

    def test_fuzzel_colours(self):
        for mode, paper, text_, ink in (("light", "fbf6d3", "0e0d0e", "0e0d0e"), ("dark", "151e26", "e4dfbd", "e4dfbd")):
            text = rendered(mode, "fuzzel", "fuzzel/gutter.ini")
            for line in ("background=%sff" % paper, "text=%sff" % text_, "border=%sff" % ink):
                self.assertIn(line, text, mode)
        self.assertIn("prompt=aa5bbdff", rendered("light", "fuzzel", "fuzzel/gutter.ini"))
        self.assertIn("match=a745beff", rendered("dark", "fuzzel", "fuzzel/gutter.ini"))
        self.assertIn("selection=9b6400ff", rendered("dark", "fuzzel", "fuzzel/gutter.ini"))

    def test_gtk_both_versions_agree_and_import_thunar(self):
        files = dict(apps.render_all(DEFAULT, "dark")["gtk"])
        self.assertEqual(files["gtk-3.0/gtk.css"], files["gtk-4.0/gtk.css"])
        self.assertIn("@define-color window_bg_color #151e26;", files["gtk-4.0/gtk.css"])
        self.assertIn("@define-color window_fg_color #e4dfbd;", files["gtk-4.0/gtk.css"])
        self.assertIn('@import "thunar.css";', files["gtk-4.0/gtk.css"])

    def test_gtk_defines_the_libadwaita_colour_names(self):
        want = {"accent_color", "accent_fg_color", "accent_bg_color", "window_bg_color", "window_fg_color",
                "headerbar_bg_color", "headerbar_fg_color", "popover_bg_color", "popover_fg_color", "view_bg_color",
                "view_fg_color", "card_bg_color", "card_fg_color", "sidebar_bg_color", "sidebar_fg_color",
                "sidebar_border_color", "sidebar_backdrop_color", "theme_selected_bg_color", "theme_selected_fg_color"}
        got = set(re.findall(r"@define-color (\w+)", rendered("light", "gtk", "gtk-3.0/gtk.css")))
        self.assertLessEqual(want, got)

    def test_accent_text_reaches_contrast_on_paper(self):
        for mode in ("light", "dark"):
            v = apps.half_values(DEFAULT, mode)
            for key in ("accent_text", "urgent_text", "ok_text", "special_text", "muted_text", "link_text"):
                self.assertGreaterEqual(palette.contrast(v[key], v["paper"]), 3.0, "%s %s" % (mode, key))

    def test_qt_text_on_paper_alt_reaches_contrast(self):
        def section(colours, header):
            block = colours.split(header + "\n")[1].split("\n[", 1)[0]
            return dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
        for mode in ("light", "dark"):
            v = apps.half_values(DEFAULT, mode)
            for key in ("muted", "urgent", "ok", "link", "neutral", "visited"):
                for bg in ("paper", "paper_alt"):
                    self.assertGreaterEqual(palette.contrast(v[key + "_alt_text"], v[bg]), 3.0,
                                            "%s %s on %s" % (mode, key, bg))
            colours = rendered(mode, "qt", "qtengine/gutter.colors")
            groups = re.findall(r"^\[Colors:(\w+)\]$", colours, re.M)
            self.assertEqual(sorted(groups),
                             ["Button", "Complementary", "Header", "Selection", "Tooltip", "View", "Window"])
            for group in groups:
                if group == "Selection":
                    continue
                fields = section(colours, "[Colors:%s]" % group)
                for name, value in fields.items():   # whatever the template wires, text reads on both backgrounds
                    if name.startswith("Foreground"):
                        for bg in ("BackgroundNormal", "BackgroundAlternate"):
                            self.assertGreaterEqual(palette.contrast(value, fields[bg]), 3.0,
                                                    "%s %s %s on %s" % (mode, group, name, bg))
            wm = section(colours, "[WM]")
            for fg, bg in (("activeForeground", "activeBackground"), ("inactiveForeground", "inactiveBackground")):
                self.assertGreaterEqual(palette.contrast(wm[fg], wm[bg]), 3.0, "%s WM %s on %s" % (mode, fg, bg))

    def test_qt_groups_and_config(self):
        colours = rendered("light", "qt", "qtengine/gutter.colors")
        for group in ("Window", "View", "Button", "Selection", "Tooltip"):
            self.assertIn("[Colors:%s]" % group, colours)
        sel = colours.split("[Colors:Selection]")[1].split("[", 1)[0]
        self.assertIn("BackgroundNormal=#f6d14b", sel); self.assertIn("ForegroundNormal=#0e0d0e", sel)
        win = colours.split("[Colors:Window]")[1].split("[", 1)[0]
        self.assertIn("BackgroundNormal=#fbf6d3", win); self.assertIn("ForegroundNormal=#0e0d0e", win)
        for mode, icons in (("light", "Papirus-Light"), ("dark", "Papirus-Dark")):
            cfg = json.loads(rendered(mode, "qt", "qtengine/config.json"))
            self.assertEqual(cfg["theme"]["colorScheme"], "~/.config/qtengine/gutter.colors")
            self.assertEqual(cfg["theme"]["iconTheme"], icons)
            self.assertEqual(cfg["theme"]["style"], "Darkly")

    def test_btop_colours(self):
        text = rendered("dark", "btop", "btop/themes/gutter.theme")
        self.assertIn("theme[main_bg]=#151e26", text); self.assertIn("theme[main_fg]=#e4dfbd", text)
        for box in ("cpu", "mem", "net", "proc"):
            self.assertIn("theme[%s_box]=#e4dfbd" % box, text)

    def test_deezer_sets_the_mode_in_both_theme_blocks(self):
        text = rendered("dark", "deezer", "deezer/gutter.css")
        block = text.split(':root,\n[data-theme="light"],\n[data-theme="dark"] {\n')[1].split("\n}", 1)[0]
        self.assertIn("--color-bg-main: #151e26;", block)
        self.assertIn("--color-text-main: #e4dfbd;", block)
        light = rendered("light", "deezer", "deezer/gutter.css")
        self.assertIn("--color-bg-main: #fbf6d3;", light)
        self.assertIn("--color-accent-main: #f6d14b;", light)

    def test_deezer_wires_tempo_tokens_and_leaves_brand_tiles(self):
        text = rendered("dark", "deezer", "deezer/gutter.css")
        self.assertIn("--tempo-colors-background-neutral-primary-default: var(--color-bg-main) !important;", text)
        self.assertIn("--tempo-colors-text-accent-onAccent-default: var(--color-on-accent) !important;", text)
        self.assertIn("--tempo-colors-border-neutral-primary-focused: var(--color-accent-main) !important;", text)
        self.assertNotIn("--tempo-colors-background-brand", text)
        self.assertNotIn("--tempo-colors-background-accent-onColor", text)
        self.assertEqual(len(re.findall(r"--tempo-colors-\S+: ", text)), len(set(re.findall(r"--tempo-colors-\S+: ", text))))

    def test_deezer_text_reaches_contrast_on_its_backgrounds(self):
        for mode in ("light", "dark"):
            text = rendered(mode, "deezer", "deezer/gutter.css")
            var = dict(re.findall(r"(--[\w-]+): (#[0-9a-f]{6});", text))
            for fg, minimum in (("--color-text-main", 4.5), ("--color-text-secondary", 3.0),
                                ("--color-accent-text", 3.0), ("--color-feedback-error-text", 3.0),
                                ("--color-feedback-success-text", 3.0), ("--color-feedback-warning-text", 3.0)):
                for bg in ("--color-bg-main", "--color-bg-secondary"):
                    self.assertGreaterEqual(palette.contrast(var[fg], var[bg]), minimum, "%s %s on %s" % (mode, fg, bg))
            self.assertGreaterEqual(palette.contrast(var["--color-on-accent"], var["--color-accent-main"]), 3.0, mode)

    def test_deezer_comic_layer_uses_no_generated_class_names(self):
        text = rendered("light", "deezer", "deezer/gutter.css")
        self.assertNotRegex(text, r"\.css-[\w-]+")
        self.assertIn('[data-testid="search_container"] {\n  border: 2px solid #0e0d0e;', text)
        self.assertIn("box-shadow: 4px 4px 0 #22a5a6;", text)
        self.assertNotIn("_thumbnail", text)    # the rounded covers are left alone

    def test_follows_palette(self):
        q = json.loads(json.dumps(DEFAULT)); q["light"]["paper"] = "#ffffff"
        self.assertIn("window_bg_color #ffffff;", dict(apps.render_all(q, "light")["gtk"])["gtk-3.0/gtk.css"])

    def test_bad_mode_raises(self):
        with self.assertRaises(ValueError): apps.render_all(DEFAULT, "sepia")

    def test_unknown_placeholder_raises(self):
        with self.assertRaises(KeyError): apps.fill("{{ nope }}", {})

    def test_fill_replaces_every_placeholder(self):
        self.assertEqual(apps.fill("{{a}} and {{ b }}", {"a": "1", "b": "2"}), "1 and 2")


class Apply(unittest.TestCase):
    """apps.apply with a logging fake for `run`: nothing here can reach a real pkill or gsettings."""
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.cfg = Path(tmp.name) / "config"
        self.cfg.mkdir()
        self.icons = Path(tmp.name) / "icons"
        self.icons.mkdir()
        old = os.environ.get("GUTTER_ICONS_DIR")
        os.environ["GUTTER_ICONS_DIR"] = str(self.icons)
        self.addCleanup(lambda: os.environ.pop("GUTTER_ICONS_DIR") if old is None
                        else os.environ.__setitem__("GUTTER_ICONS_DIR", old))
        self.flatpak = Path(tmp.name) / "flatpak-config"        # not created: Deezer is not installed as a Flatpak
        old_flatpak = os.environ.get("GUTTER_DEEZER_FLATPAK_DIR")
        os.environ["GUTTER_DEEZER_FLATPAK_DIR"] = str(self.flatpak)
        self.addCleanup(lambda: os.environ.pop("GUTTER_DEEZER_FLATPAK_DIR") if old_flatpak is None
                        else os.environ.__setitem__("GUTTER_DEEZER_FLATPAK_DIR", old_flatpak))
        self.calls = []
        self.exit_codes = {}
        self.missing = set()

    def logging_run(self, argv, **kwargs):
        self.calls.append(list(argv))
        if argv[0] in self.missing:
            raise FileNotFoundError(argv[0])
        return subprocess.CompletedProcess(argv, self.exit_codes.get(argv[0], 0))

    def test_apply_writes_and_signals(self):
        failed = apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run)
        self.assertEqual(failed, [])
        self.assertTrue((self.cfg / "foot/gutter.ini").exists())
        self.assertIn(["pkill", "-USR1", "-x", "foot"], self.calls)
        self.assertIn(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-dark"], self.calls)
        self.assertIn(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", "adw-gtk3-dark"], self.calls)

    def test_light_signals(self):
        apps.apply(DEFAULT, "light", self.cfg, run=self.logging_run)
        self.assertIn(["pkill", "-USR2", "-x", "foot"], self.calls)
        self.assertIn(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", "adw-gtk3"], self.calls)
        self.assertIn(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-light"], self.calls)

    def test_writes_precede_signals_and_order_is_foot_then_gsettings(self):
        def run(argv, **kw):
            self.assertTrue((self.cfg / "gtk-4.0/gtk.css").exists())
            return self.logging_run(argv, **kw)
        apps.apply(DEFAULT, "dark", self.cfg, run=run)
        self.assertEqual([c[0] for c in self.calls], ["pkill", "gsettings", "gsettings"])
        self.assertEqual([c[3] for c in self.calls[1:]], ["gtk-theme", "color-scheme"])

    def test_icon_theme_only_when_installed(self):
        apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run)
        self.assertFalse(any("icon-theme" in c for c in self.calls))
        (self.icons / "Papirus-Dark").mkdir()
        self.calls.clear()
        apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run)
        self.assertEqual(self.calls[-1], ["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", "Papirus-Dark"])
        self.calls.clear()
        apps.apply(DEFAULT, "light", self.cfg, run=self.logging_run)
        self.assertFalse(any("icon-theme" in c for c in self.calls))

    def test_btop_skipped_without_config_dir(self):
        apps.apply(DEFAULT, "light", self.cfg, run=self.logging_run)
        self.assertFalse((self.cfg / "btop").exists())
        self.assertNotIn(["pkill", "-USR2", "-x", "btop"], self.calls)

    def test_deezer_skipped_without_either_config_dir(self):
        self.assertEqual(apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run), [])
        self.assertFalse((self.cfg / "deezer").exists())
        self.assertFalse(self.flatpak.exists())

    def test_deezer_written_into_the_flatpak_config(self):
        self.flatpak.mkdir()
        (self.cfg / "deezer").mkdir()
        self.assertEqual(apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run), [])
        self.assertEqual((self.flatpak / "gutter.css").read_text(), rendered("dark", "deezer", "deezer/gutter.css"))
        self.assertFalse((self.cfg / "deezer/gutter.css").exists())
        self.assertEqual(sorted(p.name for p in self.flatpak.iterdir()), ["gutter.css"])   # no backup of our own file

    def test_deezer_written_into_the_plain_config(self):
        (self.cfg / "deezer").mkdir()
        self.assertEqual(apps.apply(DEFAULT, "light", self.cfg, run=self.logging_run), [])
        self.assertEqual((self.cfg / "deezer/gutter.css").read_text(), rendered("light", "deezer", "deezer/gutter.css"))
        self.assertEqual(self.calls, [c for c in self.calls if c[0] in ("pkill", "gsettings")])   # nothing signalled for it

    def test_deezer_rewrite_follows_the_mode(self):
        self.flatpak.mkdir()
        apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run)
        apps.apply(DEFAULT, "light", self.cfg, run=self.logging_run)
        self.assertIn("--color-bg-main: #fbf6d3;", (self.flatpak / "gutter.css").read_text())

    def test_failed_deezer_write_marks_only_deezer(self):
        self.flatpak.mkdir()
        (self.flatpak / "gutter.css").mkdir()   # a directory where the file goes
        self.assertEqual(apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run), ["deezer"])
        self.assertTrue((self.cfg / "foot/gutter.ini").exists())

    def test_btop_written_and_signalled(self):
        (self.cfg / "btop").mkdir()
        self.assertEqual(apps.apply(DEFAULT, "light", self.cfg, run=self.logging_run), [])
        self.assertTrue((self.cfg / "btop/themes/gutter.theme").exists())
        self.assertEqual((self.cfg / "btop/btop.conf").read_text(), 'color_theme = "gutter"\n')
        self.assertEqual(self.calls[-1], ["pkill", "-USR2", "-x", "btop"])

    def test_btop_conf_that_is_not_utf8_fails_only_btop(self):
        (self.cfg / "btop").mkdir(); (self.cfg / "btop/btop.conf").write_bytes(b'x = "\xff\xfe"\n')
        self.assertEqual(apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run), ["btop"])
        self.assertEqual((self.cfg / "btop/btop.conf").read_bytes(), b'x = "\xff\xfe"\n')
        self.assertFalse((self.cfg / "btop/themes/gutter.theme").exists())
        self.assertIn(["pkill", "-USR1", "-x", "foot"], self.calls)
        self.assertTrue(any(c[0] == "gsettings" for c in self.calls))
        self.assertNotIn(["pkill", "-USR2", "-x", "btop"], self.calls)

    def test_foot_gsettings_and_btop_signals_in_one_apply(self):
        (self.cfg / "btop").mkdir()
        apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run)
        self.assertEqual(self.calls, [
            ["pkill", "-USR1", "-x", "foot"],
            ["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", "adw-gtk3-dark"],
            ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-dark"],
            ["pkill", "-USR2", "-x", "btop"]])

    def test_btop_conf_color_theme_replaced(self):
        (self.cfg / "btop").mkdir(); (self.cfg / "btop/btop.conf").write_text('color_theme = "Default"\nx = 1\n')
        apps.apply(DEFAULT, "light", self.cfg, run=self.logging_run)
        self.assertEqual((self.cfg / "btop/btop.conf").read_text(), 'color_theme = "gutter"\nx = 1\n')

    def test_btop_conf_color_theme_appended(self):
        self.assertEqual(apps.set_color_theme("a = 1"), 'a = 1\ncolor_theme = "gutter"\n')
        self.assertEqual(apps.set_color_theme("a = 1\n#color_theme = \"x\"\n"),
                         'a = 1\n#color_theme = "x"\ncolor_theme = "gutter"\n')
        self.assertEqual(apps.set_color_theme('  color_theme = "TTY"\na = 1\n'), 'color_theme = "gutter"\na = 1\n')

    def test_no_process_to_signal_is_fine(self):
        self.exit_codes["pkill"] = 1
        (self.cfg / "btop").mkdir()
        self.assertEqual(apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run), [])

    def test_pkill_error_fails_that_app(self):
        self.exit_codes["pkill"] = 2
        (self.cfg / "btop").mkdir()
        self.assertEqual(apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run), ["foot", "btop"])

    def test_missing_gsettings_is_fine(self):
        self.missing.add("gsettings")
        self.assertEqual(apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run), [])

    def test_gsettings_error_fails_gtk(self):
        self.exit_codes["gsettings"] = 1
        self.assertEqual(apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run), ["gtk"])

    @unittest.skipIf(os.geteuid() == 0, "root writes through the mode")
    def test_failed_write_marks_only_that_app(self):
        (self.cfg / "gtk-4.0").mkdir()
        (self.cfg / "gtk-4.0").chmod(0o500)
        self.addCleanup((self.cfg / "gtk-4.0").chmod, 0o755)
        failed = apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run)
        self.assertEqual(failed, ["gtk", "thunar"])
        self.assertTrue((self.cfg / "foot/gutter.ini").exists())
        self.assertTrue((self.cfg / "qtengine/config.json").exists())
        self.assertIn(["pkill", "-USR1", "-x", "foot"], self.calls)
        self.assertFalse(any(c[0] == "gsettings" for c in self.calls))

    def test_first_write_backs_up_files_that_are_not_gutters(self):
        (self.cfg / "gtk-4.0").mkdir()
        (self.cfg / "gtk-4.0/gtk.css").write_text("/* old theme */\n")
        (self.cfg / "gtk-4.0/gtk.css").chmod(0o640)
        (self.cfg / "btop").mkdir()
        (self.cfg / "btop/btop.conf").write_text('color_theme = "old"\n')
        apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run)
        self.assertEqual((self.cfg / "gtk-4.0/gtk.css.pre-gutter").read_text(), "/* old theme */\n")
        self.assertEqual(stat.S_IMODE((self.cfg / "gtk-4.0/gtk.css.pre-gutter").stat().st_mode), 0o640)
        self.assertEqual(stat.S_IMODE((self.cfg / "gtk-4.0/gtk.css").stat().st_mode), 0o640)   # the mode is kept
        self.assertEqual((self.cfg / "btop/btop.conf.pre-gutter").read_text(), 'color_theme = "old"\n')
        # Absent before: a marker, so a manual restore deletes the file.
        for rel in ("gtk-3.0/gtk.css", "gtk-3.0/thunar.css", "gtk-4.0/thunar.css", "qtengine/config.json"):
            self.assertEqual((self.cfg / (rel + ".pre-gutter-absent")).read_text(), "", rel)
            self.assertFalse((self.cfg / (rel + ".pre-gutter")).exists(), rel)
        # Gutter's own files get neither.
        self.assertEqual(sorted(str(p.relative_to(self.cfg)) for p in self.cfg.rglob("*.pre-gutter*")), [
            "btop/btop.conf.pre-gutter", "gtk-3.0/gtk.css.pre-gutter-absent", "gtk-3.0/thunar.css.pre-gutter-absent",
            "gtk-4.0/gtk.css.pre-gutter", "gtk-4.0/thunar.css.pre-gutter-absent",
            "qtengine/config.json.pre-gutter-absent"])
        # A later apply keeps the first record.
        apps.apply(DEFAULT, "light", self.cfg, run=self.logging_run)
        self.assertEqual((self.cfg / "gtk-4.0/gtk.css.pre-gutter").read_text(), "/* old theme */\n")
        self.assertFalse((self.cfg / "gtk-3.0/gtk.css.pre-gutter").exists())

    def test_symlinked_btop_conf_is_written_through(self):
        dotfiles = self.cfg.parent / "dotfiles"
        dotfiles.mkdir()
        (dotfiles / "btop.conf").write_text('color_theme = "old"\nx = 1\n')
        (dotfiles / "btop.conf").chmod(0o600)
        (self.cfg / "btop").mkdir()
        link = self.cfg / "btop/btop.conf"
        link.symlink_to(dotfiles / "btop.conf")
        self.assertEqual(apps.apply(DEFAULT, "dark", self.cfg, run=self.logging_run), [])
        self.assertTrue(link.is_symlink())
        self.assertEqual((dotfiles / "btop.conf").read_text(), 'color_theme = "gutter"\nx = 1\n')
        self.assertEqual(stat.S_IMODE((dotfiles / "btop.conf").stat().st_mode), 0o600)
        self.assertEqual((self.cfg / "btop/btop.conf.pre-gutter").read_text(), 'color_theme = "old"\nx = 1\n')
        self.assertEqual([p.name for p in dotfiles.iterdir()], ["btop.conf"])

    def test_malformed_palette_is_a_value_error(self):
        for mutate, text in (
                (lambda p: p.update(version=1), "not version 2"),
                (lambda p: p.pop("dark"), "no dark half"),
                (lambda p: p["light"].pop("ink"), "no colour 'ink'"),
                (lambda p: p["roles"].pop("muted"), "no role 'muted'"),
                (lambda p: p["roles"].update(ok="nope"), "no accent 'nope'"),
                (lambda p: p["dark"]["accents"].pop("pink"), "the dark half has no accent 'pink'"),   # btop's
                (lambda p: p["light"]["accents"].update(navy="navy"), "the light half has no accent 'navy'"),
                (lambda p: p["dark"].pop("accents"), "no accents")):
            pal = json.loads(json.dumps(DEFAULT))
            mutate(pal)
            with self.assertRaisesRegex(ValueError, text):
                apps.apply(pal, "dark", self.cfg, run=self.logging_run)
        self.assertEqual(list(self.cfg.iterdir()), [])
        self.assertEqual(self.calls, [])

    def test_main_uses_xdg_config_home(self):
        # main runs the real subprocess.run, so put stubs for pkill and gsettings in front of the PATH.
        stubs = self.cfg.parent / "stubs"
        stubs.mkdir()
        for name in ("pkill", "gsettings"):
            (stubs / name).write_text("#!/bin/sh\nexit 0\n")
            (stubs / name).chmod(0o755)
        pal = self.cfg.parent / "palette.json"
        pal.write_text(json.dumps(DEFAULT))
        env = dict(os.environ, XDG_CONFIG_HOME=str(self.cfg), HOME=str(self.cfg.parent),
                   PATH="%s:%s" % (stubs, os.environ["PATH"]))
        r = subprocess.run([sys.executable, str(ROOT / "tools/apps.py"), "--palette", str(pal), "--mode", "light"],
                           capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.cfg / "foot/gutter.ini").exists())
        self.assertFalse((self.cfg.parent / ".config").exists())

    def test_main_reports_a_bad_palette_file(self):
        pal = self.cfg.parent / "palette.json"
        pal.write_text("not json")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):  # both fail while reading the palette, before any command runs
            self.assertEqual(apps.main(["--palette", str(pal), "--mode", "dark"]), 1)
            self.assertEqual(apps.main(["--palette", str(self.cfg.parent / "missing.json"), "--mode", "dark"]), 1)
        self.assertEqual(err.getvalue().count("apps: cannot read palette"), 2)
        self.assertIn("missing.json: No such file or directory", err.getvalue())
        self.assertNotIn("[Errno", err.getvalue())


if __name__ == "__main__":
    unittest.main()
