#!/usr/bin/env bash
# Runs tests/components/shell.qml in Quickshell, offscreen: the shared components' contracts that no other check
# covers (InkBox and SpeechBubble size from their visible content, InkSlider's wheel and grab). Like
# scripts/scrollbar.sh, it runs from a scratch config root that links the repo's folders, the services being the real
# ones.
set -uo pipefail
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
cp "$dir/tests/components/shell.qml" "$root/shell.qml"

XDG_CONFIG_HOME="$root/config" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
    timeout 60 qs -p "$root" >"$log" 2>&1
grep -E 'components: ' "$log" | sed -E 's/^.*(components: )/\1/'
if grep -qE 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"; then
    grep -E 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"
    echo "components: FAIL (QML errors)"
    exit 1
fi
grep -q 'components: OK' "$log"
