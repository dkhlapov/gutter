#!/usr/bin/env bash
# Runs tests/components/shell.qml in Quickshell, offscreen: the shared components' contracts that no other check
# covers (InkBox and SpeechBubble size from their visible content, InkSlider's wheel and grab, InkMenu's focus
# going back when a Loader tears it down). Like scripts/scrollbar.sh, with which it shares scripts/scratch-root.sh,
# it runs from a scratch config root that links the repo's folders, the services being the real ones, and with a
# private home, XDG folders, PATH and bus (like scripts/auth.sh and scripts/lock-nested.sh), so Theme and Settings
# never read or create the account's own palette, theme state or config, and neither the caller's tools nor the
# session bus is reachable (the bus address points at a socket nobody listens on). Everything else the caller's
# environment holds is dropped too (`env -i`), so a service imported into this harness later cannot reach the
# session through a variable nobody thought to scrub; only what the run lists below is passed on.
set -uo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$dir/scripts/scratch-root.sh"
scratch_root "$dir" components
qs_bin="$(command -v qs)"
mkdir "$root/home" "$root/bin"
mkdir -m 700 "$root/run"
# The only tools on the PATH: bash and mkdir (the settings make their folder).
ln -s "$(command -v bash)" "$root/bin/bash"
ln -s "$(command -v mkdir)" "$root/bin/mkdir"

timeout 60 env -i PATH="$root/bin" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$root/run/bus" HOME="$root/home" XDG_CONFIG_HOME="$root/home/.config" XDG_STATE_HOME="$root/home/.local/state" \
    XDG_DATA_HOME="$root/home/.local/share" XDG_CACHE_HOME="$root/home/.cache" XDG_RUNTIME_DIR="$root/run" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
    "$qs_bin" -p "$root" >"$log" 2>&1
status=$?
grep -E 'components: ' "$log" | sed -E 's/^.*(components: )/\1/'
if grep -qE "$errors" "$log"; then
    grep -E "$errors" "$log"
    echo "components: FAIL (QML errors)"
    exit 1
fi
if grep -q 'components: OK' "$log" && [ "$status" -eq 0 ]; then
    exit 0
fi
echo "components: FAIL (Quickshell exit status $status)"
cat "$log"
exit 1
