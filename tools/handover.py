#!/usr/bin/env python3
"""Wires foot and fuzzel to Gutter's colour files (`install`). Standard library only.

`install` works in the config folder (--config, else $XDG_CONFIG_HOME, else HOME/.config). It backs foot.ini and
fuzzel.ini up once (as `<file>.pre-gutter`), creates an empty foot/gutter.ini and fuzzel/gutter.ini when missing (both
programs refuse an include of a missing file), makes each config include its file, copies foot's alpha, alpha-mode and
blur lines from `[colors-dark]` to `[colors-light]`, and drops fuzzel.ini's own `[colors]` and `[border]` sections
(later keys win, so they would override Gutter's).
A config that is not there is skipped. It plans every edit before it changes anything, and is idempotent.
`back_up_once` is the backup rule, and `gutter theme apply` (tools/apps.py) uses it too before it first writes a file
that is not Gutter's own, so whichever runs first records the original, and a file apply created gets the `-absent`
marker. The backups stay on disk; restoring one is a manual `mv`.
"""
import argparse
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

from atomicio import write_atomic

BACKUP = ".pre-gutter"
ABSENT = ".pre-gutter-absent"
INCLUDED = (("foot/foot.ini", "foot/gutter.ini"), ("fuzzel/fuzzel.ini", "fuzzel/gutter.ini"))   # config, its include
GENERATED = ("foot/gutter.ini", "fuzzel/gutter.ini", "qtengine/gutter.colors", "btop/themes/gutter.theme")
HEADER = re.compile(r"^\s*\[([^\]]+)\]\s*$")
KEEP_IN_LIGHT = re.compile(r"^\s*(alpha|alpha-mode|blur)\s*=")


class HandoverError(Exception):
    pass


# --- INI text -----------------------------------------------------------------------------------

def split_lines(text):
    """Lines of text with their endings, split at "\\n" only: "\\r\\n" stays on its line, and a form feed or other
    separator does not split one (str.splitlines would)."""
    return re.findall(r"[^\n]*\n|[^\n]+", text)


def eol(text):
    """The line ending the file mostly uses: CRLF when more lines end in CRLF than in a bare LF, else LF."""
    crlf = text.count("\r\n")
    return "\r\n" if crlf > text.count("\n") - crlf else "\n"


def sections(text):
    """Splits text into [(name, lines)]: the main block first (name None), then each `[name]` with its header line."""
    out = [(None, [])]
    for line in split_lines(text):
        m = HEADER.match(line.rstrip("\r\n"))
        if m:
            out.append((m.group(1).strip(), []))
        out[-1][1].append(line)
    return out


def join(blocks, nl="\n"):
    """The inverse of `sections`; a block's last line gets its newline back when another block follows it."""
    lines = []
    for _, block in blocks:
        if lines and block and not lines[-1].endswith("\n"):
            lines[-1] += nl
        lines.extend(block)
    return "".join(lines)


def last_content(lines):
    """Index of the last line that is not blank, or -1."""
    for i in range(len(lines) - 1, -1, -1):
        if lines[i].strip():
            return i
    return -1


def add_include(text, include):
    """Adds `include` as the last line of the main block (before the first `[section]`), once."""
    blocks = sections(text)
    main = blocks[0][1]
    if any(line.strip() == include for line in main):
        return text
    nl = eol(text)
    at = last_content(main) + 1
    if at > 0 and not main[at - 1].endswith("\n"):
        main[at - 1] += nl
    new = [include + nl]
    if at == 0 and len(blocks) > 1:
        new.append(nl)
    main[at:at] = new
    return join(blocks, nl)


def drop_sections(text, names):
    """Deletes every section called one of `names`, header to the next header. When the last section goes, the
    blank lines that set it apart from the one before go too."""
    blocks = sections(text)
    kept = [b for b in blocks if b[0] not in names]
    if kept and kept[-1] is not blocks[-1]:
        last = kept[-1][1]
        while last and not last[-1].strip():
            last.pop()
    return join(kept, eol(text))


def add_colors_light(text):
    """Adds a `[colors-light]` with the alpha, alpha-mode and blur lines of `[colors-dark]`, once."""
    blocks = sections(text)
    if any(name == "colors-light" for name, _ in blocks):
        return text
    dark = next((b for b in blocks if b[0] == "colors-dark"), None)
    if dark is None:
        return text
    nl = eol(text)
    kept = [line.strip() + nl for line in dark[1] if KEEP_IN_LIGHT.match(line)]
    if not kept:
        return text
    lines = dark[1]
    at = last_content(lines) + 1
    if not lines[at - 1].endswith("\n"):
        lines[at - 1] += nl
    lines[at:at] = [nl, "[colors-light]" + nl] + kept
    return join(blocks, nl)


# --- files --------------------------------------------------------------------------------------

def real(path):
    return Path(os.path.realpath(path))


def read(path):
    try:
        with open(real(path), encoding="utf-8", newline="") as f:
            return f.read()
    except UnicodeDecodeError:
        raise HandoverError("%s is not UTF-8 text; nothing changed" % path)


def copy_beside(src, dest):
    """Copies src (its contents, mode and times) to dest through a temp file next to it, then renames."""
    dest = Path(dest)
    fd, tmp = tempfile.mkstemp(dir=dest.parent, prefix=".gutter.")
    os.close(fd)
    try:
        shutil.copy2(src, tmp)
        os.replace(tmp, dest)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def back_up_once(f):
    """Records f before Gutter first changes it: an existing f is copied (contents, mode, times) to <f>.pre-gutter, a
    missing one gets an empty <f>.pre-gutter-absent marker (a manual restore deletes f). Nothing happens when either is
    already there, so the first record, the original, is kept."""
    f = Path(f)
    if os.path.lexists(str(f) + BACKUP) or os.path.lexists(str(f) + ABSENT):
        return
    if f.exists():
        copy_beside(f, str(f) + BACKUP)
    else:
        f.parent.mkdir(parents=True, exist_ok=True)
        Path(str(f) + ABSENT).touch()


def include_line(home, config, rel):
    """`include=...` for Gutter's file: spelled with ~ for the default config folder (what foot and fuzzel users
    write), absolute for any other XDG_CONFIG_HOME."""
    if Path(config) == Path(home) / ".config":
        return "include=~/.config/" + rel
    return "include=%s/%s" % (config, rel)


def plan(home, config):
    """[(file, new text)] for every config install edits, each computed before anything is written."""
    foot = include_line(home, config, "foot/gutter.ini")
    fuzzel = include_line(home, config, "fuzzel/gutter.ini")
    edits = []
    for rel, steps in (("foot/foot.ini", (lambda t: add_include(t, foot), add_colors_light)),
                       ("fuzzel/fuzzel.ini", (lambda t: add_include(t, fuzzel),
                                              lambda t: drop_sections(t, ("colors", "border"))))):
        path = Path(config) / rel
        if path.exists():
            text = read(path)
            for step in steps:
                text = step(text)
            edits.append((path, text))
    return edits


def install(home, config=None):
    config = Path(config or os.environ.get("XDG_CONFIG_HOME") or Path(home) / ".config")
    edits = plan(home, config)
    for f, _ in edits:
        back_up_once(f)
    for conf, included in INCLUDED:
        if (config / conf).exists() and not os.path.lexists(config / included):
            write_atomic(config / included, "", ".gutter.")
    for f, text in edits:
        if read(f) == text:
            continue
        write_atomic(real(f), text, ".gutter.", real(f).stat().st_mode & 0o7777)


def main(argv=None):
    parser = argparse.ArgumentParser(prog="handover", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("install")
    p.add_argument("--home", required=True)
    p.add_argument("--config", help="the config folder (default: $XDG_CONFIG_HOME, else HOME/.config)")
    p.add_argument("--state", help="accepted for the installer's sake; unused")
    args = parser.parse_args(argv)
    try:
        install(args.home, args.config)
    except (HandoverError, OSError) as e:
        print("handover: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
