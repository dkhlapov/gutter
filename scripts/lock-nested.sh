#!/usr/bin/env bash
# A nested Hyprland to try the lock screen's real session-lock path in, so the live desktop is never locked.
#
# Usage:
#   lock-nested.sh start [--no-shell]
#       Runs the nested compositor in the foreground and Gutter (`qs -p <repo>`) in it. The compositor is a window in
#       the compositor you run this from (Hyprland's Wayland backend; it has no headless-only mode), with a second,
#       headless output added so there are two. Leave with Ctrl-C, by closing the window, or with `stop` from another
#       terminal.
#   lock-nested.sh shell [start|kill|kill9|hang|cont]
#                                             (re)start Gutter in the nested session (default), end it (TERM or KILL), or
#                                             freeze it (SIGSTOP, a live but hung lock client) and let it go on (SIGCONT)
#   lock-nested.sh ctl <hyprctl args...>      hyprctl against the nested compositor, e.g. `ctl monitors`
#   lock-nested.sh ipc <qs ipc args...>       Gutter's IPC in the nested session, e.g. `ipc call lock lock`
#   lock-nested.sh logind sleep|resume        feeds Gutter's fake logind monitor a PrepareForSleep (true|false) signal,
#                                             as when the machine goes to sleep or wakes. It is a line appended to a file
#                                             in the session's folder: no bus, no logind and no suspend are involved.
#                                             The nested Gutter runs in Idle's dry run, which logs `dry run, not asking
#                                             for a lock (sleep)` in qs.log unless the session is already locked. After
#                                             `lock-nested.sh ipc call lock dryRun true` a sleep shows Lock's preview
#                                             instead (no session lock), which runs Idle's whole lock-before-sleep path
#   lock-nested.sh env                        the nested session's environment, as `export` lines (for eval)
#   lock-nested.sh stop                       ends a running nested session
# The nested Gutter runs whatever `qs` is first on PATH, so another build can be tried by putting its directory first.
# Environment:
#   GUTTER_NESTED_DIR       where the session's files live (default /tmp/gn-<uid>; the Hyprland socket paths in it must
#                           stay under the 108 characters a unix socket path may have, so keep it short: a folder named
#                           gn* of at most 30 characters; a dry run does not check the length)
#   GUTTER_NESTED_TIMEOUT   watchdog: seconds until the nested compositor is ended for good (default 1800)
#   GUTTER_NESTED_RESTORE   0 starts with misc:allow_session_lock_restore off (default 1, as in the user's config)
#   GUTTER_NESTED_KEEP=1    keep the session's folder (logs) after the run
#   GUTTER_NESTED_DRY=1     print the commands instead of running them (`start` only)
#
# Why the session is sealed off. Gutter at its real settings would take the notification name, apply
# themes to live apps and hold sleep locks, and GUTTER_SMOKE=1 (which stops that) also stops Lock from locking, so it
# cannot be used here. Instead the nested session gets its own XDG_RUNTIME_DIR (so neither hyprctl nor qs can reach
# the outer compositor or the outer qs instances), its own D-Bus session bus, its own HOME and state folders, and a
# PATH whose first entry holds no-op stand-ins for the commands that touch the live desktop (pkill, gsettings,
# xdg-open, pw-play, and systemctl, loginctl, shutdown, reboot, poweroff, so the power menu can never suspend
# or power off the host; systemd-inhibit only holds `cat`; each call is logged to shim.log). GUTTER_POWER_DRY_RUN=1
# and GUTTER_LAUNCHER_DRY_RUN=1 make the power menu and the launcher only log, and DISPLAY is unset. Gutter gets
# GUTTER_LOCK_PAM_DIR (a dummy password, "guttertest", never the account's PAM), GUTTER_LOCK_HINT_FILE (so logind's
# LockedHint stays alone), GUTTER_IDLE_DRY_RUN=1 and a fake logind monitor (GUTTER_IDLE_MONITOR_CMD: `tail -F` on
# <folder>/logind.in, which `logind sleep|resume` appends to; it ends with Gutter, and only lines written after it
# opened are seen). Every command aimed at the nested session sets
# HYPRLAND_INSTANCE_SIGNATURE, WAYLAND_DISPLAY and XDG_RUNTIME_DIR to the nested values itself.
#
# `start` refuses unless WAYLAND_DISPLAY and HYPRLAND_INSTANCE_SIGNATURE are set (it is meant to be run from a
# Hyprland session), and stops if it cannot identify its own nested instance: one that is not new, or is the outer one.
# The other subcommands refuse without a running nested session, or when its recorded instance is the caller's own.
# Quickshell rewrites the `.qmlls.ini` of the checkout it runs (as a symlink into the nested session's runtime
# folder, which is removed at the end; it has no switch to leave the file alone, it only skips a checkout that has
# none). The session records what it was (a link, a file saved byte for byte, or nothing) and puts exactly that back
# when it ends. A file that was there is kept in ${TMPDIR:-/tmp}/gutter-qmlls.*/ini until the session ends (and stays
# there if putting it back failed, or the runner was killed with SIGKILL); a crashed run may leave a dangling link:
# restore it with `ln -sfn <the quickshell/vfs/... .qmlls.ini of the live shell> .qmlls.ini`.
# It never calls `loginctl lock-session`, never locks, unlocks or DPMS-offs the outer session, and never runs
# rescue-unlock.sh on it.
set -euo pipefail
# An exported CDPATH would make `cd` print the path it went to, which `$(cd ... && pwd -P)` would then get twice.
unset CDPATH
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
dry="${GUTTER_NESTED_DRY:-}"
dir="${GUTTER_NESTED_DIR:-/tmp/gn-$(id -u)}"
envfile="$dir/env"
limit="${GUTTER_NESTED_TIMEOUT:-1800}"

usage() {
    awk 'NR > 1 && /^# Environment:/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}" >&2
    exit 2
}

die() {
    echo "lock-nested: $*" >&2
    exit 1
}

# Runs a command, or only prints it in a dry run.
step() {
    if [ -n "$dry" ]; then
        printf 'would run:'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

# The environment of everything that runs inside the nested session (as `env` arguments). Needs sig and wl.
nested_args() {
    local run="$dir/run" home="$dir/home"
    # The folder is put into a JSON array below: refuse what would need escaping rather than escape it, and anything
    # but printable ASCII (Qt decodes the JSON as UTF-8, so other bytes would change the path and tail would wait for
    # a file that never comes).
    case "$dir" in
        *[\"\\]*) die "GUTTER_NESTED_DIR must not contain a quote or a backslash" ;;
    esac
    ( LC_ALL=C; case "$dir" in *[!\ -~]*) exit 1 ;; esac ) ||
        die "GUTTER_NESTED_DIR must be printable ASCII (no control or non-ASCII characters)"
    local monitor
    # shellcheck disable=SC2016
    monitor="$(printf '["sh","-c","exec tail -n 0 -F --pid=$PPID -- \\"$1\\"","sh","%s"]' "$dir/logind.in")"
    nested=(
        -u GUTTER_SMOKE -u GUTTER_GALLERY -u GUTTER_LOCK_DRY_RUN -u DISPLAY
        -u HYPRLAND_CMD -u XDG_SESSION_TYPE -u XDG_SESSION_DESKTOP -u SWAYSOCK -u QS_NO_RELOAD_POPUP
        "HYPRLAND_INSTANCE_SIGNATURE=${sig:-}"
        "WAYLAND_DISPLAY=${wl:-}"
        "XDG_RUNTIME_DIR=$run"
        "DBUS_SESSION_BUS_ADDRESS=unix:path=$run/bus"
        "HOME=$home"
        "XDG_CONFIG_HOME=$home/.config"
        "XDG_STATE_HOME=$home/.local/state"
        "XDG_DATA_HOME=$home/.local/share"
        "XDG_SESSION_ID=gutter-nested"
        "PATH=$dir/shim:$PATH"
        "GUTTER_LOCK_PAM_DIR=${pam:-}"
        "GUTTER_LOCK_HINT_FILE=$dir/hint"
        "GUTTER_IDLE_DRY_RUN=1"
        "GUTTER_POWER_DRY_RUN=1"
        "GUTTER_LAUNCHER_DRY_RUN=1"
        # Idle's logind monitor: whatever `logind sleep|resume` appends to the file (-n 0: only new lines). `--pid` ends
        # it with Gutter, which is its parent (sh's $PPID, as it execs tail), so a killed Gutter leaves no tail behind.
        "GUTTER_IDLE_MONITOR_CMD=$monitor"
    )
}

# Reads the running nested session's record and checks it is a live nested one, or dies.
load() {
    [ -f "$envfile" ] || die "no nested session is running (start one with: lock-nested.sh start)"
    # shellcheck disable=SC1090
    . "$envfile"
    [ -n "${sig:-}" ] && [ -n "${wl:-}" ] || die "$envfile does not name the nested instance"
    [ "${sig}" != "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || die "the recorded nested instance is this shell's own (refusing)"
    kill -0 "$cpid" 2>/dev/null || die "the nested compositor (pid $cpid) is not running (a stale session: remove $dir)"
    nested_args
}

# Gutter's pid in the nested session: the one recorded when it was started, if it still runs as a qs. Never found by
# name, so another qs (the live shell's) cannot be mistaken for it.
shell_pids() {
    local pid
    pid="$(cat "$dir/qs.pid" 2>/dev/null || true)"
    case "$pid" in '' | *[!0-9]*) return 0 ;; esac
    kill -0 "$pid" 2>/dev/null || return 0
    # A qs that was started in this session's folder (shell_start changes into it), not just any pid that got reused.
    case "$(cat "/proc/$pid/comm" 2>/dev/null)" in qs | quickshell*) ;; *) return 0 ;; esac
    [ "$(readlink "/proc/$pid/cwd" 2>/dev/null)" = "$(cd "$dir" 2>/dev/null && pwd -P)" ] || return 0
    echo "$pid"
}

# The runner (the `start` process) is ours: a lock-nested.sh whose arguments include `start`.
runner_ok() {
    local args
    args="$(tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null)" || return 1
    case "$args" in *lock-nested.sh*start*) return 0 ;; *) return 1 ;; esac
}

shell_start() {
    [ -z "$(shell_pids)" ] || die "Gutter already runs in the nested session"
    echo "starting Gutter in the nested session (log: $dir/qs.log)" >&2
    # The nested environment only: the outer compositor's variables never reach it. `exec` keeps the pid.
    ( cd "$dir" && exec env "${nested[@]}" qs -p "$here" >>"$dir/qs.log" 2>&1 </dev/null ) &
    echo "$!" >"$dir/qs.pid"
    disown
}

shell_signal() {
    local pids
    pids="$(shell_pids)"
    [ -n "$pids" ] || { echo "Gutter is not running in the nested session" >&2; return 0; }
    # shellcheck disable=SC2086
    kill "$1" $pids
}

cmd="${1:-}"
[ "$#" -gt 0 ] && shift

case "$cmd" in
    ctl)
        load
        exec env "${nested[@]}" hyprctl "$@"
        ;;
    ipc)
        load
        exec env "${nested[@]}" qs -p "$here" ipc "$@"
        ;;
    logind)
        load
        [ "$#" -eq 1 ] || usage
        case "$1" in
            sleep) sleeping=true ;;
            resume) sleeping=false ;;
            *) usage ;;
        esac
        [ -f "$dir/logind.in" ] || die "$dir/logind.in is missing (a session from before the fake logind monitor: restart it)"
        # The line `gdbus monitor` prints for the signal (lib/idle.js logindEvent reads it); one append, so it is whole.
        printf '/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (%s,)\n' "$sleeping" >>"$dir/logind.in"
        ;;
    env)
        load
        for kv in "${nested[@]}"; do
            case "$kv" in
                *=*) printf 'export %s=%q\n' "${kv%%=*}" "${kv#*=}" ;;
            esac
        done
        ;;
    shell)
        load
        case "${1:-start}" in
            start) shell_start ;;
            kill) shell_signal -TERM ;;
            kill9) shell_signal -KILL ;;
            hang) shell_signal -STOP ;;
            cont) shell_signal -CONT ;;
            *) usage ;;
        esac
        ;;
    stop)
        load
        kill -0 "$runner" 2>/dev/null || die "the nested session's runner (pid $runner) is gone (a stale session: remove $dir)"
        runner_ok "$runner" || die "pid $runner is not this session's lock-nested.sh start (a stale session: remove $dir)"
        kill -TERM "$runner"
        ;;
    start) ;;
    *) usage ;;
esac
[ "$cmd" = start ] || exit 0

# --- start -------------------------------------------------------------------------------------------------

shell=1
while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-shell)
            shell=0
            shift
            ;;
        *) usage ;;
    esac
done
[ -n "${WAYLAND_DISPLAY:-}" ] || die "WAYLAND_DISPLAY is not set: run this from inside the Hyprland session"
[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || die "HYPRLAND_INSTANCE_SIGNATURE is not set: run this from inside the Hyprland session"
case "$limit" in
    '' | *[!0-9]*) die "GUTTER_NESTED_TIMEOUT must be a number of seconds" ;;
esac
case "$(basename "$dir")" in
    gn* | gutter-nested*) ;;
    *) die "GUTTER_NESTED_DIR must be a folder named gn* or gutter-nested* (it is removed when the session ends)" ;;
esac
if [ -z "$dry" ] && [ "${#dir}" -gt 30 ]; then
    die "GUTTER_NESTED_DIR is too long ($dir): Hyprland's socket paths would pass the 108 characters of a unix socket path"
fi
if [ -z "$dry" ] && [ -e "$envfile" ]; then
    die "a nested session record exists ($envfile): end it with 'lock-nested.sh stop', or remove $dir if it is stale"
fi

outer_sig="$HYPRLAND_INSTANCE_SIGNATURE"
outer_wl="$WAYLAND_DISPLAY"
case "$outer_wl" in
    /*) ;;
    *) outer_wl="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$outer_wl" ;;
esac
run="$dir/run"
home="$dir/home"
restore=true
[ "${GUTTER_NESTED_RESTORE:-1}" = 0 ] && restore=false

# Not running yet: placeholders where the nested instance is not known.
sig="<nested-signature>"
wl="<nested-display>"
pam="$dir/<pam-dir>"
nested_args

# The compositor's own environment: never the outer instance's signature; its window needs the outer display.
hyprunset=(-u HYPRLAND_INSTANCE_SIGNATURE -u HYPRLAND_CMD -u XDG_SESSION_ID)
hyprenv=("WAYLAND_DISPLAY=$outer_wl")

config="$dir/hyprland.lua"
write_config() {
    cat >"$config" <<LUA
-- The nested session's config (written by scripts/lock-nested.sh).
hl.config({
    general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
    animations = { enabled = false },
    xwayland = { enabled = false },
    input = { kb_layout = "us" },
    misc = {
        allow_session_lock_restore = $restore,
        disable_hyprland_logo = true,
        force_default_wallpaper = 0,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
    },
})
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
LUA
}

make_shims() {
    mkdir -p "$dir/shim"
    local name
    for name in pkill gsettings xdg-open pw-play systemctl loginctl shutdown reboot poweroff; do
        printf '#!/bin/sh\necho "%s $*" >>"%s/shim.log"\nexit 0\n' "$name" "$dir" >"$dir/shim/$name"
        chmod +x "$dir/shim/$name"
    done
    # Holds the way the real one does, but takes no inhibitor from logind.
    printf '#!/bin/sh\necho "systemd-inhibit $*" >>"%s/shim.log"\nexec cat\n' "$dir" >"$dir/shim/systemd-inhibit"
    chmod +x "$dir/shim/systemd-inhibit"
}

# Quickshell rewrites the checkout's .qmlls.ini (a symlink into the runtime folder it runs in): put it back, byte for
# byte. What it was is a kind (link, file, none, or other: a directory or the like, which is left alone) and, for a
# file, a copy (cp -p: content, empty or not, trailing newlines and mode) in a gutter-qmlls.* folder of ${TMPDIR:-/tmp},
# made here because the session's own folder does not exist yet. restore_qmlls removes that folder, unless putting the
# file back failed: then the copy is all that is left, so it stays and its path is printed.
qmlls="$here/.qmlls.ini"
qmlls_kind=""
qmlls_link=""
qmlls_store=""
save_qmlls() {
    local real
    if [ -L "$qmlls" ]; then
        # The `x` keeps the target's trailing newlines, which $(...) would drop; it is only printed if readlink worked.
        qmlls_link="$(readlink -- "$qmlls" && printf x)" || die "cannot read $qmlls"
        qmlls_link="${qmlls_link%x}"
        # readlink adds a newline of its own.
        qmlls_link="${qmlls_link%$'\n'}"
        qmlls_kind=link
    elif [ -f "$qmlls" ]; then
        qmlls_store="$(mktemp -d -t gutter-qmlls.XXXXXXXX)" || die "cannot make a temp folder to keep $qmlls in"
        # Judged by where the folder really is: TMPDIR may be relative or reach the checkout through a link.
        real="$(cd "$qmlls_store" && pwd -P)" || real="$qmlls_store"
        case "$real" in
            "$here"/*)
                rm -rf "$qmlls_store"
                qmlls_store=""
                die "TMPDIR is inside the checkout: the saved .qmlls.ini would not be safe there"
                ;;
        esac
        qmlls_store="$real"
        qmlls_kind=file
        cp -p "$qmlls" "$qmlls_store/ini" || { rm -rf "$qmlls_store"; qmlls_store=""; die "cannot save $qmlls"; }
    elif [ -e "$qmlls" ]; then
        qmlls_kind=other
    else
        qmlls_kind=none
    fi
}
# Never fails (every command that can is guarded, even the message): it runs in the EXIT trap, which must still remove
# the session's folder.
restore_qmlls() {
    case "$qmlls_kind" in
        link) ln -sfn -- "$qmlls_link" "$qmlls" 2>/dev/null || true ;;
        file)
            if rm -f "$qmlls" 2>/dev/null && cp -p "$qmlls_store/ini" "$qmlls" 2>/dev/null; then
                rm -rf "$qmlls_store"
            else
                echo "lock-nested: could not put $qmlls back; the saved copy is $qmlls_store/ini" >&2 || true
            fi
            ;;
        none)
            # There was none before: do not leave the link the nested qs made into this folder (it points into the
            # session's folder, which is about to go).
            if [ -L "$qmlls" ]; then rm -f "$qmlls" 2>/dev/null || true; fi
            ;;
    esac
    return 0
}

hpid=""
dpid=""
runner=$$
cleanup() {
    trap - EXIT INT TERM HUP
    # Gutter first (the compositor keeps a lock a dying client leaves; it goes with the compositor), then the rest.
    local pids
    pids="$(shell_pids)"
    # shellcheck disable=SC2086
    [ -z "$pids" ] || kill -KILL $pids 2>/dev/null || true
    [ -z "$hpid" ] || kill -TERM "$hpid" 2>/dev/null || true
    [ -z "$dpid" ] || kill -TERM "$dpid" 2>/dev/null || true
    sleep 0.3
    [ -z "$hpid" ] || kill -KILL "$hpid" 2>/dev/null || true
    restore_qmlls
    if [ "${GUTTER_NESTED_KEEP:-}" = 1 ]; then
        echo "lock-nested: kept $dir" >&2
    else
        rm -rf "$dir"
    fi
}

if [ -n "$dry" ]; then
    echo "would use: dir=$dir outer=$outer_sig"
    echo "would run: $here/scripts/lock-test-pam.sh $dir"
    echo "would run: dbus-daemon --session --nofork --address=unix:path=$run/bus"
    printf 'would run:'
    printf ' %q' timeout "$limit" env "${hyprunset[@]}" "XDG_RUNTIME_DIR=$run" "DBUS_SESSION_BUS_ADDRESS=unix:path=$run/bus" "HOME=$home" "${hyprenv[@]}" Hyprland -c "$config"
    printf '\n'
    printf 'would run:'
    printf ' %q' env "${nested[@]}" hyprctl output create headless
    printf '\n'
    if [ "$shell" -eq 1 ]; then
        printf 'would run:'
        printf ' %q' env "${nested[@]}" qs -p "$here"
        printf '\n'
    fi
    exit 0
fi

command -v Hyprland >/dev/null || die "Hyprland is not installed"
command -v dbus-daemon >/dev/null || die "dbus-daemon is not installed"
command -v qs >/dev/null || die "qs (Quickshell) is not installed"

save_qmlls
trap cleanup EXIT INT TERM HUP
umask 077
mkdir -p "$run" "$home/.config" "$home/.local/state" "$home/.local/share"
chmod 700 "$dir" "$run"
pam="$("$here/scripts/lock-test-pam.sh" "$dir")"
printf 'false\n' >"$dir/hint"
: >"$dir/logind.in"
make_shims
write_config
nested_args

# The nested session's own session bus.
env XDG_RUNTIME_DIR="$run" HOME="$home" dbus-daemon --session --nofork --address="unix:path=$run/bus" >/dev/null 2>&1 &
dpid=$!

timeout "$limit" env "${hyprunset[@]}" \
    "XDG_RUNTIME_DIR=$run" "DBUS_SESSION_BUS_ADDRESS=unix:path=$run/bus" "HOME=$home" \
    "XDG_CONFIG_HOME=$home/.config" "XDG_STATE_HOME=$home/.local/state" "XDG_DATA_HOME=$home/.local/share" \
    "${hyprenv[@]}" Hyprland -c "$config" >"$dir/hyprland.out" 2>&1 </dev/null &
hpid=$!

# The nested instance is the one new folder in the private runtime dir; anything else is a refusal.
sig=""
for _ in $(seq 1 150); do
    kill -0 "$hpid" 2>/dev/null || { cat "$dir/hyprland.out" >&2; die "the nested compositor exited at start"; }
    for d in "$run"/hypr/*/; do
        if [ -f "${d}hyprland.lock" ] && [ -n "$(sed -n 2p "${d}hyprland.lock")" ]; then
            sig="$(basename "$d")"
            break 2
        fi
    done
    sleep 0.2
done
[ -n "$sig" ] || die "cannot identify the nested instance (no new folder in $run/hypr)"
[ "$sig" != "$outer_sig" ] || die "the nested instance has the outer signature (refusing)"
cpid="$(sed -n 1p "$run/hypr/$sig/hyprland.lock")"
kill -0 "$cpid" 2>/dev/null || die "the nested compositor (pid $cpid) is not running"
wl="$(sed -n 2p "$run/hypr/$sig/hyprland.lock")"
[ -S "$run/$wl" ] || die "the nested compositor's socket $run/$wl is missing"
nested_args

# Two outputs: the window and one headless one.
env "${nested[@]}" hyprctl output create headless >/dev/null
sleep 0.5
count="$(env "${nested[@]}" hyprctl monitors | grep -c '^Monitor' || true)"
[ "$count" -ge 2 ] || die "the nested session has $count outputs, not 2"

{
    printf 'sig=%q\nwl=%q\npam=%q\nhpid=%q\ncpid=%q\ndpid=%q\nrunner=%q\n' "$sig" "$wl" "$pam" "$hpid" "$cpid" "$dpid" "$runner"
} >"$envfile"

cat >&2 <<INFO
Nested Hyprland up: instance $sig on $wl ($count outputs).
Dummy password: guttertest. Folder: $dir
From another terminal:  scripts/lock-nested.sh ipc call lock lock   |   scripts/lock-nested.sh ctl monitors
Leave: Ctrl-C here, close the nested window, or run scripts/lock-nested.sh stop (watchdog: ${limit}s).
INFO

if [ "$shell" -eq 1 ]; then
    shell_start
fi

wait "$hpid" || true
