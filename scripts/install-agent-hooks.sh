#!/usr/bin/env bash
# Adds (or with --uninstall removes) Gutter's agent-tracker hooks and status-line bridge in
# ~/.claude/settings.json. Idempotent; the first run backs the file up to settings.json.pre-gutter. Needs jq.
# A status line you already had is kept in ~/.local/state/gutter/statusline-chain.json; the bridge runs it,
# and --uninstall puts it back.
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)"
hook="$dir/agent-hook.sh"
statusline="$dir/agent-statusline.sh"
chain="${XDG_STATE_HOME:-$HOME/.local/state}/gutter/statusline-chain.json"
settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

command -v jq >/dev/null || { echo "install-agent-hooks: needs jq" >&2; exit 1; }
mkdir -p "$(dirname "$settings")"
[ -f "$settings" ] || echo '{}' >"$settings"
[ -e "$settings.pre-gutter" ] || cp "$settings" "$settings.pre-gutter"

# Drop our entries from every event (keeps everything else), then add them back unless uninstalling.
filter='
  .hooks = ((.hooks // {}) | with_entries(
      .value |= (map(.hooks |= map(select((.command // "") | contains("agent-hook.sh") | not)))
                 | map(select((.hooks | length) > 0)))
  ) | with_entries(select((.value | length) > 0)))'
if [ "${1:-}" != "--uninstall" ]; then
    filter="$filter"'
  | reduce ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop"][] as $e (.;
      .hooks[$e] = ((.hooks[$e] // []) + [
          (if ($e == "PreToolUse" or $e == "PostToolUse") then { matcher: "*" } else {} end)
          + { hooks: [{ type: "command", command: $hook, timeout: 5 }] }
      ]))'
fi

# Status line: remember a foreign one before taking the slot; give it back on uninstall.
mkdir -p "$(dirname "$chain")"
current="$(jq -c '.statusLine // empty' "$settings")"
if [ -n "$current" ] && ! printf '%s' "$current" | grep -q agent-statusline.sh; then
    printf '%s\n' "$current" >"$chain"
fi
if [ "${1:-}" = "--uninstall" ]; then
    if [ -f "$chain" ]; then
        filter="$filter"' | .statusLine = $chain[0]'
    else
        filter="$filter"' | if ((.statusLine.command // "") | contains("agent-statusline.sh")) then del(.statusLine) else . end'
    fi
else
    filter="$filter"' | .statusLine = ({ type: "command", command: $statusline } + (($chain[0] // {}) | if has("padding") then { padding } else {} end))'
fi

tmp="$(mktemp)"
if [ -f "$chain" ]; then
    jq --arg hook "$hook" --arg statusline "$statusline" --slurpfile chain "$chain" "$filter" "$settings" >"$tmp"
else
    jq --arg hook "$hook" --arg statusline "$statusline" --argjson chain '[null]' "$filter" "$settings" >"$tmp"
fi
# Write through, not mv: keeps a symlinked settings.json (dotfile managers) and its mode.
cat "$tmp" >"$settings"
rm -f "$tmp"
if [ "${1:-}" = "--uninstall" ]; then
    rm -f "$chain"
    echo "install-agent-hooks: removed from $settings"
else
    echo "install-agent-hooks: installed in $settings (new Claude Code sessions pick them up)"
fi
