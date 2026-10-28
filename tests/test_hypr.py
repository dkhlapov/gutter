import contextlib, io, json, os, subprocess, sys, tempfile, unittest
from unittest import mock
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import hypr

P = json.loads((ROOT / "theme/default-palette.json").read_text())

def broken(edit):
    """A copy of the default palette with `edit` applied."""
    q = json.loads(json.dumps(P)); edit(q)
    return q

class Hypr(unittest.TestCase):
    def setUp(self):
        self.lua = hypr.render(P)
        # Never the real ~/.config/gutter/config.json: an empty config home, so the default shadow.
        home = tempfile.TemporaryDirectory()
        self.addCleanup(home.cleanup)
        env = mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": home.name})
        env.start()
        self.addCleanup(env.stop)

    def test_shape(self):
        self.assertRegex(self.lua, r"rounding\s*=\s*0\b")
        self.assertRegex(self.lua, r"border_size\s*=\s*3\b")

    def test_border_colours(self):
        self.assertIn('active_border = "rgb(22a5a6)"', self.lua)
        self.assertIn('inactive_border = "rgb(0e0d0e)"', self.lua)

    def test_shadow(self):
        self.assertIn('offset = "6 6"', self.lua)
        self.assertIn('color = "rgba(22a5a6ff)"', self.lua)
        self.assertRegex(self.lua, r"sharp\s*=\s*true")

    def test_shadow_ink(self):
        self.assertIn('color = "rgba(0e0d0eff)"', hypr.render(P, "light", "ink"))
        self.assertIn('color = "rgba(%sff)"' % P["dark"]["ink"].lstrip("#"), hypr.render(P, "dark", "ink"))

    def test_shadow_accent(self):
        self.assertIn('color = "rgba(e2492fff)"', hypr.render(P, "light", "coral"))

    def test_shadow_role(self):
        dark = P["dark"]["accents"][P["roles"]["focusBorder"]].lstrip("#")
        self.assertIn('color = "rgba(%sff)"' % dark, hypr.render(P, "dark", "focusBorder"))
        q = json.loads(json.dumps(P)); q["roles"]["urgent"] = "pink"
        self.assertIn('color = "rgba(%sff)"' % P["light"]["accents"]["pink"].lstrip("#"), hypr.render(q, "light", "urgent"))

    def config(self, d, text):
        path = Path(d) / "config.json"
        path.write_text(text)
        return path

    def test_shadow_name(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(hypr.shadow_name(self.config(d, '{"shadow": {"color": "pink"}}')), "pink")
            self.assertEqual(hypr.shadow_name(self.config(d, '{"shadow": {"color": "ink", "offset": 5}}')), "ink")

    def test_missing_config_is_teal(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(hypr.shadow_name(Path(d) / "none.json"), "teal")
            self.assertEqual(hypr.shadow_name(self.config(d, '{"hoverDelay": 300}')), "teal")

    def test_invalid_json_is_teal(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(hypr.shadow_name(self.config(d, '{"shadow": ')), "teal")

    def test_unknown_name_is_teal(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(hypr.shadow_name(self.config(d, '{"shadow": {"color": "chartreuse"}}')), "teal")
            self.assertEqual(hypr.shadow_name(self.config(d, '{"shadow": {"color": 3}}')), "teal")

    def test_shadow_not_an_object_is_teal(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(hypr.shadow_name(self.config(d, '{"shadow": "pink"}')), "teal")
            self.assertEqual(hypr.shadow_name(self.config(d, '[1, 2]')), "teal")

    def test_cli_config_flag(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "out.lua"
            cfg = self.config(d, '{"shadow": {"color": "ink"}}')
            self.assertEqual(hypr.main(["--palette", str(ROOT / "theme/default-palette.json"), "--out", str(out),
                                        "--config", str(cfg)]), 0)
            self.assertEqual(out.read_text(), hypr.render(P, "light", "ink"))

    def test_default_out_is_in_the_state_folder(self):
        with tempfile.TemporaryDirectory() as d, mock.patch.dict(os.environ, {"XDG_STATE_HOME": d}):
            self.assertEqual(hypr.default_out(), Path(d) / "gutter" / "hypr-gutter.lua")
        env = {k: v for k, v in os.environ.items() if k != "XDG_STATE_HOME"}
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(hypr.default_out(), Path(os.path.expanduser("~/.local/state/gutter/hypr-gutter.lua")))

    def test_blur_off_and_no_gaps(self):
        self.assertRegex(self.lua, r"blur\s*=\s*\{[^}]*enabled\s*=\s*false")
        self.assertNotRegex(self.lua, r"gaps_(in|out)")

    def test_window_rules_override_opacity_and_rounding(self):
        self.assertRegex(self.lua, r'hl\.window_rule\(\{[^)]*opacity\s*=\s*"1\.0 override"')
        self.assertRegex(self.lua, r"hl\.window_rule\(\{[^)]*rounding\s*=\s*0")

    def test_window_animation_children_use_gutter_bezier(self):
        for leaf in ("windowsIn", "windowsOut", "windowsMove"):
            self.assertRegex(self.lua, r'hl\.animation\(\{[^}]*leaf\s*=\s*"%s"[^}]*bezier\s*=\s*"gutterOut"' % leaf)

    def test_group_colours(self):
        # Group borders follow the window borders; the groupbar is the focus accent (active) and the muted accent.
        for key in ("border_active", "border_locked_active"):
            self.assertIn('%s = "rgb(22a5a6)"' % key, self.lua)
        for key in ("border_inactive", "border_locked_inactive"):
            self.assertIn('%s = "rgb(0e0d0e)"' % key, self.lua)
        self.assertIn('text_color = "rgb(0e0d0e)"', self.lua)
        for key in ("active", "locked_active"):
            self.assertRegex(self.lua, r'\b%s = "rgb\(22a5a6\)"' % key)
        for key in ("inactive", "locked_inactive"):
            self.assertRegex(self.lua, r'\b%s = "rgb\(5780a3\)"' % key)
        dark = hypr.render(P, "dark")
        self.assertIn('border_active = "rgb(%s)"' % P["dark"]["accents"]["teal"].lstrip("#"), dark)
        self.assertIn('text_color = "rgb(%s)"' % P["dark"]["ink"].lstrip("#"), dark)

    def test_follows_palette(self):
        q = json.loads(json.dumps(P)); q["light"]["accents"]["teal"] = "#123456"
        self.assertIn('active_border = "rgb(123456)"', hypr.render(q))

    def test_mode_picks_half(self):
        dark = hypr.render(P, "dark"); light = hypr.render(P, "light")
        self.assertIn(P["dark"]["accents"][P["roles"]["focusBorder"]].lstrip("#"), dark)
        self.assertIn(P["light"]["accents"][P["roles"]["focusBorder"]].lstrip("#"), light)
        self.assertIn('inactive_border = "rgb(%s)"' % P["dark"]["ink"].lstrip("#"), dark)
        self.assertIn('color = "rgba(%sff)"' % P["dark"]["accents"]["teal"].lstrip("#"), dark)

    def test_cli_mode_flag_and_default(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "out.lua"
            self.assertEqual(hypr.main(["--palette", str(ROOT / "theme/default-palette.json"), "--out", str(out)]), 0)
            self.assertEqual(out.read_text(), hypr.render(P, "light"))
            self.assertEqual(hypr.main(["--palette", str(ROOT / "theme/default-palette.json"), "--out", str(out),
                                        "--mode", "dark"]), 0)
            self.assertEqual(out.read_text(), hypr.render(P, "dark"))
            with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
                hypr.main(["--mode", "dusk", "--out", str(out)])

    def test_version_1_palette_is_upgraded_in_memory(self):
        v1 = {"version": 1, "source": "", "ink": "#0e0d0e", "paper": "#fbf6d3",
              "accents": dict(P["light"]["accents"]), "roles": dict(P["roles"])}
        with tempfile.TemporaryDirectory() as d:
            src, out = Path(d) / "palette.json", Path(d) / "out.lua"
            src.write_text(json.dumps(v1))
            before = src.read_text()
            self.assertEqual(hypr.main(["--palette", str(src), "--out", str(out), "--mode", "light"]), 0)
            self.assertIn('active_border = "rgb(22a5a6)"', out.read_text())
            self.assertEqual(hypr.main(["--palette", str(src), "--out", str(out), "--mode", "dark"]), 0)
            dark = hypr.load(src)["dark"]
            self.assertNotEqual(dark["ink"], "#0e0d0e")
            self.assertIn('inactive_border = "rgb(%s)"' % dark["ink"].lstrip("#"), out.read_text())
            self.assertEqual(src.read_text(), before)

    def test_check_names_what_is_wrong(self):
        cases = {
            "missing key .light.": broken(lambda q: q.pop("light")),
            "missing key .roles.": broken(lambda q: q.pop("roles")),
            "missing key .teal.": broken(lambda q: q["light"]["accents"].pop("teal")),
            "light.ink is not #RRGGBB": broken(lambda q: q["light"].update(ink="abc")),
            "light.accents.teal is not #RRGGBB: .red.": broken(lambda q: q["light"]["accents"].update(teal="red")),
            "light.accents.navy is not #RRGGBB": broken(lambda q: q["light"]["accents"].update(navy="#12345")),
            "light.accents.teal is not #RRGGBB: None": broken(lambda q: q["light"]["accents"].update(teal=None)),
            "missing key .chartreuse.": broken(lambda q: q["roles"].update(focusBorder="chartreuse")),
            "not a palette": [],
        }
        for want, q in cases.items():
            with self.subTest(want=want), self.assertRaisesRegex(ValueError, want):
                hypr.check(q, "light")
        hypr.check(P, "light"); hypr.check(P, "dark")
        hypr.check(broken(lambda q: q["light"]["accents"].update(sun="red")), "light")      # sun is not used...
        with self.assertRaisesRegex(ValueError, "light shadow colour sun is not #RRGGBB"):  # ...unless it is the shadow
            hypr.check(broken(lambda q: q["light"]["accents"].update(sun="red")), "light", "sun")
        with self.assertRaisesRegex(ValueError, "dark.ink is not"):
            hypr.check(broken(lambda q: q["dark"].update(ink="#fff")), "dark")
        hypr.check(broken(lambda q: q["dark"].update(ink="#fff")), "light")    # the other half is not looked at

    def run_cli(self, palette, out, *args):
        return subprocess.run([sys.executable, str(ROOT / "tools/hypr.py"), "--palette", str(palette),
                               "--out", str(out), "--config", str(Path(out).parent / "none.json"), *args],
                              capture_output=True, text=True)

    def test_cli_success_writes_the_file(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "out.lua"
            r = self.run_cli(ROOT / "theme/default-palette.json", out)
            self.assertEqual((r.returncode, r.stderr, out.read_text()), (0, "", hypr.render(P)))

    def test_cli_bad_palette_exits_1_and_leaves_the_target(self):
        def broken_json(edit):
            return json.dumps(broken(edit))
        def v1(**accents):
            return json.dumps({"version": 1, "source": "", "ink": "#0e0d0e", "paper": "#fbf6d3",
                               "accents": dict(P["light"]["accents"], **accents), "roles": P["roles"]})
        palettes = {
            "invalid json": "{",
            "no version": "{}",
            "not an object": "[1]",
            "missing light half": broken_json(lambda q: q.pop("light")),
            "missing accent": broken_json(lambda q: q["light"]["accents"].pop("teal")),
            "3-digit colour": broken_json(lambda q: q["light"]["accents"].update(teal="#abc")),
            "named colour": broken_json(lambda q: q["light"].update(ink="black")),
            "role naming no accent": broken_json(lambda q: q["roles"].update(focusBorder="chartreuse")),
            "version 1 missing keys": '{"version": 1}',
            "version 1 bad colour": v1(teal="#zz0000"),
            "version 1 colour not a string": v1(teal=5),
            "version 1 colour without the hash": v1(teal="x22a5a6"),
            "version 3": broken_json(lambda q: q.update(version=3)),
            "version null": broken_json(lambda q: q.update(version=None)),
            "version true": broken_json(lambda q: q.update(version=True)),
            "version 1.0": broken_json(lambda q: q.update(version=1.0)),
            "version 2.0": broken_json(lambda q: q.update(version=2.0)),
            "version string": broken_json(lambda q: q.update(version="2")),
        }
        with tempfile.TemporaryDirectory() as d:
            out, src = Path(d) / "out.lua", Path(d) / "palette.json"
            for name, text in palettes.items():
                with self.subTest(name):
                    out.write_text("CURRENT")
                    src.write_text(text)
                    r = self.run_cli(src, out)
                    self.assertEqual(r.returncode, 1, r.stderr)
                    self.assertNotIn("Traceback", r.stderr)
                    self.assertEqual(len(r.stderr.strip().splitlines()), 1, r.stderr)
                    self.assertTrue(r.stderr.startswith("hypr: cannot use palette %s: " % src), r.stderr)
                    self.assertEqual(out.read_text(), "CURRENT")
                    self.assertNotRegex(r.stderr, r"Error\(")     # no exception repr
            with self.subTest("unknown versions are named"):
                for version, want in ((3, "unknown palette version 3"), (None, "unknown palette version None"),
                                      (True, "unknown palette version True"), (2.0, "unknown palette version 2.0")):
                    src.write_text(broken_json(lambda q: q.update(version=version)))
                    self.assertIn(want, self.run_cli(src, out).stderr)
            with self.subTest("missing key reads the same for a version 1 palette"):
                src.write_text(json.dumps({"version": 1}))
                self.assertIn("cannot upgrade version 1: missing key 'ink'", self.run_cli(src, out).stderr)
            with self.subTest("missing file"):
                r = self.run_cli(Path(d) / "none.json", out)
                self.assertEqual(r.returncode, 1)
                self.assertTrue(r.stderr.startswith("hypr: cannot read palette"), r.stderr)
                self.assertEqual(r.stderr.count(str(Path(d) / "none.json")), 1, r.stderr)    # the path once
                self.assertEqual(out.read_text(), "CURRENT")
            with self.subTest("dark half checked for --mode dark only"):
                src.write_text(broken_json(lambda q: q["dark"].update(ink="x")))
                self.assertEqual(self.run_cli(src, out).returncode, 0)
                self.assertEqual(self.run_cli(src, out, "--mode", "dark").returncode, 1)

if __name__ == "__main__":
    unittest.main()
