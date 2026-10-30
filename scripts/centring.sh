#!/usr/bin/env bash
# Runs tests/centring/shell.qml in Quickshell, offscreen: the transport's visible buttons must be centred on the
# progress bar in the overview's media card and the music section, with and without shuffle and repeat. Like
# scripts/fit.sh, it runs from a scratch config root that links the repo's folders, with the Media service in
# tests/centring/stubs standing in for the real one.
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
for f in "$dir"/tests/centring/stubs/*.qml; do
    ln -sf "$f" "$root/services/"
done
cp "$dir/tests/centring/shell.qml" "$root/shell.qml"

XDG_CONFIG_HOME="$root/config" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
    timeout 60 qs -p "$root" >"$log" 2>&1
grep -E 'centring: ' "$log" | sed -E 's/^.*(centring: )/\1/'
if grep -qE 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"; then
    grep -E 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"
    echo "centring: FAIL (QML errors)"
    exit 1
fi
grep -q 'centring: OK' "$log"
