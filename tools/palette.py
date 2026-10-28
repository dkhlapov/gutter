#!/usr/bin/env python3
"""Generates Gutter's palette.json from a wallpaper image.

Usage: palette.py <image> [--out PATH] [--default PATH]
       palette.py --upgrade FILE [--out PATH] [--default PATH]
The palette is version 2: a light half (the print colours, black text on every accent) and a dark half (night paper,
soft cream lines and text, accents deepened to carry cream text).
--upgrade rewrites a version 1 file in place as version 2 and leaves a version 2 file alone; with --out it writes the
version 2 palette to PATH instead and leaves FILE untouched.
Exit 0 writes the palette atomically. Exit 1 leaves the target untouched and prints "palette: <reason>" on stderr.
"""
import argparse
import json
import math
import os
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

from atomicio import write_atomic

ROOT = Path(__file__).resolve().parents[1]
ACCENTS = ["navy", "teal", "magenta", "coral", "sun", "lime", "pink"]

SIZE = 300                  # longest side after downscaling
K = 12
ITERATIONS = 20
MAX_EMPTY = 3               # more empty slots than this and the run fails
MIN_CONTRAST = 4.5

# Pixels this dark, pale or grey are not accent candidates; the dark and light ones inform ink and paper.
# A light pixel is only near-white while its chroma is low, so a saturated yellow still counts as sun.
BLACK_L, WHITE_L, WHITE_MAX_C, MIN_CHROMA = 0.25, 0.9, 0.1, 0.04
INK_POOL_L, PAPER_POOL_L = 0.4, 0.8
INK_MAX_L, INK_MAX_C = 0.14, 0.03
PAPER_MIN_L, PAPER_MAX_C = 0.93, 0.06

# Night paper: the wallpaper's own dark tint, held to a narrow lightness band and a low chroma.
NIGHT_L, NIGHT_MAX_C = 0.23, 0.03
# Dark mode: lines and text are the light paper at this lightness (soft cream). Accents carry the full cream as text,
# at the highest lightness that keeps it at MIN_CONTRAST, with their chroma raised; yellows, which turn olive when this
# dark, become amber.
NIGHT_TEXT_L = 0.90
DEEP_STEP, DEEP_CHROMA = 0.005, 1.2
YELLOW_HUES, AMBER_HUE = (75, 110), 72

FLAT_CHROMA = 0.12
FLAT_L = (0.45, 0.80)
NUDGE_STEP, NUDGE_STEPS = 0.01, 40

HEX_COLOUR = re.compile(r"#[0-9a-fA-F]{6}")

# Modes that resize() averages as colour values; every other mode (P and PA hold palette indices, 1 is
# nearest-neighbour, LAB would lose its alpha in convert) is converted to RGBA before the thumbnail.
RESIZE_SAFE_MODES = ("RGB", "RGBA", "L", "LA", "CMYK", "YCbCr", "I", "F")


class PaletteError(Exception):
    pass


# --- colour maths -------------------------------------------------------------------------------

_M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                [0.2119034982, 0.6806995451, 0.1073969566],
                [0.0883024619, 0.2817188376, 0.6299787005]])
_M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                [1.9779984951, -2.4285922050, 0.4505937099],
                [0.0259040371, 0.7827717662, -0.8086757660]])


def _to_linear(srgb):
    return np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)


def _from_linear(lin):
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(np.maximum(lin, 0), 1 / 2.4) - 0.055)


def rgb_to_oklab(rgb):
    """(n, 3) sRGB 0-1 -> (n, 3) OKLab."""
    lms = _to_linear(rgb) @ _M1.T
    return np.cbrt(lms) @ _M2.T


def oklab_to_linear(lab):
    lms = (lab @ np.linalg.inv(_M2).T) ** 3
    return lms @ np.linalg.inv(_M1).T


def hex_to_rgb(hex_):
    """'#RRGGBB' as floats 0-1. ValueError for any other string, TypeError for a non-string."""
    if not HEX_COLOUR.fullmatch(hex_):
        raise ValueError("got %r" % (hex_,))
    return np.array([int(hex_[p:p + 2], 16) for p in (1, 3, 5)]) / 255


def oklab_l(hex_):
    return float(rgb_to_oklab(hex_to_rgb(hex_)[None])[0, 0])


def oklch_to_hex(l, c, h_deg):
    """Reduces chroma until the colour fits in sRGB, so hue and lightness are kept."""
    h = math.radians(h_deg)

    def linear(chroma):
        return oklab_to_linear(np.array([l, chroma * math.cos(h), chroma * math.sin(h)]))

    def fits(chroma):
        lin = linear(chroma)
        return lin.min() >= -1e-4 and lin.max() <= 1 + 1e-4

    if not fits(c):
        lo, hi = 0.0, c
        for _ in range(20):
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if fits(mid) else (lo, mid)
        c = lo
    rgb = np.rint(_from_linear(np.clip(linear(c), 0, 1)) * 255).astype(int)
    return "#%02x%02x%02x" % tuple(rgb)


def _luminance(hex_):
    return float(_to_linear(hex_to_rgb(hex_)) @ [0.2126, 0.7152, 0.0722])


def contrast(a_hex, b_hex):
    """WCAG 2.x contrast ratio, 1 to 21 (same formula as lib/palette.js)."""
    a, b = _luminance(a_hex), _luminance(b_hex)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def text_on(accent_hex, ink, paper):
    """Whichever of ink and paper reads better on the accent (same rule as lib/palette.js)."""
    return ink if contrast(accent_hex, ink) >= contrast(accent_hex, paper) else paper


def _lch(lab):
    return lab[0], math.hypot(lab[1], lab[2]), math.degrees(math.atan2(lab[2], lab[1])) % 360


def shift_l(hex_, delta):
    """The colour with its OKLab lightness moved by `delta` (clamped to 0-1); hue kept, chroma reduced to fit sRGB."""
    l, c, h = _lch(rgb_to_oklab(hex_to_rgb(hex_)[None])[0])
    return oklch_to_hex(min(max(l + delta, 0.0), 1.0), c, h)


def step_l(hex_, step, passes, limit=100):
    """Moves the colour's OKLab lightness by `step` at a time (hue and chroma kept, computed once) until `passes(hex)`;
    the colour itself is tried first. Stops after `limit` steps or at lightness 0 or 1, returning the last colour tried
    (the caller checks that it passes)."""
    l, c, h = _lch(rgb_to_oklab(hex_to_rgb(hex_)[None])[0])
    for _ in range(limit):
        if passes(hex_) or not 0.0 < l + step < 1.0:
            break
        l += step
        hex_ = oklch_to_hex(l, c, h)
    return hex_


# --- generator steps ----------------------------------------------------------------------------

def load_pixels(path):
    """Step 1: downscaled opaque pixels as OKLab, shape (n, 3)."""
    try:
        with Image.open(path) as img:
            # Converted first when resizing would go wrong: palette modes (P, PA) hold indices that averaging turns
            # into other colours, mode 1 is sampled nearest-neighbour, and averaging would blur a colour-key
            # transparency into opaque pixels. Otherwise the thumbnail comes first, so the full-size image is never
            # copied.
            if img.mode not in RESIZE_SAFE_MODES or "transparency" in img.info:
                img = img.convert("RGBA")
            img.thumbnail((SIZE, SIZE))
            px = np.asarray(img.convert("RGBA"), dtype=float).reshape(-1, 4)
    except Image.UnidentifiedImageError:    # an OSError whose text repeats the path
        raise PaletteError("cannot read %s: not an image" % path)
    except (OSError, ValueError, Image.DecompressionBombError) as e:
        raise PaletteError("cannot read %s: %s" % (path, describe_error(e)))
    px = px[px[:, 3] >= 128]
    if len(px) == 0:
        raise PaletteError("%s has no opaque pixels" % path)
    return rgb_to_oklab(px[:, :3] / 255)


def split_pixels(lab):
    """Step 2: chromatic pixels, plus the near-black and near-white ones that inform ink and paper."""
    chroma = np.hypot(lab[:, 1], lab[:, 2])
    dropped = (lab[:, 0] < BLACK_L) | ((lab[:, 0] > WHITE_L) & (chroma < WHITE_MAX_C)) | (chroma < MIN_CHROMA)
    return lab[~dropped], lab[dropped]


def extract_base(dropped, default):
    """Step 2: ink from the darkest pixels, paper from the lightest, both clamped. Default if there are none.

    Also returns the dark pool (every dropped pixel below INK_POOL_L) for the night paper."""
    def end(mask, order):
        pool = dropped[mask]
        if len(pool) == 0:
            return None
        pool = pool[np.argsort(order * pool[:, 0])]
        return pool[:max(1, len(pool) // 4)].mean(axis=0)

    def build(lab, default_hex, lo, hi, max_c):
        if lab is None:
            return default_hex
        l, c, h = _lch(lab)
        return oklch_to_hex(min(max(l, lo), hi), min(c, max_c), h)

    ink = build(end(dropped[:, 0] < INK_POOL_L, 1), default["ink"], 0, INK_MAX_L, INK_MAX_C)
    paper = build(end(dropped[:, 0] > PAPER_POOL_L, -1), default["paper"], PAPER_MIN_L, 1, PAPER_MAX_C)
    return ink, paper, dropped[dropped[:, 0] < INK_POOL_L]


def night_paper(dark_lab_pixels, default_dark_paper):
    """Dark-mode paper: the mean tint of the dark pool at lightness NIGHT_L, chroma capped. Default if the pool is empty."""
    if len(dark_lab_pixels) == 0:
        return default_dark_paper
    a, b = dark_lab_pixels[:, 1:].mean(axis=0)
    return oklch_to_hex(NIGHT_L, min(math.hypot(a, b), NIGHT_MAX_C), math.degrees(math.atan2(b, a)) % 360)


def kmeans(points, k=K, iterations=ITERATIONS):
    """Step 3: plain k-means with k-means++ seeding. Every pixel is one unit of area. Returns (centroids, counts)."""
    rng = np.random.default_rng(0)
    pts = np.unique(points, axis=0) if len(points) <= k else points
    k = min(k, len(pts))
    centroids = [pts[rng.integers(len(pts))]]
    for _ in range(k - 1):
        d2 = np.min(((pts[:, None] - np.array(centroids)[None]) ** 2).sum(axis=2), axis=1)
        centroids.append(pts[rng.choice(len(pts), p=d2 / d2.sum())] if d2.sum() > 0 else pts[0])
    centroids = np.array(centroids)
    for _ in range(iterations):
        labels = ((points[:, None] - centroids[None]) ** 2).sum(axis=2).argmin(axis=1)
        for i in range(k):
            if (labels == i).any():
                centroids[i] = points[labels == i].mean(axis=0)
    labels = ((points[:, None] - centroids[None]) ** 2).sum(axis=2).argmin(axis=1)
    return centroids, np.bincount(labels, minlength=k)


def slot_of(l, h):
    """Step 4: the slot an OKLCH colour belongs to, or None. Hue ranges are in degrees.

    Lightness splits: dark teal is navy, light magenta is pink, dark pink (raspberry) is magenta.
    """
    if 15 <= h < 50:
        return "coral"
    if 70 <= h < 110:
        return "sun"
    if 110 <= h < 150:
        return "lime"
    if 170 <= h < 215:
        return "navy" if l < 0.55 else "teal"
    if 215 <= h < 265:
        return "navy" if l < 0.55 else None
    if h >= 285 or h < 15:
        return "pink" if l >= 0.6 else "magenta"
    return None


def assign_slots(centroids, counts):
    """Step 4: each slot gets the most populous cluster in its range -> {slot: (L, C, h)}."""
    best = {}
    for cen, n in zip(centroids, counts):
        if n == 0:
            continue
        l, c, h = _lch(cen)
        slot = slot_of(l, h)
        if slot and (slot not in best or n > best[slot][0]):
            best[slot] = (n, (l, c, h))
    return {slot: lch for slot, (n, lch) in best.items()}


def flatten(l, c, h):
    """Step 5: saturated, mid-light value, as flat print colour."""
    return oklch_to_hex(min(max(l, FLAT_L[0]), FLAT_L[1]), max(c, FLAT_CHROMA), h)


def ensure_contrast(hex_, ink):
    """Step 6: light mode's text on every accent is the ink (black), so lightness is raised (hue and chroma kept) until
    the ink reads on the accent at 4.5:1. Unchanged if it already does."""
    return step_l(hex_, NUDGE_STEP, lambda x: contrast(x, ink) >= MIN_CONTRAST, NUDGE_STEPS)


def deepen(accent_hex, cream):
    """Dark-mode accent: the light accent with its chroma raised (yellows turned amber) at the highest lightness at which
    `cream`, text on every accent in dark mode, reads on it at 4.5:1."""
    l, c, h = _lch(rgb_to_oklab(hex_to_rgb(accent_hex)[None])[0])
    if YELLOW_HUES[0] <= h < YELLOW_HUES[1]:
        h = AMBER_HUE
    l = 1.0
    while l > 0:
        hex_ = oklch_to_hex(l, c * DEEP_CHROMA, h)
        if contrast(hex_, cream) >= MIN_CONTRAST:
            return hex_
        l -= DEEP_STEP
    return oklch_to_hex(0, 0, h)


def night_text(cream):
    """Dark-mode lines and text: `cream` (the light paper) at lightness NIGHT_TEXT_L, hue and chroma kept."""
    l, c, h = _lch(rgb_to_oklab(hex_to_rgb(cream)[None])[0])
    return oklch_to_hex(min(l, NIGHT_TEXT_L), c, h)


def dark_half(light, dark_paper):
    """The dark half of a palette: soft cream lines and text on the night paper; accents deepened to carry the light
    paper (full cream) as text."""
    text = night_text(light["paper"])
    return {"ink": text, "paper": dark_paper, "text": text,
            "accents": {name: deepen(hex_, light["paper"]) for name, hex_ in light["accents"].items()}}


def light_half(ink, paper, accents):
    """The light half of a palette: the print colours, with the ink as text."""
    return {"ink": ink, "paper": paper, "text": ink, "accents": accents}


def upgrade(v1, default_v2):
    """A version 1 palette as version 2: its colours become the light half (accents lightened where black text needs
    it), the dark half is derived from them."""
    light = light_half(v1["ink"], v1["paper"], {n: ensure_contrast(a, v1["ink"]) for n, a in v1["accents"].items()})
    pal = {"version": 2, "source": v1.get("source", ""), "roles": dict(v1["roles"]),
           "light": light, "dark": dark_half(light, default_v2["dark"]["paper"])}
    if "filled" in v1:
        pal["filled"] = v1["filled"]
    return pal


def generate(image_path, default):
    """Returns a version 2 palette dict for the image. Slots with no matching hue come from `default` (version 2)."""
    chromatic, dropped = split_pixels(load_pixels(image_path))
    ink, paper, dark_pool = extract_base(dropped, default["light"])
    found = assign_slots(*kmeans(chromatic)) if len(chromatic) else {}
    if len(ACCENTS) - len(found) > MAX_EMPTY:
        raise PaletteError("only %d of %d colour slots found in %s" % (len(found), len(ACCENTS), image_path))
    accents = {}
    for name in default["light"]["accents"]:
        hex_ = flatten(*found[name]) if name in found else default["light"]["accents"][name]
        accents[name] = ensure_contrast(hex_, ink)
    light = light_half(ink, paper, accents)
    return {"version": 2, "source": str(image_path), "roles": dict(default["roles"]), "light": light,
            "dark": dark_half(light, night_paper(dark_pool, default["dark"]["paper"])), "filled": len(found)}


# --- command line -------------------------------------------------------------------------------

def default_out():
    state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(state) / "gutter" / "palette.json"


def describe_error(e):
    """An exception as one short phrase for an error line: the file's path is not repeated for an OSError, and a
    KeyError reads as a missing key."""
    if isinstance(e, OSError):
        return e.strerror or str(e)
    if isinstance(e, KeyError):
        return "missing key %s" % e
    if isinstance(e, (TypeError, AttributeError)):
        return "%s: %s" % (type(e).__name__, e)
    return str(e)


def load_default(path):
    try:
        default = json.loads(path.read_text())
        default["light"]["ink"], default["light"]["paper"], default["light"]["accents"], default["dark"]["paper"]
        default["roles"]
    except (OSError, ValueError, KeyError, TypeError) as e:
        raise PaletteError("cannot use default palette %s: %s" % (path, describe_error(e)))
    return default


def upgrade_file(path, default, out=None):
    """Rewrites a version 1 file as version 2 in place, or at `out` (the file itself is then left alone). A version 2
    file is left untouched, or copied to `out`."""
    try:
        text = path.read_text()
        pal = json.loads(text)
    except (OSError, ValueError) as e:
        raise PaletteError("cannot read %s: %s" % (path, describe_error(e)))
    try:
        version = pal["version"]
    except (KeyError, TypeError):
        raise PaletteError("cannot read %s: no palette version" % path)
    if type(version) is not int or version not in (1, 2):  # True, 1.0, 2.0 equal 1 or 2: the type test rejects them
        raise PaletteError("cannot upgrade %s: unknown palette version %r" % (path, version))
    if version == 2:
        if out:
            write_atomic(out, text, ".palette-")
        return
    try:
        v2 = upgrade(pal, default)
    except (KeyError, TypeError, AttributeError) as e:
        raise PaletteError("cannot upgrade %s: %s" % (path, describe_error(e)))
    except ValueError as e:     # a colour that is not #RRGGBB, from hex_to_rgb
        raise PaletteError("cannot upgrade %s: a colour is not #RRGGBB (%s)" % (path, e))
    write_atomic(out or path, json.dumps(v2, indent=2) + "\n", ".palette-")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Generate Gutter's palette.json from a wallpaper.")
    what = ap.add_mutually_exclusive_group(required=True)
    what.add_argument("image", nargs="?")
    what.add_argument("--upgrade", type=Path, metavar="FILE", help="rewrite a version 1 palette as version 2")
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--default", type=Path, default=ROOT / "theme" / "default-palette.json")
    args = ap.parse_args(argv)
    try:
        default = load_default(args.default)
        if args.upgrade:
            upgrade_file(args.upgrade, default, args.out)
        else:
            pal = generate(os.path.abspath(args.image), default)
            write_atomic(args.out or default_out(), json.dumps(pal, indent=2) + "\n", ".palette-")
    except (PaletteError, OSError) as e:
        print("palette: %s" % e, file=sys.stderr)
        return 1
    except Exception as e:      # whatever else a hostile image or file turns up: one line, target untouched
        print("palette: unexpected %s: %s" % (type(e).__name__, e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
