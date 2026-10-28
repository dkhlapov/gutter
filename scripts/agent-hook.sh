#!/usr/bin/env bash
# Claude Code hook for Gutter's agent tracker: appends one JSON line per hook call to
# $XDG_RUNTIME_DIR/gutter/agents.jsonl. It must never slow down or fail Claude Code, so every
# error is swallowed and it always exits 0. Installed by scripts/install-agent-hooks.sh.
dir="${XDG_RUNTIME_DIR:-/tmp}/gutter"
log="$dir/agents.jsonl"
mkdir -p "$dir" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

line="$(jq -c --argjson t "$(date +%s%3N)" '{
    t: $t,
    e: .hook_event_name,
    id: .session_id,
    cwd: .cwd,
    prompt: (if .prompt then .prompt[0:400] else null end),
    tool: .tool_name,
    msg: .message
} | with_entries(select(.value != null))' 2>/dev/null)" || exit 0
[ -n "$line" ] || exit 0

# Append and trim under one lock, so a trim never drops a line another hook call just wrote.
# Waits at most a second; past that the event is dropped rather than holding Claude Code up.
exec 9>>"$dir/agents.lock" 2>/dev/null || exit 0
flock -w 1 9 2>/dev/null || exit 0
printf '%s\n' "$line" >>"$log"

# Keep the log short: the pill only needs the last few hundred events.
if [ "$(wc -l <"$log" 2>/dev/null || echo 0)" -gt 2000 ]; then
    tmp="$(mktemp "$log.XXXXXX" 2>/dev/null)" || exit 0
    if tail -n 500 "$log" >"$tmp" 2>/dev/null; then mv -f "$tmp" "$log"; else rm -f "$tmp"; fi
fi
exit 0
