#!/usr/bin/env bash
# Sets Gutter up for the current user. Idempotent. Links ~/.local/bin/gutter to tools/gutter (unless something else
# owns the name), links ${XDG_CONFIG_HOME:-~/.config}/quickshell/gutter to this checkout (Quickshell finds the shell
# through it, and the Hyprland migration checks it; a link or folder that leads elsewhere is left alone), makes foot
# and fuzzel include Gutter's colour files (tools/handover.py install; their configs are backed up once as
# *.pre-gutter), installs the agent hooks (scripts/install-agent-hooks.sh) and creates Gutter's state folder.
# Honours HOME, XDG_CONFIG_HOME, XDG_STATE_HOME and GUTTER_DRY=1 (skips the hook installer, which edits
# ~/.claude/settings.json).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd -P)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
state="${XDG_STATE_HOME:-$HOME/.local/state}"
link="$HOME/.local/bin/gutter"
cli="$repo/tools/gutter"
shell_link="$cfg/quickshell/gutter"

warn() { echo "gutter: $*" >&2; }

command -v python3 >/dev/null || { warn "install needs python3"; exit 1; }

mkdir -p -- "$state/gutter"

if [ ! -e "$link" ] && [ ! -L "$link" ]; then
    mkdir -p -- "$(dirname -- "$link")"
    ln -s -- "$cli" "$link"
elif [ "$(readlink -- "$link" || true)" != "$cli" ]; then
    warn "$link is not ours; left alone"
fi

if [ ! -e "$shell_link" ] && [ ! -L "$shell_link" ]; then
    mkdir -p -- "$(dirname -- "$shell_link")"
    ln -s -- "$repo" "$shell_link"
elif [ ! -e "$shell_link" ] || [ "$(readlink -f -- "$shell_link")" != "$repo" ]; then
    warn "$shell_link does not lead to this checkout; left alone (the Hyprland migration needs it to)"
fi

python3 "$repo/tools/handover.py" install --home "$HOME" --config "$cfg" --state "$state" \
    || { warn "wiring foot and fuzzel failed"; exit 1; }

if [ -n "${GUTTER_DRY:-}" ]; then
    warn "dry run: skipped the agent hooks"
    exit 0
fi
bash "$repo/scripts/install-agent-hooks.sh" || warn "Gutter hook install failed; carrying on (fix it, then run scripts/install.sh again)"
