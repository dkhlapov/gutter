#!/usr/bin/env bash
# Text on paper is Theme.text; Theme.ink is for lines (outlines, borders, ink plates). Every `color: Theme.ink`
# in the QML under <root> must be listed in <root>/scripts/ink-lines.txt, and every entry there must still match
# a line. An entry is `<path>: <enclosing object> > <trimmed line>`, the enclosing object being the nearest
# preceding line at a smaller indent that opens a block (ends in `{`, a trailing // comment ignored, or is
# `[property:] Type { id: x`), so a Text { color: Theme.ink } is not covered by an entry written for a Rectangle {
# color: Theme.ink }. A one-line `Rectangle { color: Theme.ink }` has no such line of its own and is keyed on the
# object around it. Text, not line numbers, so edits elsewhere in a file keep it valid. Entries are a multiset:
# a hit consumes one, so n identical hits need n entries.
set -euo pipefail
export LC_ALL=C
root="$(cd "${1:?usage: ink-lines.sh <root>}" && pwd)"
list="$root/scripts/ink-lines.txt"

cd "$root"
# Through a file, not process substitution, which would swallow git's exit status. NUL-separated, so file names
# need no quoting.
names="$(mktemp)"
trap 'rm -f "$names"' EXIT
git ls-files -z -co --exclude-standard '*.qml' >"$names"
files=()
while IFS= read -r -d '' f; do
    # Tracked but deleted from the worktree is not an error. "./": a name with = would be taken for an awk variable.
    if [ -f "$f" ]; then files+=("./$f"); fi
done <"$names"

awk '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    FILENAME == ARGV[1] { # the allow-list
        if ($0 !~ /^[ \t]*(#|$)/) allowed[trim($0)]++
        next
    }
    FNR == 1 { depth = 0; name = FILENAME; sub(/^\.\//, "", name) }
    /^[ \t]*(\/\/|\r?$)/ { next }
    {
        match($0, /^[ \t]*/)
        ind = RLENGTH
        text = trim($0)
        code = text
        sub(/[ \t]*\/\/.*$/, "", code)
        while (depth > 0 && indent[depth] >= ind) depth--
        if (text ~ /(^|[^A-Za-z0-9_])(color|textColor):[ \t]*Theme\.ink([^A-Za-z0-9_]|$)/) {
            key = name ": " (depth > 0 ? head[depth] : "(top level)") " > " text
            hits[key]++
            if (allowed[key] > 0) allowed[key]--
            else {
                printf "lint: Theme.ink used for text at %s:%d (use Theme.text, or add \"%s\" to scripts/ink-lines.txt)\n", name, FNR, key > "/dev/stderr"
                bad = 1
            }
        }
        if (code ~ /\{$/ || code ~ /^([A-Za-z_][A-Za-z0-9_.]*:[ \t]*)?[A-Za-z][A-Za-z0-9_.]*[ \t]*\{[ \t]*id:[ \t]*[A-Za-z_][A-Za-z0-9_]*$/) {
            depth++; indent[depth] = ind; head[depth] = code
        }
    }
    END {
        for (key in allowed) if (allowed[key] > 0) {
            if (hits[key] > 0) printf "lint: scripts/ink-lines.txt lists this line %d time(s) too many: %s\n", allowed[key], key | "sort >&2"
            else printf "lint: stale entry in scripts/ink-lines.txt, no such line in the tree: %s\n", key | "sort >&2"
            bad = 1
        }
        exit bad
    }' "$list" "${files[@]}"
