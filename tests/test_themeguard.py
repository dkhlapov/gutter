import re, unittest
from pathlib import Path

SRC = (Path(__file__).resolve().parents[1] / "services/ThemeMode.qml").read_text()


def function_body(name):
    """The text of `function name(...)` in ThemeMode.qml, up to the next function."""
    m = re.search(r"^    function %s\(.*?(?=^    function |\Z)" % re.escape(name), SRC, re.S | re.M)
    assert m, name
    return m.group(0)


class ThemeGuardTest(unittest.TestCase):
    """The smoke/gallery instance (`inert`) shares the real HOME and must never apply a theme, run `gutter hypr`
    or write theme-auto.json. ThemeMode.qml is a singleton and cannot be loaded in a unit test, so this checks the
    source: every start sits in one function, behind the guard, and nowhere else."""

    def test_apply_starts_only_in_evaluate_behind_mayStart(self):
        self.assertEqual(len(re.findall(r"applier\.run\(", SRC)), 1)
        body = function_body("evaluate")
        self.assertLess(body.index("ThemeModeLib.mayStart(inert, applier.running, hyprRunner.running)"), body.index("applier.run("))

    def test_hypr_starts_only_in_refreshHypr_behind_mayStart(self):
        self.assertEqual(len(re.findall(r"hyprRunner\.run\(", SRC)), 1)
        body = function_body("refreshHypr")
        self.assertLess(body.index("ThemeModeLib.mayStart(inert, applier.running, hyprRunner.running)"), body.index("hyprRunner.run("))

    def test_state_file_is_written_only_behind_inert(self):
        self.assertEqual(len(re.findall(r"mkdir\.running = true", SRC)), 1)
        self.assertEqual(len(re.findall(r"autoState\.setText\(", SRC)), 1)
        body = function_body("save")
        self.assertLess(body.index("if (inert"), body.index("mkdir.running = true"))

    def test_inert_covers_smoke_and_gallery(self):
        self.assertRegex(SRC, r"readonly property bool inert: smoke \|\| gallery")
        self.assertIn('Quickshell.env("GUTTER_SMOKE") === "1"', SRC)
        self.assertIn('Quickshell.env("GUTTER_GALLERY") === "1"', SRC)

    def test_detached_commands_are_only_notifications(self):
        # The tool is started by the two runners alone; the one thing run outside them is notify-send. A message can
        # start with a dash (hyprctl's stderr), so `--` ends the options before it, as in tools/gutter.
        calls = re.findall(r"\bexecDetached\((.*)\)", SRC)
        self.assertTrue(calls)
        for call in calls:
            self.assertIn('"notify-send"', call)
            self.assertIn('"--", "Gutter", message]', call)


if __name__ == "__main__":
    unittest.main()
