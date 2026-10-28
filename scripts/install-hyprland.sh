#!/usr/bin/env bash
# Makes Hyprland load Gutter's config. Usage: install-hyprland.sh [--dry-run | --apply]
# The default is a dry run that prints every step as "would: ...". Run scripts/install.sh first. Steps, in order:
#   0. refuses (exit 1, nothing written, also in a dry run) unless ~/.config/quickshell/gutter resolves to this repo
#      (scripts/install.sh makes that link) and hypr/gutter.lua is there;
#   1. builds the loader in a temp folder and has `Hyprland --verify-config -c` check it (the loader and
#      hypr/gutter.lua on its own); any error aborts with exit 1 before anything is written. The temp folder has its own
#      HOME and XDG_* folders, so the check never reads or writes the live session. It does not catch errors inside
#      hypr/gutter/keybinds.lua: that module is loaded with loadfile + pcall (the failsafe binds a terminal instead), so
#      a broken one is handled, not fatal.
#   2. copies ~/.config/hypr to ~/.config/hypr.pre-gutter, once, when it exists (never overwritten; symlinks are
#      followed, so the backup holds the files themselves);
#   3. renders ~/.local/state/gutter/hypr-gutter.lua (tools/hypr.py);
#   4. writes the loader (hypr/loader.lua.in) to ~/.config/hypr/hyprland.lua, unless it is already identical; a symlink
#      there is replaced by a regular file (the link's target stays as it was);
#   5. touches the loader's "session already started" marker (${XDG_RUNTIME_DIR:-/tmp}/gutter/hypr-started-<signature>),
#      so a failed reload is reported as a reload, then `hyprctl reload` (only warns when no session is running);
#   6. prints the manual steps (install cava).
# Your own Hyprland settings go in ~/.config/gutter/hypr-user.lua (loaded last) and ~/.config/gutter/hypr-vars.lua;
# neither is written here. Idempotent.
# The repo in the loader is this script's repo (the link above resolves to it).
# A repo path with ";" or "?" (package.path cannot hold them), a newline, "]==]" or ending in "]==" (the loader keeps
# it in a Lua long bracket string) is refused.
# Honours HOME, XDG_CONFIG_HOME, XDG_STATE_HOME, XDG_RUNTIME_DIR, HYPRLAND_INSTANCE_SIGNATURE and GUTTER_DRY=1 (no Hyprland --verify-config and no hyprctl call).
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd -P)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
state="${XDG_STATE_HOME:-$HOME/.local/state}"

warn() { echo "gutter: $*" >&2; }
die() { warn "$*"; exit 1; }

apply=
case "${1:-}" in
    "" | --dry-run) ;;
    --apply) apply=1 ;;
    *) die "usage: install-hyprland.sh [--dry-run | --apply]" ;;
esac
[ "$#" -le 1 ] || die "usage: install-hyprland.sh [--dry-run | --apply]"

command -v python3 >/dev/null || die "this needs python3"

hypr_dir="$cfg/hypr"
backup="$cfg/hypr.pre-gutter"
loader_dest="$hypr_dir/hyprland.lua"
gutter_lua="$state/gutter/hypr-gutter.lua"
template="$here/hypr/loader.lua.in"

# say <text>: a step, "would: <text>" in a dry run.
say() { if [ -n "$apply" ]; then echo "$1"; else echo "would: $1"; fi; }

# --- the repo the loader points at: this checkout, which the quickshell link must name ---
repo="$here"
link="$cfg/quickshell/gutter"
if [ ! -e "$link" ] || [ "$(readlink -f -- "$link")" != "$repo" ]; then
    die "$link does not lead to this checkout ($repo): run scripts/install.sh from this checkout first"
fi
[ -f "$repo/hypr/gutter.lua" ] || die "$repo/hypr/gutter.lua not found: is this a complete checkout? (run scripts/install.sh from it)"
nl=$'\n' cr=$'\r'
case "$repo" in
    *";"* | *"?"* | *"]==]"* | *"]=="  | *"$nl"* | *"$cr"*)
        die "the repo path $repo cannot go in the loader (it holds ';', '?', a newline or ']==]', or ends in ']=='); move the checkout" ;;
esac
[ -f "$template" ] || die "$template not found"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

# --- 1. verify ---
if [ -n "${GUTTER_DRY:-}" ]; then
    say "skip verifying the config (GUTTER_DRY)"
else
    command -v Hyprland >/dev/null || die "this needs Hyprland to verify the config (GUTTER_DRY=1 skips the check)"
    v="$work/verify"
    mkdir -p -- "$v/home" "$v/config/gutter" "$v/state/gutter" "$v/cache" "$v/data" "$v/run"
    chmod 700 "$v/run"
    python3 "$here/tools/hypr.py" --out "$v/state/gutter/hypr-gutter.lua" \
        || die "could not render hypr-gutter.lua for the check"
    python3 -c 'import sys; sys.stdout.write(open(sys.argv[1]).read().replace("@REPO@", sys.argv[2]))' \
        "$template" "$repo" >"$v/hyprland.lua"
    # The loader handles a failing repo config, so the repo's own entry file is checked on its own as well.
    for target in "$v/hyprland.lua" "$repo/hypr/gutter.lua"; do
        echo "verify $target with Hyprland --verify-config (in a temp HOME)"
        rc=0
        out="$(env HOME="$v/home" XDG_CONFIG_HOME="$v/config" XDG_STATE_HOME="$v/state" XDG_CACHE_HOME="$v/cache" \
            XDG_DATA_HOME="$v/data" XDG_RUNTIME_DIR="$v/run" \
            Hyprland --verify-config -c "$target" 2>&1)" || rc=$?
        if [ "$rc" -ne 0 ]; then
            echo "$out" >&2
            die "Hyprland --verify-config rejected $target; nothing changed"
        fi
    done
fi

# --- helpers that write ---
# put <src> <dest> [mode source]: a same-folder temp file renamed over dest (through a symlink to its target).
put() {
    local src="$1" dest tmp
    mkdir -p -- "$(dirname -- "$2")"
    dest="$(readlink -f -- "$2")"
    tmp="$(mktemp "$(dirname -- "$dest")/.gutter.XXXXXX")"
    cp -- "$src" "$tmp"
    if [ -n "${3:-}" ]; then chmod --reference="$3" -- "$tmp"; else chmod 644 -- "$tmp"; fi
    mv -f -- "$tmp" "$dest"
}

# replace_file <src> <dest>: a regular file at dest from a same-folder temp file renamed over it, so a symlink at dest
# is replaced and its target left alone. Keeps the mode of what dest leads to now.
replace_file() {
    local src="$1" dest="$2" tmp
    mkdir -p -- "$(dirname -- "$dest")"
    tmp="$(mktemp "$(dirname -- "$dest")/.gutter.XXXXXX")"
    cp -- "$src" "$tmp"
    if [ -f "$dest" ]; then chmod --reference="$dest" -- "$tmp"; else chmod 644 -- "$tmp"; fi
    mv -f -- "$tmp" "$dest"
}

# --- 2. backup ---
if [ ! -d "$hypr_dir" ]; then
    say "skip the backup: $hypr_dir does not exist"
elif [ -e "$backup" ] || [ -L "$backup" ]; then
    say "keep $backup (already there)"
else
    say "copy $hypr_dir to $backup"
    if [ -n "$apply" ]; then
        # Dereferenced: a symlinked folder or file must not leave the backup pointing at what the loader replaces.
        if ! cp -aL -- "$hypr_dir/." "$backup.tmp.$$"; then
            rm -rf -- "$backup.tmp.$$"
            die "could not copy $hypr_dir to $backup; nothing changed"
        fi
        mv -- "$backup.tmp.$$" "$backup"
    fi
fi

# --- 3. the generated look ---
say "write $gutter_lua (tools/hypr.py)"
if [ -n "$apply" ]; then
    python3 "$here/tools/hypr.py" --out "$gutter_lua" || die "could not write $gutter_lua"
fi
# --- 4. the loader ---
python3 -c 'import sys; sys.stdout.write(open(sys.argv[1]).read().replace("@REPO@", sys.argv[2]))' \
    "$template" "$repo" >"$work/loader.lua"
if [ -f "$loader_dest" ] && [ ! -L "$loader_dest" ] && cmp -s "$work/loader.lua" "$loader_dest"; then
    say "keep $loader_dest (already the loader)"
else
    say "write the loader (repo $repo) to $loader_dest"
    if [ -n "$apply" ]; then
        replace_file "$work/loader.lua" "$loader_dest"
    fi
fi
# --- 5. reload ---
# The session is already running, so the loader must treat the reload as one (a failure notifies instead of starting
# a second shell): the marker it looks for is normally written at hyprland.start, which this session did long ago
# under the previous config. Same path rule as hypr/loader.lua.in.
marker_dir="${XDG_RUNTIME_DIR:-/tmp}/gutter"
marker="$marker_dir/hypr-started-${HYPRLAND_INSTANCE_SIGNATURE:-x}"
say "touch the loader marker $marker"
if [ -n "$apply" ]; then
    mkdir -p -- "$marker_dir" && touch -- "$marker" || warn "could not write $marker"
fi
if [ -n "${GUTTER_DRY:-}" ]; then
    say "skip hyprctl reload (GUTTER_DRY)"
else
    say "hyprctl reload"
    if [ -n "$apply" ]; then hyprctl reload || warn "hyprctl reload failed"; fi
fi

# --- 6. the manual steps ---
cat <<'EOF'

Left to you:
  install the audio visualizer:     sudo pacman -S cava
EOF
if [ -f "$backup/hyprland.lua" ]; then echo "The previous ~/.config/hypr is backed up in $backup."; fi
if [ -z "$apply" ]; then echo "This was a dry run; run with --apply to do it."; fi
