#!/usr/bin/env bash
# Runs tests/components/shell.qml in Quickshell, offscreen: the shared components' contracts that no other check
# covers (InkBox and SpeechBubble size from their visible content, InkSlider's wheel and grab, InkMenu's focus
# going back when a Loader tears it down). Like scripts/scrollbar.sh, with which it shares scripts/scratch-root.sh,
# it runs from a scratch config root that links the repo's folders, the services being the real ones, and with a
# private home, XDG folders, PATH and bus (like scripts/auth.sh and scripts/lock-nested.sh), so Theme and Settings
# never read or create the account's own palette, theme state or config, and neither the caller's tools nor the
# session bus is reachable (the bus address points at a socket nobody listens on). Everything else the caller's
# environment holds is dropped too (`env -i`), so a service imported into this harness later cannot reach the
# session through a variable nobody thought to scrub.
set -uo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$dir/scripts/scratch-root.sh"
scratch_root "$dir" components

scratch_run 60
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
