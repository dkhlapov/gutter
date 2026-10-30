#!/usr/bin/env bash
# Runs tests/sides/shell.qml in Quickshell, offscreen: the real pill with none, the music pill, the Claude pill and
# both beside the island. The island must stay centred on its surface, the side pills must fit inside the surface
# and clear of the island, and nothing in them may be drawn outside their outline. Like scripts/fit.sh, it runs from
# a scratch config root that links the repo's folders, with the Media and Agents services of tests/fit/stubs
# standing in for the real ones.
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
for f in "$dir"/tests/fit/stubs/*.qml; do
    ln -sf "$f" "$root/services/"
done
cp "$dir/tests/sides/shell.qml" "$root/shell.qml"

XDG_CONFIG_HOME="$root/config" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
    timeout 90 qs -p "$root" >"$log" 2>&1
grep -E 'sides: ' "$log" | sed -E 's/^.*(sides: )/\1/'
if grep -qE 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"; then
    grep -E 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"
    echo "sides: FAIL (QML errors)"
    exit 1
fi
grep -q 'sides: OK' "$log"
