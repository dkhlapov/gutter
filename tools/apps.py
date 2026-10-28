#!/usr/bin/env python3
"""Renders the app configs (foot, fuzzel, GTK, Thunar, Qt, btop, Deezer) from a version 2 palette for one mode.

`render_all(palette, mode)` is pure: it returns {app: [(path relative to XDG_CONFIG_HOME, text)]} and writes nothing.
`apply` writes them under the config directory and signals the running apps; `main` is what `gutter theme apply` runs.
Before its first write of a file that is not Gutter's own (gtk.css, thunar.css, qtengine/config.json, btop.conf),
`apply` backs it up by the hand-over's rule (handover.back_up_once), so the original is kept as `<file>.pre-gutter`
(or a `-absent` marker when the file did not exist). Writes go through a symlink to its target and keep the file's mode.
Templates live in theme/templates/ and use `{{ name }}` placeholders; `fill` raises KeyError for an unknown one.
Colour rules: lines are the half's `ink` (cream in dark mode), text on an accent is the light half's ink or paper,
whichever contrasts more (the rule lib/palette.js applies), and an accent drawn as text on paper is kept as is when it
reaches 3:1, otherwise moved in lightness until it does (Qt's `_alt_text` accents reach it on paper_alt as well).
"""
import argparse
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

import deezer
import palette
from atomicio import write_atomic
from handover import GENERATED, back_up_once, real

ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = ROOT / "theme" / "templates"
MODES = ("light", "dark")
ROLE_KEYS = ("active", "urgent", "ok", "special", "muted")

FOOT_NORMAL = ("coral", "lime", "sun", "navy", "magenta", "teal")  # regular1..6
FOOT_LIGHT_TEXT = (2, 3)        # light mode: lime and sun, darkened (regular and bright) until they read on the paper
FOOT_BRIGHT_L = 0.08            # bright = regular lifted by this much OKLab lightness
FOOT_BLACK_L = -0.05            # dark mode regular0: the dark paper lowered by this much
FOOT_WHITE_L = -0.15            # light mode regular7: the light paper lowered by this much
ALT_L = 0.04                    # row/button tint: paper moved by this much, towards the text
TEXT_CONTRAST = 3.0             # an accent, or dark bright black, as text on paper (Qt `_alt_text`: paper_alt too)
LIFT_STEP = 0.01                # OKLab lightness steps when raising or lowering a colour until it reads
FUZZEL_ALPHA = "ff"

PLACEHOLDER = re.compile(r"\{\{\s*(\w+)\s*\}\}")


def fill(template, values):
    """Replaces every `{{ name }}` with values[name]; an unknown name raises KeyError."""
    return PLACEHOLDER.sub(lambda m: values[m.group(1)], template)


def _template(name):
    return (TEMPLATES / name).read_text()


def _bare(hex_):
    """'#RRGGBB' -> 'rrggbb' (foot and fuzzel take colours without the hash)."""
    return hex_.lstrip("#").lower()


def _on_paper(accent, paper, text):
    """The accent as a foreground colour on paper: unchanged at 3:1, else its lightness moves away from the paper until
    it gets there (hue kept); the text colour if no lightness does."""
    step = -LIFT_STEP if palette.oklab_l(paper) > 0.5 else LIFT_STEP
    hex_ = palette.step_l(accent, step, lambda x: palette.contrast(x, paper) >= TEXT_CONTRAST)
    return hex_ if palette.contrast(hex_, paper) >= TEXT_CONTRAST else text


def _bright_black(paper):
    """Dark mode bright0: the paper with its lightness raised (hue and chroma kept) until it reads on the paper at 3:1,
    so fish suggestions and comments drawn in bright black stay visible."""
    return palette.step_l(paper, LIFT_STEP, lambda x: palette.contrast(x, paper) >= TEXT_CONTRAST)


def half_values(pal, name):
    """Placeholder values (with '#') for one half: the base colours, every accent, the five roles, and the derived ones.
    `<role>_text` reads on the paper; `<role>_alt_text` on paper_alt too (Qt draws it as a background as well)."""
    half, light, roles = pal[name], pal["light"], pal["roles"]
    black, cream = light["ink"], light["paper"]
    paper, text = half["paper"], half["text"]
    v = {"paper": paper, "text": text, "ink": half["ink"]}
    v["paper_alt"] = palette.shift_l(paper, -ALT_L if palette.oklab_l(paper) > 0.5 else ALT_L)
    v.update(half["accents"])
    for role in ROLE_KEYS:
        accent = half["accents"][roles[role]]
        v[role] = accent
        v["on_" + role] = palette.text_on(accent, black, cream)
        v[role + "_text"] = _on_paper(accent, paper, text)
    v["focus"] = half["accents"][roles["focusBorder"]]
    v["accent_text"] = v["active_text"]
    v["link_text"] = _on_paper(v["focus"], paper, text)
    v["neutral_text"] = v["active_text"]
    v["visited_text"] = v["special_text"]
    # The same accents as text on paper_alt, which sits closer to them than the paper does, so they need more lifting.
    for key, accent in (("muted", v["muted"]), ("urgent", v["urgent"]), ("ok", v["ok"]), ("link", v["focus"]),
                        ("neutral", v["active"]), ("visited", v["special"])):
        v[key + "_alt_text"] = _on_paper(accent, v["paper_alt"], text)
    return v


def foot_values(pal, name):
    """foot's colours for one half, as 'rrggbb'. foot draws a palette colour the same as text and as background, so the
    light half's lime and sun are darkened only as far as 3:1 on the paper (the bright ones too: lifted, they could not
    read), keeping their look as backgrounds as far as they can; the selection keeps the accent as it is."""
    half, light, roles = pal[name], pal["light"], pal["roles"]
    black, cream = light["ink"], light["paper"]
    shift = palette.shift_l
    regular = [half["ink"] if name == "light" else shift(half["paper"], FOOT_BLACK_L)]
    # The light accents in both modes: terminal colours are text, and the dark accents are deepened to carry cream
    # text on chips, which leaves them too dim as text on the night page.
    regular += [light["accents"][a] for a in FOOT_NORMAL]
    regular.append(shift(cream, FOOT_WHITE_L) if name == "light" else cream)
    active = half["accents"][roles["active"]]
    out = {"background": half["paper"], "foreground": half["text"], "selection_background": active,
           "selection_foreground": palette.text_on(active, black, cream)}
    for i, hex_ in enumerate(regular):
        out["regular%d" % i] = hex_
        out["bright%d" % i] = shift(hex_, FOOT_BRIGHT_L)
    if name == "dark":
        out["bright0"] = _bright_black(half["paper"])
    else:
        for i in FOOT_LIGHT_TEXT:
            out["regular%d" % i] = out["bright%d" % i] = _on_paper(regular[i], half["paper"], half["text"])
    return {k: _bare(x) for k, x in out.items()}


def render_foot(pal, mode):
    values = {"initial_theme": mode}
    for name in MODES:
        values.update({"%s_%s" % (name, k): x for k, x in foot_values(pal, name).items()})
    return [("foot/gutter.ini", fill(_template("foot.ini"), values))]


def render_fuzzel(pal, mode):
    values = {k: _bare(x) + FUZZEL_ALPHA for k, x in half_values(pal, mode).items()}
    return [("fuzzel/gutter.ini", fill(_template("fuzzel.ini"), values))]


def render_gtk(pal, mode):
    text = fill(_template("gtk.css"), half_values(pal, mode))
    return [("gtk-3.0/gtk.css", text), ("gtk-4.0/gtk.css", text)]


def render_thunar(pal, mode):
    text = fill(_template("thunar.css"), half_values(pal, mode))
    return [("gtk-3.0/thunar.css", text), ("gtk-4.0/thunar.css", text)]


def render_qt(pal, mode):
    values = half_values(pal, mode)
    icons = "Papirus-Light" if mode == "light" else "Papirus-Dark"
    return [("qtengine/gutter.colors", fill(_template("qt.colors"), values)),
            ("qtengine/config.json", fill(_template("qtengine.json"), {"icon_theme": icons}))]


def render_btop(pal, mode):
    return [("btop/themes/gutter.theme", fill(_template("btop.theme"), half_values(pal, mode)))]


def render_deezer(pal, mode):
    values = half_values(pal, mode)
    values.update(deezer.extra(values))
    return [("deezer/gutter.css", fill(_template("deezer.css"), values))]


RENDERERS = {"foot": render_foot, "fuzzel": render_fuzzel, "gtk": render_gtk, "thunar": render_thunar,
             "qt": render_qt, "btop": render_btop, "deezer": render_deezer}


def render_all(pal, mode):
    """{app: [(path relative to XDG_CONFIG_HOME, text)]} for every app, from a version 2 palette in `mode`."""
    if mode not in MODES:
        raise ValueError("unknown mode %r" % (mode,))
    return {app: render(pal, mode) for app, render in RENDERERS.items()}


# --- validation ---------------------------------------------------------------------------------

HALF_KEYS = ("ink", "paper", "text")
HEX = re.compile(r"#[0-9a-fA-F]{6}")
ROLES = ROLE_KEYS + ("focusBorder",)


def validate(pal):
    """Raises ValueError with a readable message unless pal is a version 2 palette that render_all can use."""
    if not isinstance(pal, dict) or pal.get("version") != 2:
        raise ValueError("the palette is not version 2")
    roles = pal.get("roles")
    if not isinstance(roles, dict):
        raise ValueError("the palette has no roles")
    for role in ROLES:
        if not isinstance(roles.get(role), str):
            raise ValueError("the palette has no role %r" % role)
    for name in MODES:
        half = pal.get(name)
        if not isinstance(half, dict):
            raise ValueError("the palette has no %s half" % name)
        for key in HALF_KEYS:
            if not (isinstance(half.get(key), str) and HEX.fullmatch(half[key])):
                raise ValueError("the %s half has no colour %r" % (name, key))
        accents = half.get("accents")
        if not isinstance(accents, dict):
            raise ValueError("the %s half has no accents" % name)
        for accent in palette.ACCENTS + sorted({roles[r] for r in ROLES} - set(palette.ACCENTS)):
            if not (isinstance(accents.get(accent), str) and HEX.fullmatch(accents[accent])):
                raise ValueError("the %s half has no accent %r" % (name, accent))


# --- writing and signalling ---------------------------------------------------------------------

GTK_THEMES = {"light": "adw-gtk3", "dark": "adw-gtk3-dark"}
COLOR_SCHEMES = {"light": "prefer-light", "dark": "prefer-dark"}
ICON_THEMES = {"light": "Papirus-Light", "dark": "Papirus-Dark"}
FOOT_SIGNALS = {"light": "-USR2", "dark": "-USR1"}
BTOP_THEME = "gutter"
DEEZER_FLATPAK_DIR = "~/.var/app/dev.aunetx.deezer/config"
COLOR_THEME_LINE = re.compile(r"^[ \t]*color_theme[ \t]*=.*$", re.MULTILINE)


def icons_dir():
    return Path(os.environ.get("GUTTER_ICONS_DIR") or "/usr/share/icons")


def set_color_theme(conf_text):
    """btop.conf text with `color_theme = "gutter"`: the first existing color_theme line replaced, else appended."""
    line = 'color_theme = "%s"' % BTOP_THEME
    if COLOR_THEME_LINE.search(conf_text):
        return COLOR_THEME_LINE.sub(lambda m: line, conf_text, count=1)
    if conf_text and not conf_text.endswith("\n"):
        conf_text += "\n"
    return conf_text + line + "\n"


def _write_file(path, text):
    """Writes one file, a symlink's target rather than the link, keeping the file's mode."""
    dest = real(path)
    mode = stat.S_IMODE(dest.stat().st_mode) if dest.exists() else 0o644
    write_atomic(dest, text, ".gutter-", mode)


def _put(config_dir, rel, text):
    """Writes one file under config_dir; a file that is not Gutter's own is backed up first."""
    path = config_dir / rel
    if rel not in GENERATED:
        back_up_once(path)
    _write_file(path, text)


def _write(config_dir, files):
    for rel, text in files:
        _put(config_dir, rel, text)


def deezer_dir(config_dir):
    """Where Deezer reads gutter.css from: the Flatpak's own config folder (its sandbox cannot read ~/.config) when that
    exists, else config_dir/deezer when that exists, else None (Deezer is not installed, or never run)."""
    flatpak = Path(os.environ.get("GUTTER_DEEZER_FLATPAK_DIR") or os.path.expanduser(DEEZER_FLATPAK_DIR))
    if flatpak.is_dir():
        return flatpak
    plain = config_dir / "deezer"
    return plain if plain.is_dir() else None


def _write_deezer(dest_dir, files):
    for rel, text in files:     # Gutter's own file with its own name: nothing to back up
        _write_file(dest_dir / Path(rel).name, text)


def _write_btop(config_dir, files):
    rel = "btop/btop.conf"
    try:
        old = real(config_dir / rel).read_text(encoding="utf-8")
    except FileNotFoundError:
        old = ""
    _write(config_dir, files)
    _put(config_dir, rel, set_color_theme(old))


def _command(run, argv, ok=(0,)):
    """True when argv ran and exited with one of ok; a command that cannot be started is a failure."""
    try:
        return run(argv, capture_output=True, text=True).returncode in ok
    except OSError:
        return False


def _gsettings(run, mode):
    """Sets the GTK theme, colour scheme and, when installed, icon theme; a missing gsettings is not a failure."""
    keys = [("gtk-theme", GTK_THEMES[mode]), ("color-scheme", COLOR_SCHEMES[mode])]
    if (icons_dir() / ICON_THEMES[mode]).is_dir():
        keys.append(("icon-theme", ICON_THEMES[mode]))
    ok = True
    for key, value in keys:
        try:
            result = run(["gsettings", "set", "org.gnome.desktop.interface", key, value],
                         capture_output=True, text=True)
        except FileNotFoundError:
            return True
        except OSError:
            return False
        ok = ok and result.returncode == 0
    return ok


def apply(pal, mode, config_dir, run=subprocess.run):
    """Writes every app's config under config_dir, then signals the running apps and sets the GTK settings.
    Returns the names of the apps that failed, in render order. A failed write marks only that app, which is then
    not signalled; the others carry on. btop is skipped entirely when config_dir/btop does not exist; Deezer is written
    to its Flatpak config folder or config_dir/deezer, whichever exists (see deezer_dir), and skipped when neither does;
    it reloads the file itself, so nothing is signalled."""
    validate(pal)
    config_dir = Path(config_dir)
    rendered = render_all(pal, mode)
    if not (config_dir / "btop").is_dir():
        del rendered["btop"]
    deezer_to = deezer_dir(config_dir)
    if deezer_to is None:
        del rendered["deezer"]
    writers = {"btop": _write_btop, "deezer": lambda _, files: _write_deezer(deezer_to, files)}
    failed = []
    for app, files in rendered.items():
        try:
            writers.get(app, _write)(config_dir, files)
        except (OSError, UnicodeError):  # a btop.conf that is not UTF-8 is that app's failure too
            failed.append(app)
    signals = [("foot", lambda: _command(run, ["pkill", FOOT_SIGNALS[mode], "-x", "foot"], ok=(0, 1))),
               ("gtk", lambda: _gsettings(run, mode)),
               ("btop", lambda: _command(run, ["pkill", "-USR2", "-x", "btop"], ok=(0, 1)))]
    for app, signal in signals:
        if app in rendered and app not in failed and not signal():
            failed.append(app)
    return [app for app in rendered if app in failed]


# --- command line -------------------------------------------------------------------------------

def config_home():
    return Path(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"))


def main(argv=None):
    ap = argparse.ArgumentParser(description="Write the app configs from the palette and switch the running apps.")
    ap.add_argument("--palette", type=Path, required=True)
    ap.add_argument("--mode", choices=MODES, required=True)
    args = ap.parse_args(argv)
    try:
        try:
            pal = json.loads(args.palette.read_text())
        except OSError as e:
            raise ValueError("cannot read palette %s: %s" % (args.palette, e.strerror or e))
        except ValueError as e:
            raise ValueError("cannot read palette %s: %s" % (args.palette, e))
        failed = apply(pal, args.mode, config_home())
    except (OSError, ValueError) as e:
        print("apps: %s" % e, file=sys.stderr)
        return 1
    if failed:
        print("apps: failed: %s" % ",".join(failed), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
