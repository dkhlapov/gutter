import json, re, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT = json.loads((ROOT / "theme/default-palette.json").read_text())


def luminance(hex_):
    def lin(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (int(hex_[i:i + 2], 16) for i in (1, 3, 5))
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast(a, b):
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def blend(fg, bg, t):
    return "#" + "".join(
        "%02x" % round(int(fg[i:i + 2], 16) * t + int(bg[i:i + 2], 16) * (1 - t)) for i in (1, 3, 5))


def muted_mix():
    return float(re.search(r"var MUTED_MIX = ([0-9.]+);", (ROOT / "lib/palette.js").read_text()).group(1))


class MutedTextContrast(unittest.TestCase):
    """The muted text role (Theme.textMuted: the text colour mixed into paper by MUTED_MIX) on the shipped palette."""

    def test_muted_text_clears_aa_on_paper_in_both_modes(self):
        for mode in ("light", "dark"):
            half = DEFAULT[mode]
            ratio = contrast(blend(half["text"], half["paper"], muted_mix()), half["paper"])
            self.assertGreaterEqual(ratio, 4.5, f"{mode}: muted text is {ratio:.2f}:1 on paper")

    def test_theme_last_resort_matches_the_default_palette(self):
        # Theme.qml's lastResort is what serves muted text when default-palette.json cannot be read.
        theme = (ROOT / "theme/Theme.qml").read_text()
        for mode in ("light", "dark"):
            for key in ("text", "paper"):
                self.assertIn(f'{key}: "{DEFAULT[mode][key]}"', theme)


# Decorative marks may stay under the floor: "path: reason".
SMALL_TEXT_ALLOWED = {}


def qml_files():
    for folder in ("bar", "components", "launcher", "lockscreen", "pill", "wallpaper", "settings"):
        yield from sorted((ROOT / folder).rglob("*.qml"))


def blocks(text, head):
    """Yield (line number, body) of every `head {` block in a QML source, its braces matched."""
    for m in re.finditer(r"(?m)^[ \t]*(?:\w+:\s*)?" + head + r"\s*\{", text):
        depth, i = 0, m.end() - 1
        while i < len(text):
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            if depth == 0:
                break
            i += 1
        yield text.count("\n", 0, m.start()) + 1, text[m.end():i]


def own_lines(body):
    """The block's own property lines: those not inside a nested { } block."""
    depth, out = 0, []
    for line in body.splitlines():
        if depth == 0:
            out.append(line)
        depth += line.count("{") - line.count("}")
    return out


class TextSize(unittest.TestCase):
    def test_no_text_is_set_below_the_floor(self):
        floor = int(re.search(r"textMin: (\d+)", (ROOT / "theme/Theme.qml").read_text()).group(1))
        self.assertEqual(floor, 13)
        found = []
        for path in qml_files():
            rel = path.relative_to(ROOT).as_posix()
            if rel in SMALL_TEXT_ALLOWED:
                continue
            for n, line in enumerate(path.read_text().splitlines(), 1):
                m = re.search(r"font\.pixelSize:\s*(.+)", line)
                if m and "Theme.textMin" not in m.group(1) and \
                        any(int(v) < floor for v in re.findall(r"(?<![\w.])\d+(?![\w.])", m.group(1))):
                    found.append(f"{rel}:{n}: {line.strip()}")
        self.assertEqual(found, [], "text under the 13 px floor; use Theme.textMin or drop the size")

    def test_text_is_not_dimmed_with_a_literal_opacity(self):
        found = []
        for path in qml_files():
            text = path.read_text()
            for n, body in blocks(text, "InkText"):
                for line in own_lines(body):
                    m = re.match(r"\s*opacity:\s*(0?\.\d+)\s*$", line)
                    if m:
                        found.append(f"{path.relative_to(ROOT)}:{n}: {line.strip()}")
        self.assertEqual(found, [], "secondary text dims itself with opacity; use color: Theme.textMuted")


# Shared components with a pointer area that name themselves elsewhere: "file: where".
ACCESSIBLE_ELSEWHERE = {
    "components/CaptionBox.qml": "its tabs are LabelTabs, which carry the role and the name",
    "components/InkScrollBar.qml": "a scroll bar is no control a screen reader needs: the scrolled view is",
    "components/InkMenu.qml": "a frame for InkMenuList, whose entries carry the role and the name",
}


class AccessibleMetadata(unittest.TestCase):
    def test_every_shared_interactive_component_has_a_role_and_a_name(self):
        missing = []
        for path in sorted((ROOT / "components").glob("*.qml")):
            rel = path.relative_to(ROOT).as_posix()
            text = path.read_text()
            if "MouseArea" not in text or rel in ACCESSIBLE_ELSEWHERE:
                continue
            for what in ("Accessible.role", "Accessible.name"):
                if what not in text:
                    missing.append(f"{rel}: no {what}")
        self.assertEqual(missing, [])

    def test_every_use_of_an_unnamed_control_names_it(self):
        """A slider, a seek bar or an icon-only button has no text of its own to be named by."""
        found = []
        for path in qml_files():
            rel = path.relative_to(ROOT).as_posix()
            text = path.read_text()
            for head, needs in (("InkSlider", lambda b: True), ("SeekBar", lambda b: True),
                                ("InkButton", lambda b: re.search(r"^\s*icon:", b, re.M) and not re.search(r"^\s*text:", b, re.M))):
                for n, body in blocks(text, head):
                    props = "\n".join(own_lines(body))
                    if needs(props) and "accessibleName" not in props:
                        found.append(f"{rel}:{n}: {head} has no accessibleName")
        self.assertEqual(found, [])

    def test_every_bar_cell_has_a_name(self):
        found = []
        for path in sorted((ROOT / "bar").glob("*.qml")):
            text = path.read_text()
            for n, body in blocks(text, "Segment"):
                props = "\n".join(own_lines(body))
                if not re.search(r"^\s*accessibleName:", props, re.M):
                    found.append(f"{path.relative_to(ROOT)}:{n}: Segment has no accessibleName")
        self.assertEqual(found, [])


if __name__ == "__main__":
    unittest.main()
