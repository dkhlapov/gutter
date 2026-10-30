#!/usr/bin/env bash
# Runs tests/fit/shell.qml in Quickshell, offscreen: the collapsed pill in every face, at rest and while its box
# animates, must draw nothing outside its ink box; so must the launcher box and the session screen, at a few
# scales of the window; so must a notification card of the history, which also shows its app name whole (or cut
# short for the age) with the age right after it and clear of the dismiss button. The check runs from a scratch
# config root that links the repo's folders, with the services in tests/fit/stubs standing in for the real ones.
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
cp "$dir/tests/fit/shell.qml" "$root/shell.qml"

XDG_CONFIG_HOME="$root/config" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
    timeout 60 qs -p "$root" >"$log" 2>&1
grep -E '^.*fit: ' "$log" | sed -E 's/^.*(fit: )/\1/'
if grep -qE 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"; then
    grep -E 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"
    echo "fit: FAIL (QML errors)"
    exit 1
fi
grep -q 'fit: OK' "$log"
