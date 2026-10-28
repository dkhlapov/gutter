#!/usr/bin/env bash
# Lints all QML against Quickshell's generated module tree. Fails only on warnings missing from
# scripts/lint-baseline.txt (the baseline records known qmllint false positives: Quickshell's
# generated qmldir singletons, PanelWindow not creatable). `--update` rewrites the baseline.
set -euo pipefail
export LC_ALL=C # one sort order for the baseline, whatever the locale
dir="$(cd "$(dirname "$0")/.." && pwd)"
baseline="$dir/scripts/lint-baseline.txt"

# A section folder is imported with a bare `import "<sub>"`; a section loaded by SectionHost cannot list the
# folder itself, so every .qml file in it needs a line in the folder's hand-written qmldir (R37).
missing=0
for sub in "$dir"/pill/sections/*/; do
    [ -d "$sub" ] || continue
    for f in "$sub"*.qml; do
        [ -e "$f" ] || continue
        name="$(basename "$f" .qml)"
        if [ ! -f "${sub}qmldir" ]; then
            echo "lint: ${sub#"$dir"/} has no qmldir (needed so sections can import the folder)" >&2
            missing=1
            break
        fi
        if ! grep -qE "^${name}[[:space:]]+[0-9.]+[[:space:]]+${name}\.qml\$" "${sub}qmldir"; then
            echo "lint: ${sub#"$dir"/}qmldir has no line for $name.qml (add: $name 1.0 $name.qml)" >&2
            missing=1
        fi
    done
done
if [ "$missing" -ne 0 ]; then
    exit 1
fi

# Theme.ink is for lines, not text: every `color: Theme.ink` must be listed in scripts/ink-lines.txt, and every
# entry there must still match a line.
"$dir/scripts/ink-lines.sh" "$dir"

touch "$dir/.qmlls.ini"
build="$(sed -n 's/^buildDir="\(.*\)"$/\1/p' "$dir/.qmlls.ini")"
if [ -z "$build" ] || [ ! -d "$build/qs" ]; then
    echo "lint: no Quickshell module tree yet; run scripts/smoke.sh first" >&2
    exit 1
fi

cd "$dir"
raw="$(mktemp)"
current="$(mktemp)"
mapfile -t files < <(git ls-files -co --exclude-standard '*.qml' | grep -v '^tests/')
/usr/lib/qt6/bin/qmllint -I "$build" "${files[@]}" >"$raw" 2>&1 || true
# Drop line:column so the baseline survives edits elsewhere in a file.
{ grep '^Warning:' "$raw" || true; } | sed -E 's/^(Warning: [^:]+\.qml):[0-9]+:[0-9]+:/\1:/' | sort -u >"$current"

if [ "${1:-}" = "--update" ]; then
    cp "$current" "$baseline"
    echo "lint: baseline updated ($(wc -l <"$baseline") warnings)"
    exit 0
fi

new="$(comm -13 "$baseline" "$current")"
if [ -n "$new" ]; then
    echo "$new"
    echo "lint: FAIL — new qmllint warnings (full output: $raw)"
    exit 1
fi
echo "lint: OK"
rm -f "$raw" "$current"
