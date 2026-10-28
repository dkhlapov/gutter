import json, os, shutil, subprocess, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAPPED = ROOT / "scripts/mapped.sh"
INK = ROOT / "scripts/ink-lines.sh"

# The fake hyprctl answers from HYPRCTL_<WORD> files, or fails when HYPRCTL_FAIL names the word.
HYPRCTL = """#!/bin/sh
[ "$HYPRCTL_FAIL" = "$1" ] && exit 1
case "$1" in
    workspaces) cat "$HYPRCTL_WORKSPACES" ;;
    monitors) cat "$HYPRCTL_MONITORS" ;;
    layers) cat "$HYPRCTL_LAYERS" ;;
    *) exit 2 ;;
esac
"""


needs_jq = unittest.skipUnless(shutil.which("jq"), "jq is not installed")


class Mapped(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.stubs = self.dir / "stubs"
        self.stubs.mkdir()
        self.stub("hyprctl", HYPRCTL)
        self.env = {**os.environ, "PATH": f"{self.stubs}:{os.environ['PATH']}", "HYPRCTL_FAIL": ""}
        for word in ("workspaces", "monitors", "layers"):
            self.env[f"HYPRCTL_{word.upper()}"] = str(self.dir / word)

    def stub(self, name, body):
        path = self.stubs / name
        path.write_text(body)
        path.chmod(0o755)

    def hypr(self, fullscreen=False, layers=None):
        (self.dir / "workspaces").write_text(json.dumps([{"id": 1, "hasfullscreen": fullscreen}]))
        (self.dir / "monitors").write_text(
            json.dumps([{"name": "DP-1", "activeWorkspace": {"id": 1}, "specialWorkspace": {"id": 0}}])
        )
        levels = {"0": [{"namespace": "gutter"}]} if layers else {}
        (self.dir / "layers").write_text(json.dumps({"DP-1": {"levels": levels}}))

    def run_mapped(self):
        # One second of polling: enough for the absent-layer case to fail without slowing the suite.
        return subprocess.run([MAPPED, "1"], env=self.env, capture_output=True, text=True)

    def test_hyprctl_workspaces_failing_fails(self):
        self.hypr()
        self.env["HYPRCTL_FAIL"] = "workspaces"
        r = self.run_mapped()
        self.assertEqual(r.returncode, 1)
        self.assertIn("mapped: FAIL: hyprctl workspaces failed", r.stderr)
        self.assertNotIn("skipped", r.stdout)

    def test_hyprctl_monitors_failing_fails(self):
        self.hypr()
        self.env["HYPRCTL_FAIL"] = "monitors"
        r = self.run_mapped()
        self.assertEqual(r.returncode, 1)
        self.assertIn("mapped: FAIL: hyprctl monitors failed", r.stderr)
        self.assertNotIn("skipped", r.stdout)

    def test_jq_failing_fails(self):
        self.hypr()
        self.stub("jq", "#!/bin/sh\nexit 1\n")
        r = self.run_mapped()
        self.assertEqual(r.returncode, 1)
        self.assertIn("mapped: FAIL: jq failed", r.stderr)
        self.assertNotIn("skipped", r.stdout)

    @needs_jq
    def test_empty_monitor_list_fails(self):
        self.hypr()
        (self.dir / "monitors").write_text("[]")
        r = self.run_mapped()
        self.assertEqual(r.returncode, 1)
        self.assertIn("mapped: FAIL: hyprctl reports no monitors", r.stderr)
        self.assertNotIn("skipped", r.stdout)

    @needs_jq
    def test_monitor_list_that_is_not_one_json_value_fails(self):
        self.hypr()
        for text in ("", "[] []", "{}"):
            with self.subTest(text=text):
                (self.dir / "monitors").write_text(text)
                r = self.run_mapped()
                self.assertEqual(r.returncode, 1)
                self.assertIn("mapped: FAIL: jq failed", r.stderr)
                self.assertNotIn("integer", r.stderr)

    @needs_jq
    def test_every_monitor_fullscreen_skips(self):
        self.hypr(fullscreen=True)
        r = self.run_mapped()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("mapped: skipped (every monitor shows a fullscreen window)", r.stdout)

    @needs_jq
    def test_layer_present_passes(self):
        self.hypr(layers=True)
        r = self.run_mapped()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("mapped: OK (DP-1)", r.stdout)

    @needs_jq
    def test_layer_absent_fails(self):
        self.hypr(layers=False)
        r = self.run_mapped()
        self.assertEqual(r.returncode, 1)
        self.assertIn("mapped: FAIL: no gutter layer on DP-1", r.stderr)

    @needs_jq
    def test_hyprctl_layers_failing_fails_and_says_so(self):
        self.hypr(layers=True)
        self.env["HYPRCTL_FAIL"] = "layers"
        r = self.run_mapped()
        self.assertEqual(r.returncode, 1)
        self.assertIn("mapped: FAIL: no gutter layer on DP-1 (hyprctl layers failed)", r.stderr)


RECT = "Rectangle {\n    color: Theme.ink\n}\n"


class InkLines(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "scripts").mkdir()
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def tree(self, qml, entries, name="A.qml"):
        (self.root / name).write_bytes(qml.encode())
        (self.root / "scripts/ink-lines.txt").write_text(
            "# a comment\n\n" + "".join(e + "\n" for e in entries), encoding="utf-8"
        )

    def run_ink(self, root=None, cwd=None, env=None):
        return subprocess.run([INK, root or str(self.root)], capture_output=True, text=True, cwd=cwd, env=env)

    def test_listed_line_passes(self):
        self.tree(RECT, ["A.qml: Rectangle { > color: Theme.ink"])
        r = self.run_ink()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_unlisted_line_fails_with_its_place(self):
        self.tree(RECT, [])
        r = self.run_ink()
        self.assertEqual(r.returncode, 1)
        self.assertIn("Theme.ink used for text at A.qml:2", r.stderr)

    def test_same_line_in_another_object_fails(self):
        # The text comes first, so an entry matched on the line alone would be spent on it.
        self.tree("Text {\n    color: Theme.ink\n}\n" + RECT, ["A.qml: Rectangle { > color: Theme.ink"])
        r = self.run_ink()
        self.assertEqual(r.returncode, 1)
        self.assertIn("Theme.ink used for text at A.qml:2", r.stderr)
        self.assertNotIn("A.qml:5", r.stderr)

    def test_nested_object_keys_on_the_nearest_one(self):
        self.tree(
            "Rectangle {\n    Text {\n        color: Theme.ink\n    }\n}\n",
            ["A.qml: Rectangle { > color: Theme.ink"],
        )
        r = self.run_ink()
        self.assertEqual(r.returncode, 1)
        self.assertIn("Theme.ink used for text at A.qml:3", r.stderr)

    def test_stale_entry_fails_and_is_named(self):
        self.tree(RECT, ["A.qml: Rectangle { > color: Theme.ink", "A.qml: Rectangle { > border.color: Theme.ink",
                         "Gone.qml: Rectangle { > color: Theme.ink"])
        r = self.run_ink()
        self.assertEqual(r.returncode, 1)
        self.assertIn("stale entry", r.stderr)
        self.assertIn("A.qml: Rectangle { > border.color: Theme.ink", r.stderr)
        self.assertIn("Gone.qml: Rectangle { > color: Theme.ink", r.stderr)

    def test_a_duplicate_pair_needs_two_entries(self):
        self.tree(RECT + RECT, ["A.qml: Rectangle { > color: Theme.ink"])
        r = self.run_ink()
        self.assertEqual(r.returncode, 1)
        self.assertIn("Theme.ink used for text at A.qml:5", r.stderr)
        self.tree(RECT + RECT, ["A.qml: Rectangle { > color: Theme.ink"] * 2)
        self.assertEqual(self.run_ink().returncode, 0)

    def test_a_surplus_entry_is_called_surplus_not_stale(self):
        self.tree(RECT, ["A.qml: Rectangle { > color: Theme.ink"] * 3)
        r = self.run_ink()
        self.assertEqual(r.returncode, 1)
        self.assertIn("lists this line 2 time(s) too many: A.qml: Rectangle { > color: Theme.ink", r.stderr)
        self.assertNotIn("no such line", r.stderr)

    def test_an_edit_elsewhere_keeps_the_entry_valid(self):
        self.tree("// moved down\n\n" + RECT, ["A.qml: Rectangle { > color: Theme.ink"])
        self.assertEqual(self.run_ink().returncode, 0)

    def test_text_colour_property_is_caught(self):
        self.tree("Text {\n    textColor: Theme.ink\n}\n", [])
        r = self.run_ink()
        self.assertEqual(r.returncode, 1)
        self.assertIn("Theme.ink used for text at A.qml:2", r.stderr)

    def test_a_trailing_comment_on_the_header_is_ignored(self):
        self.tree("Rectangle { // plate\n    color: Theme.ink\n}\n", ["A.qml: Rectangle { > color: Theme.ink"])
        r = self.run_ink()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_a_header_with_an_id_is_the_header(self):
        self.tree(
            "Rectangle { id: plate\n    color: Theme.ink\n}\n",
            ["A.qml: Rectangle { id: plate > color: Theme.ink"],
        )
        r = self.run_ink()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_a_property_before_the_type_still_makes_a_header(self):
        self.tree(
            "ListView {\n    delegate: Rectangle { id: row\n        color: Theme.ink\n    }\n}\n",
            ["A.qml: delegate: Rectangle { id: row > color: Theme.ink"],
        )
        r = self.run_ink()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_crlf_lines_key_on_their_header(self):
        self.tree(RECT.replace("\n", "\r\n"), ["A.qml: Rectangle { > color: Theme.ink"])
        r = self.run_ink()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_a_relative_root(self):
        self.tree(RECT, ["A.qml: Rectangle { > color: Theme.ink"])
        r = self.run_ink(root=self.root.name, cwd=self.root.parent)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_a_root_that_is_not_a_git_tree_fails(self):
        self.tree("Text {\n    color: Theme.ink\n}\n", [])
        shutil.rmtree(self.root / ".git")
        # Without the ceiling git would walk up from the temp dir to whatever repository encloses it.
        r = self.run_ink(env={**os.environ, "GIT_CEILING_DIRECTORIES": str(self.root.parent)})
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("Theme.ink used", r.stderr)  # failed on git, did not read an empty file list

    def test_a_tracked_file_deleted_from_the_worktree_is_skipped(self):
        self.tree(RECT, [])
        subprocess.run(["git", "-C", str(self.root), "add", "A.qml"], check=True)
        (self.root / "A.qml").unlink()
        r = self.run_ink()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_a_file_name_with_an_equals_sign_is_scanned(self):
        self.tree("Text {\n    color: Theme.ink\n}\n", [], name="x=y.qml")
        r = self.run_ink()
        self.assertEqual(r.returncode, 1)
        self.assertIn("Theme.ink used for text at x=y.qml:2", r.stderr)

    def test_a_non_ascii_file_name_matches_its_entry(self):
        self.tree(RECT, ["\u00e9.qml: Rectangle { > color: Theme.ink"], name="\u00e9.qml")
        r = self.run_ink()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_the_real_tree_passes(self):
        r = subprocess.run([INK, str(ROOT)], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)


if __name__ == "__main__":
    unittest.main()
