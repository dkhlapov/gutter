#!/usr/bin/env bash
# Screenshots the pill on the focused monitor for visual checks.
#   scripts/shot.sh <section> [out.png]   opens that tab, captures the panel, closes it again
#   scripts/shot.sh pill [out.png]        captures the compact pill as it is right now
# SHOT_SCREEN=<monitor> uses that monitor instead of the focused one (the panel opens there without
# moving focus), e.g. while the focused monitor shows a fullscreen window and the pill is hidden.
# SHOT_WAIT=<seconds> keeps the panel open longer before the capture (default 1.5), e.g. for graphs.
set -euo pipefail
what="${1:?usage: shot.sh <section|pill> [out.png]}"
out="${2:-${TMPDIR:-/tmp}/gutter-$what.png}"
screen="${SHOT_SCREEN:-$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')}"
read -r mx my mw scale < <(hyprctl monitors -j | jq -r --arg s "$screen" '.[] | select(.name == $s) | "\(.x) \(.y) \(.width) \(.scale)"')
lw=$(awk -v w="$mw" -v s="$scale" 'BEGIN { printf "%d", w / s }')
if [ "$what" = pill ]; then
    w=480
    h=70
else
    w=1090
    h=440
    qs -c gutter ipc call gutter openOn "$screen" "$what" >/dev/null
    sleep "${SHOT_WAIT:-1.5}"
fi
grim -g "$((mx + (lw - w) / 2)),$my ${w}x$h" "$out"
[ "$what" = pill ] || qs -c gutter ipc call gutter close >/dev/null
echo "$out"
