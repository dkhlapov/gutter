#!/usr/bin/env bash
# Runs tests/components/shell.qml in Quickshell, offscreen: the shared components' contracts that no other check
# covers (InkBox and SpeechBubble size from their visible content, InkSlider's wheel and grab). Like
# scripts/scrollbar.sh, it runs from a scratch config root that links the repo's folders, the services being the real
# ones, and with a private home, XDG folders, PATH and bus (like scripts/auth.sh and scripts/lock-nested.sh), so Theme
# and Settings never read or create the account's own palette, theme state or config, and neither the caller's tools
# nor the session bus is reachable (the bus address points at a socket nobody listens on).
set -uo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
root="$(mktemp -d)"
log="$root/log"
trap 'rm -rf "$root"' EXIT

for d in bar components dev ipc launcher lib pill scripts settings theme wallpaper; do
    ln -s "$dir/$d" "$root/$d"
done
qs_bin="$(command -v qs)"
mkdir "$root/services" "$root/home" "$root/bin"
mkdir -m 700 "$root/run"
# The only tools on the PATH: bash and mkdir (the settings make their folder).
ln -s "$(command -v bash)" "$root/bin/bash"
ln -s "$(command -v mkdir)" "$root/bin/mkdir"
for f in "$dir"/services/*; do
    ln -s "$f" "$root/services/"
done
cp "$dir/tests/components/shell.qml" "$root/shell.qml"

timeout 60 env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE PATH="$root/bin" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$root/run/bus" HOME="$root/home" XDG_CONFIG_HOME="$root/home/.config" XDG_STATE_HOME="$root/home/.local/state" \
    XDG_DATA_HOME="$root/home/.local/share" XDG_CACHE_HOME="$root/home/.cache" XDG_RUNTIME_DIR="$root/run" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
    "$qs_bin" -p "$root" >"$log" 2>&1
status=$?
grep -E 'components: ' "$log" | sed -E 's/^.*(components: )/\1/'
if grep -qE 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"; then
    grep -E 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"
    echo "components: FAIL (QML errors)"
    exit 1
fi
if grep -q 'components: OK' "$log" && [ "$status" -eq 0 ]; then
    exit 0
fi
echo "components: FAIL (Quickshell exit status $status)"
cat "$log"
exit 1
