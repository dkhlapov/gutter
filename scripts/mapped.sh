#!/usr/bin/env bash
# Fails if the running gutter has no layer surface on some monitor within a few seconds (e.g. right
# after smoke.sh restarted it). A monitor whose active or special workspace holds a fullscreen window
# is skipped, since the pill is meant to sit under the fullscreen window there. Skipped at once while there is no
# pill window to look for. Fails at once if hyprctl or jq fails while listing the monitors; a failing
# `hyprctl layers` in the poll loop is retried, and named if the check ends in FAIL.
set -uo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
seconds="${1:-8}"

if [ ! -f "$dir/pill/PillWindow.qml" ]; then
    echo "mapped: skipped: no gutter layer"
    exit 0
fi

# Monitors that should show a pill: those without a fullscreen window on their active or special workspace.
# A failing hyprctl or jq fails the check: an empty answer would read as "every monitor is fullscreen".
expected() {
    local workspaces monitors count
    workspaces="$(hyprctl workspaces -j)" || { echo "mapped: FAIL: hyprctl workspaces failed" >&2; return 1; }
    monitors="$(hyprctl monitors -j)" || { echo "mapped: FAIL: hyprctl monitors failed" >&2; return 1; }
    # -n and --argjson: empty or several JSON values are an error here, not an empty count.
    count="$(jq -n --argjson m "$monitors" '$m | if type == "array" then length else error("not a list") end')" ||
        { echo "mapped: FAIL: jq failed on the hyprctl output" >&2; return 1; }
    [ "$count" -gt 0 ] || { echo "mapped: FAIL: hyprctl reports no monitors" >&2; return 1; }
    jq -n -r --argjson ws "$workspaces" --argjson mons "$monitors" '
        $mons[] | .name as $n | .activeWorkspace.id as $a | (.specialWorkspace.id // 0) as $s
        | select(any($ws[]; (.id == $a or .id == $s) and .hasfullscreen) | not)
        | $n' || { echo "mapped: FAIL: jq failed on the hyprctl output" >&2; return 1; }
}

# Captured first: mapfile < <(expected) would swallow its exit status.
wanted="$(expected)" || exit 1
if [ -z "$wanted" ]; then
    echo "mapped: skipped (every monitor shows a fullscreen window)"
    exit 0
fi
mapfile -t monitors <<<"$wanted"

missing=()
layers_failed=""
for _ in $(seq $((seconds * 4))); do
    # A failing hyprctl counts as no layer, and is named if the check ends in FAIL (it may only be starting up).
    if layers="$(hyprctl layers -j)"; then layers_failed=""; else layers_failed=" (hyprctl layers failed)"; fi
    missing=()
    for mon in "${monitors[@]}"; do
        if ! jq -e --arg m "$mon" '.[$m].levels[][] | select(.namespace == "gutter")' <<<"$layers" >/dev/null 2>&1; then
            missing+=("$mon")
        fi
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        echo "mapped: OK (${monitors[*]})"
        exit 0
    fi
    sleep 0.25
done
echo "mapped: FAIL: no gutter layer on ${missing[*]}$layers_failed" >&2
exit 1
