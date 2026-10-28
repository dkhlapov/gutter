import os, re, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Views that ask for icons by literal name, found by scanning the source so a new name cannot slip past a
# hand-kept list. Names that come out of a lib (WeatherLib.icon, KeysLib.icon, ...) are walked in tst_glyphs.qml.
CALL = "Glyphs.glyph("
STRING = re.compile(r'"([^"\\]*)"')
COMPARED = re.compile(r'[=!]==\s*"[^"]*"')    # `kind === "timerDone"` compares, it does not name an icon
LIB_CALL = re.compile(r'\b(\w+)\.icon\(')
LIB_IMPORT = re.compile(r'^import\s+"[^"]*\blib/(\w+)\.js"\s+as\s+(\w+)', re.M)


def lib_aliases(text):
    """{alias: lib file name without .js} for the lib/<file>.js imports of one QML text."""
    return {alias: lib for lib, alias in LIB_IMPORT.findall(text)}


def walked_libs(text):
    """The lib files whose icon() the QML text calls, through whatever alias it imports them as (tst_glyphs.qml:
    a name from any other lib would go unchecked). Comments are dropped: a mention is not a call."""
    text = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
    return {lib for alias, lib in lib_aliases(text).items() if re.search(rf"\b{alias}\.icon\(", text)}


WALKED_LIBS = walked_libs((ROOT / "tests/tst_glyphs.qml").read_text())
GLYPHS_IMPORT = re.compile(r'^import\s+"[^"]*glyphs\.js"(?:\s+as\s+(\w+))?', re.M)

# The activity views and the notification history: Material Design Icons, each a plane-15 glyph.
PLANE15 = ["pill/activities/*.qml", "pill/sections/NotificationsSection.qml", "pill/sections/notifications/*.qml"]


def qml_files():
    """Every QML file of the shell: all but those under tests/ and under dot-directories (.claude worktrees)."""
    for top, dirs, files in os.walk(ROOT):
        rel = Path(top).relative_to(ROOT)
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and not (rel == Path(".") and d == "tests"))
        for f in sorted(files):
            if f.endswith(".qml"):
                yield Path(top) / f


def table():
    """The code point of every row in lib/glyphs.js TABLE."""
    text = (ROOT / "lib/glyphs.js").read_text()
    start = text.index("var TABLE")
    body = text[start:text.index("};", start)]
    rows = re.findall(r'^\s+(\w+): "\\u\{?([0-9a-f]+)\}?"', body, re.M)
    if len(rows) != len(re.findall(r'^\s+\w+:', body, re.M)):
        raise AssertionError("a row of the glyph table is not read")
    return {name: int(code, 16) for name, code in rows}


def scan(text):
    """(names, problems) of one QML text: the icon names written as double-quoted literals inside its
    Glyphs.glyph(...) calls, and what the scan cannot read. Limit: an argument that mixes a literal with a
    variable (`ok ? "check" : root.iconName`) passes, the variable branch going unchecked."""
    names, problems = [], []
    aliases = lib_aliases(text)
    for m in GLYPHS_IMPORT.finditer(text):
        if m.group(1) != "Glyphs":
            problems.append(f"glyphs.js is imported as {m.group(1)}, the scan reads `as Glyphs`" if m.group(1)
                            else "glyphs.js is imported without `as Glyphs`")
    at = text.find(CALL)
    while at != -1:
        start = at + len(CALL)
        depth, end = 1, start
        while depth and end < len(text):
            depth += {"(": 1, ")": -1}.get(text[end], 0)
            end += 1
        arg = COMPARED.sub("", text[start:end - 1])
        found = STRING.findall(arg)
        if "'" in arg or "`" in arg:
            problems.append(f"icon names are written in double quotes: {arg.strip()}")
        elif [a for a in LIB_CALL.findall(arg) if aliases.get(a) not in WALKED_LIBS]:
            problems.append(f"an icon() call of a lib tst_glyphs.qml does not walk: {arg.strip()}")
        elif not found and not LIB_CALL.search(arg):
            problems.append(f"neither a name literal nor an icon() call of a lib tst_glyphs.qml walks: {arg.strip()}")
        names += found
        at = text.find(CALL, end)
    return names, problems


def used(files):
    """({name: [file, ...]}, [problem, ...]) for the literal names the given QML files ask for."""
    found, problems = {}, []
    for path in files:
        names, bad = scan(path.read_text())
        problems += [f"{path.relative_to(ROOT)}: {p}" for p in bad]
        for name in names:
            found.setdefault(name, []).append(path.name)
    return found, problems


def globbed(patterns):
    """The files matching the globs, which are taken from the repository root."""
    return [p for pattern in patterns for p in sorted(ROOT.glob(pattern))]


class GlyphUsage(unittest.TestCase):
    def test_everyNamedGlyphIsInTheTable(self):
        names = table()
        found, problems = used(qml_files())
        if problems:
            self.fail("\n".join(problems))
        self.assertGreaterEqual(len(found), 10, found)    # a sanity floor: the scan found the views at all
        for name, files in found.items():
            self.assertTrue(name in names, f"{name} (in {', '.join(files)}) has no row in lib/glyphs.js")

    def test_activityGlyphsAreMaterialDesignIcons(self):
        names = table()
        found, problems = used(globbed(PLANE15))
        if problems:
            self.fail("\n".join(problems))
        self.assertGreaterEqual(len(found), 10, found)    # a sanity floor
        for name in found:
            self.assertTrue(name in names, f"{name} has no row in lib/glyphs.js")
            self.assertTrue(0xF0000 <= names[name] <= 0xFFFFD, f"{name} is not in plane 15")

    # Plane 15 holds the activities, the keys HUD and the muted speaker: two names with one glyph would be
    # told apart by nothing on screen.
    def test_plane15GlyphsAreDistinct(self):
        seen = {}
        for name, code in table().items():
            if code >= 0xF0000:
                self.assertFalse(code in seen, f"{name} shares its glyph with {seen.get(code)}")
                seen[code] = name
        self.assertGreaterEqual(len(seen), 10, seen)    # a sanity floor

    def test_walkedLibsAreTheOnesTstGlyphsCalls(self):
        self.assertEqual(WALKED_LIBS, {"weather", "shelf", "volume", "keys"})

    def test_aCommentIsNotAWalk(self):
        imp = 'import "../lib/keys.js" as K\n'
        self.assertEqual(walked_libs(imp + "x = K.icon(a)"), {"keys"})
        self.assertEqual(walked_libs(imp + "// K.icon(a)"), set())
        self.assertEqual(walked_libs(imp + "/* K.icon(a)\n   K.icon(b) */"), set())

    def test_scanSeesTheIconsOfAKnownView(self):
        # The timer face's ternary names four icons and compares against two kinds.
        found, problems = used([ROOT / "pill/activities/TimerPill.qml"])
        self.assertEqual(sorted(found), ["alarm", "timer", "timer_pause", "timer_play"])
        if problems:
            self.fail("\n".join(problems))

    def test_scanRefusesWhatItCannotRead(self):
        libs = "".join(f'import "../lib/{f}.js" as {a}\n' for f, a in [
            ("volume", "VolumeLib"), ("keys", "KeysLib"), ("weather", "WeatherLib"), ("other", "OtherLib")])

        def call(arg):
            return scan(f'import "../lib/glyphs.js" as Glyphs\n{libs}IconPlate {{ icon: Glyphs.glyph({arg}) }}')

        self.assertEqual(call('"alarm"'), (["alarm"], []))
        self.assertEqual(call('x === "a" ? "b" : VolumeLib.icon(v, m)'), (["b"], []))
        self.assertEqual(call("'alarm'")[0], [])
        self.assertEqual(len(call("'alarm'")[1]), 1)
        self.assertEqual(len(call("`alarm`")[1]), 1)
        self.assertEqual(len(call("root.name")[1]), 1)
        self.assertEqual(len(call("OtherLib.icon(v)")[1]), 1)
        self.assertEqual(len(call("UnimportedLib.icon(v)")[1]), 1)
        # A walked lib under another alias is still the walked lib, and a walked alias of another lib is not.
        self.assertEqual(scan('import "../lib/keys.js" as K\nX { icon: Glyphs.glyph(K.icon(k)) }'), ([], []))
        other = scan('import "../lib/other.js" as KeysLib\nX { icon: Glyphs.glyph(KeysLib.icon(k)) }')
        self.assertEqual(len(other[1]), 1)
        # One walked lib does not vouch for the other branch.
        self.assertEqual(len(call("a ? WeatherLib.icon(x) : OtherLib.icon(y)")[1]), 1)
        self.assertEqual(len(call('a ? "b" : OtherLib.icon(y)')[1]), 1)
        self.assertEqual(call("KeysLib.icon(k, on)"), ([], []))
        self.assertEqual(len(scan('import "../lib/glyphs.js" as G\nX { icon: G.glyph("alarm") }')[1]), 1)
        self.assertEqual(len(scan('import "../lib/glyphs.js"\n')[1]), 1)


if __name__ == "__main__":
    unittest.main()
