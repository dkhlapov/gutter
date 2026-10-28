#!/usr/bin/env bash
# Loads the shell for a few seconds and fails if the log contains a QML error.
# A running gutter is stopped for the run and started again afterwards.
set -uo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
seconds="${1:-6}"
log="$(mktemp)"

if pgrep -f '^qs -c gutter( |$)' >/dev/null; then
    trap 'qs -c gutter -n -d >/dev/null 2>&1' EXIT
fi
qs -c gutter kill >/dev/null 2>&1 || true
# GUTTER_SMOKE=1: ThemeMode neither runs `gutter theme apply` nor writes theme-auto.json, so a check run never
# themes the live apps or touches the real state files (this runs against the real HOME).
GUTTER_SMOKE=1 timeout "$seconds" qs -p "$dir" >"$log" 2>&1
status=$?

# 124 is the normal timeout kill; 0 a clean exit. Anything else is a crash.
if [ "$status" -ne 124 ] && [ "$status" -ne 0 ]; then
    cat "$log"
    echo "smoke: FAIL (qs exited with status $status; full log: $log)"
    exit 1
fi
if grep -E "ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign|Cannot read property" "$log"; then
    echo "smoke: FAIL (full log: $log)"
    exit 1
fi
echo "smoke: OK"
rm -f "$log"
