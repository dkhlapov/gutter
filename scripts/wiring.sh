#!/usr/bin/env bash
# Runs tests/wiring/shell.qml in Quickshell, offscreen: SectionHost (pill/SectionHost.qml) maps a section name to
# pill/sections/<Name>Section.qml, for every section in lib/config.js, and reports no file, a loaded file and a
# broken one; Theme (theme/Theme.qml) serves ink, text, paper, textOnInk and the accents from the half of
# palette.json that theme.json names, follows a change of mode and falls back to the default for an invalid half
# or theme.json. Like scripts/fit.sh, it runs from a scratch config root that links the repo's folders, here with
# its own pill/sections (the repo's sections plus a broken one) and its own XDG_STATE_HOME, so the real state
# folder is never read or written.
set -uo pipefail
# A scratch root has no tools/gutter: ThemeMode would report "cannot run" to the real desktop.
export GUTTER_NO_NOTIFY=1
dir="$(cd "$(dirname "$0")/.." && pwd)"
root="$(mktemp -d)"
log="$root/log"
trap 'rm -rf "$root"' EXIT

for d in bar components dev ipc launcher lib scripts settings theme wallpaper; do
    ln -s "$dir/$d" "$root/$d"
done
mkdir "$root/services" "$root/config" "$root/pill" "$root/pill/sections"
for f in "$dir"/services/*; do
    ln -s "$f" "$root/services/"
done
for f in "$dir"/pill/*; do
    [ "$(basename "$f")" = sections ] || ln -s "$f" "$root/pill/"
done
for f in "$dir"/pill/sections/*; do
    ln -s "$f" "$root/pill/sections/"
done
printf 'import QtQuick\nItem {\n    this is not QML\n}\n' >"$root/pill/sections/BrokenSection.qml"
cp "$dir/tests/wiring/shell.qml" "$dir/tests/wiring/palette.json" "$root/"

state="$root/state"
mkdir -p "$state/gutter"
cp "$dir/tests/wiring/palette.json" "$state/gutter/palette.json"
echo '{"version": 1, "mode": "light"}' >"$state/gutter/theme.json"

XDG_CONFIG_HOME="$root/config" XDG_STATE_HOME="$state" WIRING_STATE="$state" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
    timeout 60 qs -p "$root" >"$log" 2>&1
grep -E 'wiring: ' "$log" | sed -E 's/^.*(wiring: )/\1/'
# The broken section's own warning is expected, and so is the error text in it.
errors='ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign'
if grep -v 'gutter: section broken' "$log" | grep -qE "$errors"; then
    grep -v 'gutter: section broken' "$log" | grep -E "$errors"
    echo "wiring: FAIL (QML errors)"
    exit 1
fi
if ! grep -q 'wiring: OK' "$log"; then
    grep -q 'wiring: FAIL' "$log" || { echo "wiring: FAIL (no result; qs output follows)"; tail -n 20 "$log"; }
    exit 1
fi
