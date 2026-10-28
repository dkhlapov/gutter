#!/usr/bin/env bash
# Claude Code statusLine bridge (installed by install-agent-hooks.sh). Claude Code passes the session's
# status JSON on stdin; its `rate_limits` (5-hour and weekly use, Pro/Max only) are the only local source
# of plan limits, so the last ones seen are kept in $XDG_STATE_HOME/gutter/claude-limits.json for the
# pill. Only the CLI runs a status line (the Desktop app does not), so the file ages while only Desktop is used.
# A status line that was configured before the install still runs and prints as before.
input="$(cat)"
dir="${XDG_STATE_HOME:-$HOME/.local/state}/gutter"
mkdir -p "$dir" 2>/dev/null

if command -v jq >/dev/null; then
    limits="$(printf '%s' "$input" | jq -c 'select(.rate_limits != null) | { t: (now * 1000 | floor), rate_limits }' 2>/dev/null)"
    if [ -n "$limits" ]; then
        # A temp file per call: sessions update their status lines at the same time.
        tmp="$(mktemp "$dir/claude-limits.json.XXXXXX" 2>/dev/null)" &&
            { printf '%s\n' "$limits" >"$tmp" && mv -f "$tmp" "$dir/claude-limits.json" || rm -f "$tmp"; }
    fi
    if [ -f "$dir/statusline-chain.json" ]; then
        cmd="$(jq -r '.command // empty' "$dir/statusline-chain.json" 2>/dev/null)"
        [ -n "$cmd" ] && printf '%s' "$input" | sh -c "$cmd"
    fi
fi
exit 0
