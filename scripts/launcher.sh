#!/usr/bin/env bash
# Runs tests/launcher/shell.qml in Quickshell, offscreen: the launcher service (services/Launcher.qml) in dry run
# guards `move`, `complete`, `activate` and `choose` by mode and arguments, runs only commands that are ready, asks
# twice for one that ends the session, and starts the selection over with a new query or mode. Like scripts/fit.sh,
# it runs from a scratch config root that links the repo's folders, the services being the real ones. The state
# directory is the scratch one, and a dry run runs no action.
set -uo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
root="$(mktemp -d)"
log="$root/log"
trap 'rm -rf "$root"' EXIT

for d in bar components dev ipc launcher lib pill scripts settings theme wallpaper; do
    ln -s "$dir/$d" "$root/$d"
done
mkdir "$root/services" "$root/config" "$root/state"
for f in "$dir"/services/*; do
    ln -s "$f" "$root/services/"
done
cp "$dir/tests/launcher/shell.qml" "$root/shell.qml"

GUTTER_LAUNCHER_DRY_RUN=1 GUTTER_POWER_DRY_RUN=1 XDG_STATE_HOME="$root/state" XDG_CONFIG_HOME="$root/config" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
    timeout 60 qs -p "$root" >"$log" 2>&1
grep -E 'launcher: ' "$log" | sed -E 's/^.*(launcher: )/\1/'
# The check's own FAIL lines can quote an error message; only the log's other lines count as QML errors.
errors="$(grep -E 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log" | grep -v 'launcher: FAIL')"
if [ -n "$errors" ]; then
    echo "$errors"
    echo "launcher: FAIL (QML errors)"
    exit 1
fi
grep -q 'launcher: OK' "$log" && exit 0
grep -q 'launcher: FAIL' "$log" || echo "launcher: FAIL (no result)"
exit 1
