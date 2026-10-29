#!/usr/bin/env bash
# Runs tests/components/shell.qml in Quickshell, offscreen: the shared components' contracts that no other check
# covers (InkBox and SpeechBubble size from their visible content, InkSlider's wheel and grab). Like
# scripts/scrollbar.sh, it runs from a scratch config root that links the repo's folders, the services being the real
# ones, and with a private home and XDG folders (like scripts/auth.sh), so Theme and Settings never read or create the
# account's own palette, theme state or config.
set -uo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
root="$(mktemp -d)"
log="$root/log"
trap 'rm -rf "$root"' EXIT

for d in bar components dev ipc launcher lib pill scripts settings theme wallpaper; do
    ln -s "$dir/$d" "$root/$d"
done
mkdir "$root/services" "$root/home"
mkdir -m 700 "$root/run"
for f in "$dir"/services/*; do
    ln -s "$f" "$root/services/"
done
cp "$dir/tests/components/shell.qml" "$root/shell.qml"

env HOME="$root/home" XDG_CONFIG_HOME="$root/home/.config" XDG_STATE_HOME="$root/home/.local/state" \
    XDG_DATA_HOME="$root/home/.local/share" XDG_CACHE_HOME="$root/home/.cache" XDG_RUNTIME_DIR="$root/run" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
    timeout 60 qs -p "$root" >"$log" 2>&1
grep -E 'components: ' "$log" | sed -E 's/^.*(components: )/\1/'
if grep -qE 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"; then
    grep -E 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"
    echo "components: FAIL (QML errors)"
    exit 1
fi
grep -q 'components: OK' "$log"
