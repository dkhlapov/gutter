#!/usr/bin/env bash
# Runs tests/pills/shell.qml in Quickshell, offscreen: every pill of the top bars (workspace, tray, status, theme
# and power cells) must be Theme.pillHeight high, and the ones with only a glyph or an icon must be squares. Like
# scripts/fit.sh, it runs from a scratch config root that links the repo's folders, with the services in
# tests/pills/stubs (audio, network, Bluetooth, tray) standing in for the real ones so every cell shows.
set -uo pipefail
# A scratch root has no tools/gutter: ThemeMode would report "cannot run" to the real desktop.
export GUTTER_NO_NOTIFY=1
dir="$(cd "$(dirname "$0")/.." && pwd)"
root="$(mktemp -d)"
log="$root/log"
trap 'rm -rf "$root"' EXIT

for d in bar components dev ipc launcher lib pill scripts settings theme wallpaper; do
    ln -s "$dir/$d" "$root/$d"
done
mkdir "$root/services" "$root/config"
for f in "$dir"/services/*; do
    ln -s "$f" "$root/services/"
done
for f in "$dir"/tests/pills/stubs/*.qml; do
    ln -sf "$f" "$root/services/"
done
cp "$dir/tests/pills/shell.qml" "$root/shell.qml"

XDG_CONFIG_HOME="$root/config" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
    timeout 60 qs -p "$root" >"$log" 2>&1
grep -E 'pills: ' "$log" | sed -E 's/^.*(pills: )/\1/'
if grep -qE 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"; then
    grep -E 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"
    echo "pills: FAIL (QML errors)"
    exit 1
fi
grep -q 'pills: OK' "$log"
