import json, os, re, subprocess, sys, tempfile, unittest
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import palette

DEFAULT = json.loads((ROOT / "theme/default-palette.json").read_text())

HUES = [(230, 70, 45), (245, 205, 60), (160, 210, 60), (30, 165, 165), (35, 70, 110), (140, 60, 160), (235, 115, 155), (10, 10, 10), (250, 245, 210)]
BLACK, CREAM = DEFAULT["light"]["ink"], DEFAULT["light"]["paper"]
LIGHT_V1 = {  # what the version 1 generator gave for HUES
    "ink": "#070808",
    "paper": "#fbf6d3",
    "accents": {"navy": "#175695", "teal": "#00a6a6", "magenta": "#8c3ca0", "coral": "#e6462d",
                "sun": "#e1ba1b", "lime": "#9fd23c", "pink": "#eb739b"},
}
V1_SAMPLE = {
    "version": 1, "source": "", "ink": "#0e0d0e", "paper": "#fbf6d3",
    "accents": {"navy": "#224969", "teal": "#22a5a6", "magenta": "#8e3fa0", "coral": "#e2492f",
                "sun": "#f6d14b", "lime": "#a3d23a", "pink": "#e8739d"},
    "roles": {"active": "sun", "urgent": "coral", "focusBorder": "teal", "ok": "lime", "special": "magenta", "muted": "navy"},
}

def oklch(hex_):
    L, a, b = palette.rgb_to_oklab(palette.hex_to_rgb(hex_)[None])[0]
    return L, (a * a + b * b) ** 0.5

def hue(hex_):
    return palette._lch(palette.rgb_to_oklab(palette.hex_to_rgb(hex_)[None])[0])[2]

def checkerboard(left, right, size=600):
    """A size x size RGB image of 1 px checks: `left` and `right` (the two halves) are each an (even, odd) pair of
    colours, a pixel being even when (x + y) % 2 is 0."""
    x, y = palette.np.meshgrid(palette.np.arange(size), palette.np.arange(size))
    colours = palette.np.array([left, right], dtype=palette.np.uint8)    # [half][parity][channel]
    return Image.fromarray(colours[(x >= size // 2).astype(int), (x + y) % 2])

def blocks(path, colours, mode="RGB"):
    img = Image.new(mode, (70 * len(colours), 70))
    for i, c in enumerate(colours):
        img.paste(c, (70 * i, 0, 70 * (i + 1), 70))
    img.save(path)

class Palette(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def blocks_image(self):
        img = self.dir / "blocks.png"
        blocks(img, HUES)
        return img

    def fixture_images(self):
        dark = self.dir / "dark.png"  # nearly all #101010, so the dark pool has no tint at all; the hues keep it generatable
        blocks(dark, [(16, 16, 16)] * 8 + HUES[:7])
        return [self.blocks_image(), dark]

    def run_cli(self, image, out, *args):
        return subprocess.run([sys.executable, str(ROOT / "tools/palette.py"), str(image), "--out", str(out),
                               *map(str, args)], capture_output=True, text=True)

    def run_upgrade(self, f, *args):
        return subprocess.run([sys.executable, str(ROOT / "tools/palette.py"), "--upgrade", str(f), *args],
                              capture_output=True, text=True)

    def test_hue_blocks_fill_their_slots(self):
        img = self.dir / "b.png"
        blocks(img, HUES)
        p = palette.generate(str(img), DEFAULT)
        self.assertEqual(sorted(p["light"]["accents"]), sorted(DEFAULT["light"]["accents"]))
        self.assertGreater(int(p["light"]["accents"]["coral"][1:3], 16), int(p["light"]["accents"]["coral"][3:5], 16))  # red-dominant
        self.assertEqual(p["roles"], DEFAULT["roles"])
        self.assertEqual(p["source"], str(img))
        self.assertEqual(p["filled"], 7)

    def test_dark_pink_hue_counts_as_magenta(self):
        img = self.dir / "r.png"
        # raspberry: OKLCH L 0.49, h 341, inside the pink hue range but too dark for pink
        blocks(img, [(155, 45, 125), (230, 70, 45), (245, 205, 60), (30, 165, 165)])
        p = palette.generate(str(img), DEFAULT)
        self.assertEqual(p["filled"], 4)
        self.assertNotEqual(p["light"]["accents"]["magenta"], DEFAULT["light"]["accents"]["magenta"])
        self.assertEqual(p["light"]["accents"]["pink"], DEFAULT["light"]["accents"]["pink"])

    def test_light_accents_carry_black_text(self):
        # Light mode: text on every accent is the ink (black), so a dark navy or magenta is lightened until it reads.
        img = self.dir / "b.png"
        blocks(img, [(255, 240, 0), (0, 0, 120), (120, 0, 140), (0, 200, 200)])
        for p in [palette.generate(str(img), DEFAULT)] + [palette.generate(str(i), DEFAULT) for i in self.fixture_images()]:
            ink, paper = p["light"]["ink"], p["light"]["paper"]
            for name, hex_ in p["light"]["accents"].items():
                self.assertGreaterEqual(palette.contrast(hex_, ink), 4.5, name)
                self.assertEqual(palette.text_on(hex_, ink, paper), ink, name)

    def test_palette_mode_image_is_averaged_like_its_rgb_copy(self):
        # A dithered GIF (mode P): the 1 px checkerboard must be averaged, not sampled, as in the same image saved
        # as RGB.
        board = checkerboard((HUES[0], HUES[3]), (HUES[3], HUES[6]))
        gif, png = self.dir / "d.gif", self.dir / "d.png"
        board.quantize(8, dither=Image.Dither.NONE).save(gif)
        Image.open(gif).convert("RGB").save(png)
        self.assertEqual(Image.open(gif).mode, "P")
        a, b = palette.load_pixels(str(gif)), palette.load_pixels(str(png))
        self.assertTrue(palette.np.allclose(a, b))

    def test_colour_key_transparency_is_applied_before_averaging(self):
        # An RGB PNG whose transparent colour is dithered with teal: the key pixels drop out, so none of the mix
        # survives.
        board = checkerboard(((30, 165, 165), (1, 2, 3)), ((30, 165, 165), (1, 2, 3)))
        img = self.dir / "key.png"
        board.save(img, transparency=(1, 2, 3))
        teal = palette.rgb_to_oklab(palette.np.array([[30, 165, 165]]) / 255)[0]
        px = palette.load_pixels(str(img))
        self.assertLess(palette.np.abs(px - teal).max(), 0.02)

    def test_palette_alpha_mode_image_is_averaged_like_its_rgb_copy(self):
        # PA holds palette indices too: averaging them first turned a teal and red checkerboard into other colours.
        board = checkerboard((HUES[0], HUES[3]), (HUES[3], HUES[6]))
        pa, png = self.dir / "pa.tiff", self.dir / "pa.png"
        board.quantize(8, dither=Image.Dither.NONE).convert("PA").save(pa)
        with Image.open(pa) as img:
            self.assertEqual(img.mode, "PA")
            img.convert("RGB").save(png)
        self.assertTrue(palette.np.allclose(palette.load_pixels(str(pa)), palette.load_pixels(str(png))))

    def test_16_bit_greyscale_image_does_not_fail_to_load(self):
        # Pillow cannot thumbnail I;16 unless the size halves exactly: this used to fail with "wrong mode".
        img = self.dir / "grey16.png"
        Image.new("I;16", (1920, 1080), 30000).save(img)
        with Image.open(img) as im:
            self.assertEqual(im.mode, "I;16")
        # The converted colours are not asserted: Pillow clips 16-bit to white, and a greyscale image yields no palette.
        self.assertGreater(len(palette.load_pixels(str(img))), 0)

    def test_lab_image_keeps_its_alpha(self):
        # Resized first, a LAB image converted to RGBA with alpha 0 and read as having no opaque pixels.
        lab = self.dir / "lab.tiff"
        Image.new("RGB", (600, 600), (30, 165, 165)).convert("LAB").save(lab)
        with Image.open(lab) as img:
            self.assertEqual(img.mode, "LAB")
        teal = palette.rgb_to_oklab(palette.np.array([[30, 165, 165]]) / 255)[0]
        self.assertLess(palette.np.abs(palette.load_pixels(str(lab)) - teal).max(), 0.02)

    def test_cli_writes_the_palette_atomically(self):
        out = self.dir / "palette.json"
        out.write_text("CURRENT")
        r = self.run_cli(self.blocks_image(), out)
        self.assertEqual((r.returncode, r.stderr), (0, ""))
        p = json.loads(out.read_text())
        self.assertEqual((p["version"], p["filled"]), (2, 7))
        # no .palette-*.tmp left behind
        self.assertEqual(sorted(f.name for f in self.dir.iterdir()), ["blocks.png", "palette.json"])

    def test_cli_unexpected_error_is_one_line_and_leaves_the_target(self):
        out = self.dir / "palette.json"
        out.write_text("CURRENT")
        img, bad = self.dir / "four.png", self.dir / "default.json"
        blocks(img, HUES[:4])   # no navy in the image, so the default's navy is used, and it is not a colour
        d = json.loads(json.dumps(DEFAULT)); d["light"]["accents"]["navy"] = 5
        bad.write_text(json.dumps(d))
        r = self.run_cli(img, out, "--default", bad)
        self.assertEqual(r.returncode, 1)
        self.assertNotIn("Traceback", r.stderr)
        self.assertEqual(len(r.stderr.strip().splitlines()), 1, r.stderr)
        self.assertTrue(r.stderr.startswith("palette: "), r.stderr)
        self.assertEqual(out.read_text(), "CURRENT")

    def test_monochrome_keeps_current_palette(self):
        img, out = self.dir / "m.png", self.dir / "palette.json"
        blocks(img, [(0, 0, 0), (128, 128, 128), (255, 255, 255)])
        out.write_text("CURRENT")
        r = self.run_cli(img, out)
        self.assertEqual(r.returncode, 1)
        self.assertIn("palette:", r.stderr)
        self.assertEqual(out.read_text(), "CURRENT")

    def test_rgba_and_missing_file(self):
        img = self.dir / "a.png"
        blocks(img, [(230, 70, 45, 0), (30, 165, 165, 255), (245, 205, 60, 255), (140, 60, 160, 255), (160, 210, 60, 255)], mode="RGBA")
        p = palette.generate(str(img), DEFAULT)
        # The alpha-0 block is coral; ignored, so coral is the default and only the four opaque hues are found.
        self.assertEqual(p["filled"], 4)
        self.assertEqual(p["light"]["accents"]["coral"], DEFAULT["light"]["accents"]["coral"])
        r = self.run_cli(self.dir / "nope.jpg", self.dir / "p.json")
        self.assertEqual(r.returncode, 1)
        self.assertFalse((self.dir / "p.json").exists())

    def test_ink_and_paper_clamped(self):
        img = self.dir / "b.png"
        blocks(img, [(60, 60, 60), (200, 200, 200), (230, 70, 45), (30, 165, 165), (245, 205, 60), (140, 60, 160)])
        p = palette.generate(str(img), DEFAULT)
        self.assertLess(palette.oklab_l(p["light"]["ink"]), 0.15)
        self.assertGreater(palette.oklab_l(p["light"]["paper"]), 0.92)

    def test_generate_writes_v2_with_both_halves(self):
        p = palette.generate(str(self.blocks_image()), DEFAULT)
        self.assertEqual(p["version"], 2)
        self.assertEqual(p["light"]["text"], p["light"]["ink"])
        # Dark lines and text are one soft cream: the light paper at OKLab lightness 0.90, hue kept.
        self.assertEqual(p["dark"]["ink"], p["dark"]["text"])
        self.assertAlmostEqual(oklch(p["dark"]["ink"])[0], 0.90, delta=0.005)
        self.assertAlmostEqual(hue(p["dark"]["ink"]), hue(p["light"]["paper"]), delta=3)

    def test_night_paper_band(self):
        for img in self.fixture_images():
            p = palette.generate(str(img), DEFAULT)
            L, C = oklch(p["dark"]["paper"])
            self.assertTrue(0.20 <= L <= 0.26, (img, L))
            self.assertLessEqual(C, 0.03 + 1e-3)

    def test_night_paper_takes_the_tint_of_a_dark_pool(self):
        # Dark blocks tinted blue and red, beside the seven hues: the night paper keeps their hue at L 0.23, chroma
        # capped.
        for tint in ((24, 22, 48), (40, 20, 20)):
            with self.subTest(tint=tint):
                img = self.dir / "tinted.png"
                blocks(img, [tint] * 8 + HUES[:7])
                paper = palette.generate(str(img), DEFAULT)["dark"]["paper"]
                L, C = oklch(paper)
                self.assertAlmostEqual(L, palette.NIGHT_L, delta=0.005)
                self.assertAlmostEqual(C, palette.NIGHT_MAX_C, delta=1e-3)
                self.assertAlmostEqual(hue(paper), hue("#%02x%02x%02x" % tint), delta=5)
                self.assertNotEqual(paper, DEFAULT["dark"]["paper"])

    def test_night_paper_caps_chroma_and_keeps_hue(self):
        lab = palette.np.array([[0.2, 0.0, -0.08]])    # hue 270, chroma well over the cap
        L, C = oklch(palette.night_paper(lab, "#26232b"))
        self.assertAlmostEqual(L, palette.NIGHT_L, delta=0.005)
        self.assertAlmostEqual(C, palette.NIGHT_MAX_C, delta=1e-3)
        self.assertAlmostEqual(hue(palette.night_paper(lab, "#26232b")), 270, delta=3)

    def test_slot_of_pinks_and_magentas(self):
        for h in (285, 310, 330, 350, 359, 0, 14):
            self.assertEqual(palette.slot_of(0.7, h), "pink", h)
            self.assertEqual(palette.slot_of(0.5, h), "magenta", h)
        self.assertEqual(palette.slot_of(0.7, 270), None)
        self.assertEqual(palette.slot_of(0.7, 15), "coral")

    def test_dark_accents_contrast(self):
        for img in self.fixture_images():
            p = palette.generate(str(img), DEFAULT)
            d, light = p["dark"], p["light"]
            cream = light["paper"]
            for name, hex_ in d["accents"].items():
                self.assertGreaterEqual(palette.contrast(hex_, d["paper"]), 3.0, (img, name))
                # Dark mode: text on every accent is the cream, and the accent is as light as that allows.
                self.assertGreaterEqual(palette.contrast(hex_, cream), 4.5, (img, name))
                self.assertEqual(palette.text_on(hex_, light["ink"], cream), cream, (img, name))
                self.assertLess(palette.contrast(palette.shift_l(hex_, 0.01), cream), 4.5, (img, name))

    def test_light_half_keeps_v1_accents_that_carry_black(self):
        p = palette.generate(str(self.blocks_image()), DEFAULT)
        self.assertEqual({k: p["light"][k] for k in ("ink", "paper")}, {k: LIGHT_V1[k] for k in ("ink", "paper")})
        for name, old in LIGHT_V1["accents"].items():
            new = p["light"]["accents"][name]
            if palette.contrast(old, LIGHT_V1["ink"]) >= 4.5:
                self.assertEqual(new, old, name)
            else:  # lightened just far enough, hue kept
                self.assertGreater(oklch(new)[0], oklch(old)[0], name)
                self.assertLess(palette.contrast(palette.shift_l(new, -0.01), LIGHT_V1["ink"]), 4.5, name)
                self.assertAlmostEqual(hue(new), hue(old), delta=3, msg=name)

    def test_accent_already_carrying_black_keeps_lightness(self):
        self.assertEqual(palette.ensure_contrast("#f6d14b", BLACK), "#f6d14b")

    def test_deepen_turns_yellow_to_amber_and_keeps_other_hues(self):
        self.assertAlmostEqual(hue(palette.deepen("#f6d14b", CREAM)), palette.AMBER_HUE, delta=2)
        for accent in ("#a3d23a", "#22a5a6", "#e8739d"):
            self.assertAlmostEqual(hue(palette.deepen(accent, CREAM)), hue(accent), delta=3, msg=accent)

    def test_default_palette_follows_the_rule(self):
        light = DEFAULT["light"]
        self.assertEqual({n: palette.ensure_contrast(a, light["ink"]) for n, a in light["accents"].items()}, light["accents"])
        self.assertEqual(palette.dark_half(light, DEFAULT["dark"]["paper"]), DEFAULT["dark"])

    def test_theme_last_resort_matches_the_default_palette(self):
        # Theme.qml's lastResort is the default palette written out, for when default-palette.json cannot be read.
        qml = (ROOT / "theme/Theme.qml").read_text()
        block = qml[qml.index("lastResort"):qml.index("defaultParsed")]
        got = re.findall(r'(\w+): "(#[0-9a-f]{6})"', block)
        want = [(k, DEFAULT[m][k]) for m in ("light",) for k in ("ink", "paper", "text")]
        want += list(DEFAULT["light"]["accents"].items())
        want += [(k, DEFAULT["dark"][k]) for k in ("ink", "paper", "text")] + list(DEFAULT["dark"]["accents"].items())
        self.assertEqual(got, want)

    def test_upgrade_gives_v1_navy_black_text(self):
        p = palette.upgrade(V1_SAMPLE, DEFAULT)
        for name, hex_ in p["light"]["accents"].items():
            self.assertGreaterEqual(palette.contrast(hex_, p["light"]["ink"]), 4.5, name)

    def test_night_paper_without_dark_pixels_is_the_default(self):
        self.assertEqual(palette.night_paper(palette.np.empty((0, 3)), "#26232b"), "#26232b")

    def test_shift_l_clamps_and_keeps_hue(self):
        self.assertEqual(palette.shift_l("#e2492f", 5), "#ffffff")
        self.assertEqual(palette.shift_l("#e2492f", -5), "#000000")
        base = palette._lch(palette.rgb_to_oklab(palette.hex_to_rgb("#22a5a6")[None])[0])
        moved = palette._lch(palette.rgb_to_oklab(palette.hex_to_rgb(palette.shift_l("#22a5a6", 0.1))[None])[0])
        self.assertAlmostEqual(moved[0], base[0] + 0.1, delta=0.01)
        self.assertAlmostEqual(moved[2], base[2], delta=3)

    def test_step_l_tries_the_colour_first_and_stops_at_the_end(self):
        self.assertEqual(palette.step_l("#22a5a6", 0.01, lambda h: True), "#22a5a6")
        self.assertEqual(palette.step_l("#808080", 0.01, lambda h: False, limit=500), "#ffffff")

    def test_upgrade_cli_rewrites_v1(self):
        f = self.dir / "p.json"
        f.write_text(json.dumps(V1_SAMPLE))
        r = self.run_upgrade(f)
        self.assertEqual(r.returncode, 0, r.stderr)
        p = json.loads(f.read_text())
        self.assertEqual(p["version"], 2)
        self.assertEqual(p["light"]["paper"], V1_SAMPLE["paper"])
        self.assertEqual(p["dark"]["paper"], DEFAULT["dark"]["paper"])

    def test_upgrade_cli_out_writes_there_and_leaves_the_file(self):
        f, out = self.dir / "p.json", self.dir / "out.json"
        f.write_text(json.dumps(V1_SAMPLE))
        before = f.read_bytes()
        r = self.run_upgrade(f, "--out", out)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(f.read_bytes(), before)
        self.assertEqual(json.loads(out.read_text()), palette.upgrade(V1_SAMPLE, DEFAULT))
        f.write_text(json.dumps(DEFAULT))   # a version 2 file is copied
        out.unlink()
        r = self.run_upgrade(f, "--out", out)
        self.assertEqual((r.returncode, out.read_bytes()), (0, f.read_bytes()))

    def test_upgrade_cli_malformed_colour_is_one_line(self):
        for bad in ("#zz0000", "#abc", "teal"):
            with self.subTest(bad=bad):
                f = self.dir / "p.json"
                v1 = json.loads(json.dumps(V1_SAMPLE)); v1["accents"]["teal"] = bad
                f.write_text(json.dumps(v1))
                before = f.read_bytes()
                r = self.run_upgrade(f)
                self.assertEqual(r.returncode, 1)
                self.assertNotIn("Traceback", r.stderr)
                self.assertEqual(len(r.stderr.strip().splitlines()), 1, r.stderr)
                self.assertIn("palette: cannot upgrade %s: a colour is not #RRGGBB" % f, r.stderr)
                self.assertEqual(f.read_bytes(), before)

    def test_hex_to_rgb_wants_exactly_rrggbb(self):
        self.assertEqual(palette.hex_to_rgb("#ff0080").tolist(), [1.0, 0.0, 128 / 255])
        self.assertEqual(palette.hex_to_rgb("#FF0080").tolist(), [1.0, 0.0, 128 / 255])
        for bad in ("x123456", "#12345", "#1234567", "123456", "#12345g", ""):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                palette.hex_to_rgb(bad)
        with self.assertRaises(TypeError):
            palette.hex_to_rgb(5)

    def test_upgrade_cli_prefix_other_than_hash_is_refused(self):
        f = self.dir / "p.json"
        v1 = json.loads(json.dumps(V1_SAMPLE)); v1["ink"] = "x123456"
        f.write_text(json.dumps(v1))
        before = f.read_bytes()
        r = self.run_upgrade(f)
        self.assertEqual(r.returncode, 1)
        self.assertEqual(len(r.stderr.strip().splitlines()), 1, r.stderr)
        self.assertIn("a colour is not #RRGGBB", r.stderr)
        self.assertEqual(f.read_bytes(), before)

    def test_upgrade_cli_read_errors_say_the_path_once(self):
        d = self.dir / "dir.json"
        d.mkdir()
        r = self.run_upgrade(d)
        self.assertEqual(r.returncode, 1)
        self.assertEqual(len(r.stderr.strip().splitlines()), 1, r.stderr)
        self.assertTrue(r.stderr.startswith("palette: cannot read %s: " % d), r.stderr)
        self.assertEqual(r.stderr.count(str(d)), 1, r.stderr)
        r = self.run_upgrade(self.dir / "none.json")
        self.assertEqual((r.returncode, r.stderr.count("none.json")), (1, 1), r.stderr)

    def test_upgrade_cli_version_must_be_the_integer_1_or_2(self):
        f = self.dir / "p.json"
        for version in ("true", "1.0", "2.0", "3", "null", '"1"'):
            with self.subTest(version=version):
                f.write_text('{"version": %s}' % version)
                r = self.run_upgrade(f)
                self.assertEqual(r.returncode, 1)
                self.assertEqual(r.stderr.strip(), "palette: cannot upgrade %s: unknown palette version %s"
                                 % (f, "None" if version == "null" else repr(json.loads(version))))
                self.assertEqual(f.read_text(), '{"version": %s}' % version)

    def test_missing_image_says_the_path_once(self):
        r = self.run_cli(self.dir / "none.png", self.dir / "out.json")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(len(r.stderr.strip().splitlines()), 1, r.stderr)
        self.assertEqual(r.stderr.count("none.png"), 1, r.stderr)

    def test_unreadable_images_say_the_path_once(self):
        whole = self.dir / "whole.png"
        Image.new("RGB", (60, 60), (30, 165, 165)).save(whole)
        text, cut = self.dir / "text.png", self.dir / "cut.png"
        text.write_text("hello")
        cut.write_bytes(whole.read_bytes()[:len(whole.read_bytes()) // 2])
        for img in (text, cut):
            with self.subTest(img=img.name):
                r = self.run_cli(img, self.dir / "out.json")
                self.assertEqual(r.returncode, 1)
                self.assertEqual(len(r.stderr.strip().splitlines()), 1, r.stderr)
                self.assertEqual(r.stderr.count(img.name), 1, r.stderr)

    def test_upgrade_cli_missing_key_reads_the_same_everywhere(self):
        f = self.dir / "p.json"
        for text in ("{}", "[1]"):      # no version
            with self.subTest(text=text):
                f.write_text(text)
                r = self.run_upgrade(f)
                self.assertEqual(r.returncode, 1)
                self.assertEqual(r.stderr.strip(), "palette: cannot read %s: no palette version" % f)
        v1 = json.loads(json.dumps(V1_SAMPLE)); del v1["ink"]
        f.write_text(json.dumps(v1))
        r = self.run_upgrade(f)
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stderr.strip(), "palette: cannot upgrade %s: missing key 'ink'" % f)

    def test_upgrade_cli_leaves_v2_alone(self):
        f = self.dir / "p.json"
        f.write_text(json.dumps(DEFAULT))
        before = f.read_bytes()
        r = self.run_upgrade(f)
        self.assertEqual((r.returncode, f.read_bytes()), (0, before))

    def test_default_palette_is_v2_and_in_band(self):
        self.assertEqual(DEFAULT["version"], 2)
        L, C = oklch(DEFAULT["dark"]["paper"])
        self.assertTrue(0.20 <= L <= 0.26)
        self.assertLessEqual(C, 0.031)
