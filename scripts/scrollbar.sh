#!/usr/bin/env bash
# Runs tests/scrollbar/shell.qml in Quickshell, offscreen: the shared scroll bar (components/InkScrollBar.qml) shows while its
# list scrolls and not otherwise, its thumb tracks the list and dragging it scrolls, and a CaptionBox with a lone tab
# draws a caption that ignores clicks. Like scripts/fit.sh, it runs from a scratch config root that links the repo's
# folders, the services being the real ones (scripts/scratch-root.sh makes the root).
set -uo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$dir/scripts/scratch-root.sh"
scratch_root "$dir" scrollbar
mkdir "$root/config"

XDG_CONFIG_HOME="$root/config" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
    timeout 60 qs -p "$root" >"$log" 2>&1
grep -E 'scrollbar: ' "$log" | sed -E 's/^.*(scrollbar: )/\1/'
if grep -qE "$errors" "$log"; then
    grep -E "$errors" "$log"
    echo "scrollbar: FAIL (QML errors)"
    exit 1
fi
grep -q 'scrollbar: OK' "$log"
