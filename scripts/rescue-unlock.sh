#!/usr/bin/env bash
# The way out when Gutter's lock screen died, hung, or left the session locked. Run it from a TTY (Ctrl+Alt+F3, log in).
#
# Usage: rescue-unlock.sh [--force] [--instance SIGNATURE]
#   --force               run inside a Wayland session too (the script is meant for a TTY; this is for a nested compositor)
#   --instance SIGNATURE  the Hyprland instance to unlock: a bare folder name under $XDG_RUNTIME_DIR/hypr (letters,
#                         digits and _ only; anything else is refused). Inside a Wayland session (--force) it is required,
#                         and refused when its compositor is the live session's (see below)
# Environment:
#   HYPRLAND_INSTANCE_SIGNATURE  the instance to unlock; default is the newest live one under $XDG_RUNTIME_DIR/hypr
#   XDG_RUNTIME_DIR              where that instance and the Quickshell instances of the session live (/run/user/<uid>)
#   GUTTER_RESCUE_SESSION        the logind session id of the graphical session; default is the user's Display session
#   GUTTER_LOCK_HINT_FILE        the nested test setup's LockedHint file: cleared instead of logind's hint, which is then
#                                never touched
#   GUTTER_RESCUE_QS             how `qs` names the lock screen to end (default `-c gutter`; `-p <repo>` for a checkout)
#   GUTTER_RESCUE_KILL_CMD       the command that asks it to quit, replacing the default wholesale (the default is
#                                `qs $GUTTER_RESCUE_QS kill --pid <pid>` for each instance of that config that runs
#                                in the target Hyprland instance; a bare `qs kill` would ask only the oldest instance of
#                                the config on the current display, whichever Hyprland instance it runs in)
#   GUTTER_RESCUE_KILL_TIMEOUT   seconds to wait for it, then the instance is killed by pid (default 5)
#   GUTTER_RESCUE_TIMEOUT        seconds the rescue shell may take before it is stopped (default 15)
#   GUTTER_RESCUE_POLL           seconds between looks at whether the lock screen has gone (default 0.25; up to 8 looks)
#   GUTTER_RESCUE_SETTLE         seconds to let the compositor notice a killed client before the rescue shell (default 0.5)
#   GUTTER_RESCUE_DRY=1          print each command ("would run: ...") instead of running it
#   The four time settings above take plain numbers (5, 0.25); anything else is refused before the prompt. The two
#   timeouts must also be above 0 (`timeout 0` would mean no limit at all).
# Exit codes: 0 done; 1 refused, no instance found, or misc:allow_session_lock_restore could not be turned on; 2 bad
#   usage, a time setting that is no number or a zero timeout, or the word `unlock` was not given; 124 the rescue shell
#   did not finish in time; otherwise the exit code of the step that failed.
#
# What it does, in this order:
#   1. sets misc:allow_session_lock_restore on that instance (so a new client may take the lock over; exit 1 if that
#      cannot be confirmed, before anything is ended),
#   2. ends the lock screen that still runs in that instance (`qs ... kill --pid <pid>`, and when that does not answer,
#      as with a hung process, SIGKILL for the pid `qs ... list` names). A live lock client makes the compositor refuse
#      a second lock, and a hung one would never let go. Only instances registered under the target's XDG_RUNTIME_DIR
#      whose environment names the target instance are asked or killed (`qs kill` without --pid asks only the oldest
#      instance of the config on the current display, which is not checked against the target and leaves any other one
#      running), never a process found by name. The session stays locked (the compositor keeps it),
#   3. runs lockscreen/rescue (a tiny qs shell that takes the lock, waits 1.5 s and releases it; no password, you are
#      already logged in on the TTY) under `timeout`. It exits non-zero if the lock is refused or not confirmed
#      within 5 s,
#   4. clears the session's LockedHint over D-Bus (or the hint file, see above).
# The hint is cleared last, on purpose: if step 3 fails (or times out) the session stays locked and still marked as
# locked, so Gutter relocks at its next start. Clearing it first would let a Gutter that restarts in between come up
# unlocked over a still-locked session. After it succeeds, start Gutter again through the compositor (printed at the end)
# or log out and in.
#
# The compositor's pid is that of the process holding the instance's .socket.sock, because a hyprland.lock can be stale
# or name a reused pid. It is found without ever connecting to a socket (a connect would be a request to a compositor):
# /proc/net/unix names the inode of the listening socket bound at that path, and the process whose /proc/<pid>/fd holds
# that inode is the holder. If the pid in hyprland.lock is among the holders, it is used; if not, it says so and trusts
# the (lowest) holder. Without a socket, python3 or a readable /proc the pid in hyprland.lock is used. A socket path
# with a newline in it can fake a line of /proc/net/unix. An inode that shows up on more than one line is ignored (with
# none left, the pid in hyprland.lock is used), which stops a fake line that reuses the inode of a unix socket with its
# own line (such as the compositor's or the faker's own). It does not stop a fake line with the inode of a socket that
# has no line there (TCP, UDP, netlink, or a unix socket of another network namespace): that inode shows up once, is in
# the faker's /proc/<pid>/fd, and so names the faker as a holder. Only a process of the same user can do that, and it
# can already do everything this script does, so no privilege boundary is crossed; and the pid in hyprland.lock is
# still used whenever it is among the holders. The display named in hyprland.lock must be a bare name, and the process
# holding that Wayland socket (when it can be found) must be the compositor too, or nothing is touched.
# It never works on the session it runs in: an instance whose compositor is an ancestor of this process is refused, and
# inside a Wayland session (WAYLAND_DISPLAY set, which needs --force) the instance must be named with --instance (a
# signature from the environment, or the newest one, would be this session's own) and is refused if its compositor is
# the live session's: its pid is compared (not its name or path, so no spelling and no symlink gets past it) with the
# pid of EVERY live instance (a valid signature folder whose compositor runs, pid found as above) under
# /run/user/<uid>/hypr. A nested compositor has its own XDG_RUNTIME_DIR and its own pid:
# `eval "$(scripts/lock-nested.sh env)"; scripts/rescue-unlock.sh --force --instance <its signature>`.
# GUTTER_RESCUE_LIVE_RUNTIME (for the tests) adds a runtime dir to compare with; /run/user/<uid> is always compared.
# What a refusal echoes of the command line, the environment and hyprland.lock is sanitised (other characters are shown
# as ?, a signature is cut at 40 and a path at 120).
# The option check comes first: if misc:allow_session_lock_restore cannot be turned on the script stops before it ends
# anything, so a working lock screen stays in place.
set -euo pipefail
# An exported CDPATH would make `cd` print the path it went to, which `$(cd ... && pwd -P)` would then get twice.
unset CDPATH
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
dry="${GUTTER_RESCUE_DRY:-}"

force=0
named=""
usage() {
    echo "usage: rescue-unlock.sh [--force] [--instance SIGNATURE]" >&2
    exit 2
}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --force) force=1 ;;
        --instance)
            [ "$#" -ge 2 ] && [ -n "$2" ] || usage
            named="$2"
            shift
            ;;
        *) usage ;;
    esac
    shift
done
# A signature is a folder name: never a path (SIG/, ./SIG, ../x) that would name the same instance another way.
valid_sig() {
    [[ "$1" =~ ^[A-Za-z0-9_]+$ ]]
}
# A value that failed that check, safe to print: it came from the command line or the environment and may hold terminal
# escape sequences or newlines. Anything outside the signature alphabet shows as ? (one for each byte), and it is cut at
# 40 characters.
shown() {
    local LC_ALL=C
    local s="${1//[^A-Za-z0-9_]/?}"  # byte by byte, whatever the locale
    if [ "${#s}" -gt 40 ]; then
        s="${s:0:40}..."
    fi
    printf '%s' "$s"
}
# The same for a path built from the environment (or from a folder name): it may keep / . and -, and is cut at 120.
shown_path() {
    local LC_ALL=C
    local s="${1//[^A-Za-z0-9_\/.-]/?}"
    if [ "${#s}" -gt 120 ]; then
        s="${s:0:120}..."
    fi
    printf '%s' "$s"
}
# The time settings are handed to sleep and timeout: plain numbers only.
for setting in GUTTER_RESCUE_POLL GUTTER_RESCUE_SETTLE GUTTER_RESCUE_KILL_TIMEOUT GUTTER_RESCUE_TIMEOUT; do
    value="${!setting:-}"
    if [ -n "$value" ] && ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "rescue-unlock: $setting takes a number of seconds (5, 0.25), not '$(shown "$value")'" >&2
        exit 2
    fi
done
# timeout 0 means no limit: a rescue shell or a kill that hangs would then never be stopped.
for setting in GUTTER_RESCUE_KILL_TIMEOUT GUTTER_RESCUE_TIMEOUT; do
    if [[ "${!setting:-}" =~ ^0+(\.0+)?$ ]]; then
        echo "rescue-unlock: $setting must be above 0 (0 would mean no time limit), not '${!setting}'" >&2
        exit 2
    fi
done
if [ -n "$named" ] && ! valid_sig "$named"; then
    echo "rescue-unlock: --instance takes a bare signature (letters, digits and _), not '$(shown "$named")': refusing" >&2
    exit 1
fi
# A directory with every symlink and trailing slash resolved (empty if it does not exist).
canon() {
    (cd -P -- "$1" 2>/dev/null && pwd -P) || true
}

if [ -n "${WAYLAND_DISPLAY:-}" ] && [ "$force" -ne 1 ]; then
    echo "rescue-unlock: this is a Wayland session; the script is meant for a TTY (Ctrl+Alt+F3). Use --force to run it anyway." >&2
    exit 1
fi

runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
runtime_real="$(canon "$runtime")"
[ -z "$runtime_real" ] || runtime="$runtime_real"
export XDG_RUNTIME_DIR="$runtime"
hypr="$runtime/hypr"

# The compositor pid a hyprland.lock names, as a plain number (empty if it names none). Leading zeros are dropped; more
# than 10 digits is no pid.
lock_pid() {
    local pid
    pid="$(sed -n 1p "$1" 2>/dev/null || true)"
    [[ "$pid" =~ ^[0-9]{1,10}$ ]] && echo "$((10#$pid))"
    return 0
}
# Whether a process of that pid runs. Only a plain number above 1 is asked: kill -0 0 and kill -0 -N signal a whole
# process group, a text is no pid, and pid 1 is no compositor.
pid_alive() {
    [[ "$1" =~ ^[0-9]{1,10}$ ]] && [ "$((10#$1))" -gt 1 ] && kill -0 "$((10#$1))" 2>/dev/null
}
# Whether the compositor a hyprland.lock names runs (by the lock's own pid: this only picks the newest candidate).
alive() {
    pid_alive "$(lock_pid "$1")"
}
# The newest live instance under a hypr folder (default $hypr; empty if none).
newest_live() {
    local name dir="${1:-$hypr}"
    [ -d "$dir" ] || return 0
    while IFS= read -r name; do
        if valid_sig "$name" && [ -f "$dir/$name/hyprland.lock" ] && alive "$dir/$name/hyprland.lock"; then
            echo "$name"
            return 0
        fi
    done < <(ls -1t "$dir" 2>/dev/null || true)
}
# The pids of the processes that hold the listening unix socket bound at a path, lowest first (nothing if there is none,
# python3 is missing or /proc cannot be read). It never connects: the inode comes from /proc/net/unix and the holders
# from the socket:[inode] links in /proc/<pid>/fd (those of this user's processes are readable).
socket_holders() {
    [ -S "$1" ] || return 0
    local out line
    out="$(python3 -I -c '
import os, sys
path = sys.argv[1]
inodes = set()
seen = {}
try:
    # As bytes: any user can bind a socket whose path is not UTF-8, and one such line must not end the lookup.
    with open("/proc/net/unix", "rb") as f:
        for line in f.read().splitlines()[1:]:
            c = line.split(None, 7)
            if len(c) < 7 or not c[0].endswith(b":"):
                continue
            seen[c[6]] = seen.get(c[6], 0) + 1
            # Num: RefCount Protocol Flags Type St Inode Path; flag 0x10000 is a listening socket
            if len(c) == 8 and c[7] == os.fsencode(path):
                try:
                    if int(c[3], 16) & 0x10000:
                        inodes.add(c[6])
                except ValueError:
                    pass
except OSError:
    pass
# A socket is one line: an inode on two was made up by a line inside a socket path.
inodes = {i.decode("ascii", "replace") for i in inodes if seen[i] == 1}
holders = set()
for pid in os.listdir("/proc") if inodes else []:
    if not pid.isdigit():
        continue
    try:
        fds = os.listdir("/proc/%s/fd" % pid)
    except OSError:
        continue
    for fd in fds:
        try:
            link = os.readlink("/proc/%s/fd/%s" % (pid, fd))
        except OSError:
            continue
        if link.startswith("socket:[") and link[8:-1] in inodes:
            holders.add(int(pid))
            break
for pid in sorted(holders):
    print(pid)
' "$1" 2>/dev/null || true)"
    while IFS= read -r line; do
        [[ "$line" =~ ^[0-9]+$ ]] && echo "$line"
    done <<<"$out"
    return 0
}
# The compositor pid out of the one a hyprland.lock names ($1, may be empty) and the holders of its socket ($2...): the
# lock's if it is among the holders or there are none, else the lowest holder.
pick_pid() {
    local lockp="$1" h
    shift
    for h in "$@"; do
        [ "$h" != "$lockp" ] || { echo "$lockp"; return 0; }
    done
    echo "${1:-$lockp}"
}
# The compositor pid of an instance folder (empty if it has none).
instance_pid() {
    local holders
    mapfile -t holders < <(socket_holders "$1/.socket.sock")
    pick_pid "$(lock_pid "$1/hyprland.lock")" "${holders[@]}"
}
inside_wayland=0
[ -z "${WAYLAND_DISPLAY:-}" ] || inside_wayland=1
# The instance: the named one, else the caller's signature, else the newest folder (by modification time) with a
# hyprland.lock whose compositor is still running (a crashed one leaves its folder behind).
sig="${named:-${HYPRLAND_INSTANCE_SIGNATURE:-}}"
[ -n "$sig" ] || sig="$(newest_live)"
lock="$hypr/$sig/hyprland.lock"
if [ -n "$sig" ] && ! valid_sig "$sig"; then
    echo "rescue-unlock: '$(shown "$sig")' is not a Hyprland instance signature (letters, digits and _): refusing" >&2
    exit 1
fi
if [ -z "$sig" ] || [ ! -f "$lock" ]; then
    echo "rescue-unlock: no Hyprland instance found under $(shown_path "$hypr")${sig:+ (signature $sig)}" >&2
    exit 1
fi
lock_said="$(lock_pid "$lock")"
mapfile -t holders < <(socket_holders "$hypr/$sig/.socket.sock")
target_pid="$(pick_pid "$lock_said" "${holders[@]}")"
if [ "${#holders[@]}" -gt 0 ] && [ "$target_pid" != "$lock_said" ]; then
    echo "rescue-unlock: $(shown_path "$lock") names ${lock_said:+pid }${lock_said:-no usable pid}, but the socket of instance $sig is held by pid $target_pid; trusting the socket" >&2
fi
if [ -z "$target_pid" ]; then
    echo "rescue-unlock: $(shown_path "$lock") does not name the compositor's pid" >&2
    exit 1
fi
if ! pid_alive "$target_pid"; then
    echo "rescue-unlock: the compositor of instance $sig is not running (a stale $(shown_path "$lock"))" >&2
    exit 1
fi

# Never the session this script runs in. --force is for a nested compositor, which has its own XDG_RUNTIME_DIR
# (scripts/lock-nested.sh) and is not this shell's ancestor; a rescue of the live session is for a TTY.
is_ancestor() {
    local want="$1" p="$$" stat
    while [ -n "$p" ] && [ "$p" -gt 1 ]; do
        [ "$p" != "$want" ] || return 0
        stat="$(cat "/proc/$p/stat" 2>/dev/null)" || return 1
        stat="${stat##*) }"
        set -- $stat
        p="${2:-}"
    done
    return 1
}
refuse_hint='to unlock a nested compositor: eval "$(scripts/lock-nested.sh env)" and run rescue-unlock.sh --force --instance <its signature>; to unlock the live session: run this from a TTY (Ctrl+Alt+F3)'
if is_ancestor "$target_pid"; then
    echo "rescue-unlock: instance $sig is the compositor this shell runs in (it is an ancestor of this process): refusing; $refuse_hint" >&2
    exit 1
fi
if [ "$inside_wayland" -eq 1 ]; then
    if [ -z "$named" ]; then
        # The signature came from the environment of a Wayland session (its own) or was picked as the newest (probably the same).
        echo "rescue-unlock: inside a Wayland session the instance must be named with --instance; refusing to guess (it would be this session's own); $refuse_hint" >&2
        exit 1
    fi
    # The live session's compositors, by pid: every live instance (a valid signature folder whose compositor runs) in
    # the real runtime dir and in the one the tests add. The same compositor reached through any other path still has
    # the same pid.
    lives=("/run/user/$(id -u)")
    [ -z "${GUTTER_RESCUE_LIVE_RUNTIME:-}" ] || lives+=("$GUTTER_RESCUE_LIVE_RUNTIME")
    for live in "${lives[@]}"; do
        live_real="$(canon "$live")"
        [ -n "$live_real" ] || continue
        for dir in "$live_real/hypr"/*/; do
            dir="${dir%/}"
            [ -d "$dir" ] && valid_sig "${dir##*/}" || continue
            live_pid="$(instance_pid "$dir")"
            if pid_alive "$live_pid" && [ "$live_pid" = "$target_pid" ]; then
                echo "rescue-unlock: instance $sig runs on compositor pid $target_pid, the live session's own ($(shown_path "$dir"), in $(shown_path "$live"), is a live instance): refusing; $refuse_hint" >&2
                exit 1
            fi
        done
    done
fi
# hyprland.lock holds the compositor's pid, then the name of the Wayland socket it serves.
display="$(sed -n 2p "$lock")"
if [ -z "$display" ]; then
    echo "rescue-unlock: $(shown_path "$lock") does not name the instance's Wayland socket" >&2
    exit 1
fi
# A bare socket name: it is joined to the runtime dir, and printed and exported below.
if ! [[ "$display" =~ ^[A-Za-z0-9_.-]+$ ]] || [ "$display" = . ] || [ "$display" = .. ]; then
    echo "rescue-unlock: $(shown_path "$lock") names '$(shown_path "$display")' as the Wayland socket, not a bare socket name: refusing" >&2
    exit 1
fi
# That socket must be the target compositor's own (when its holder can be found): a lock that points at another
# compositor's display would have the rescue shell lock and unlock the wrong session.
mapfile -t holders < <(socket_holders "$runtime/$display")
if [ "${#holders[@]}" -gt 0 ] && [ "$(pick_pid "$target_pid" "${holders[@]}")" != "$target_pid" ]; then
    echo "rescue-unlock: the Wayland socket $(shown_path "$display") of instance $sig is held by pid ${holders[0]}, not by the compositor pid $target_pid: refusing" >&2
    exit 1
fi
export HYPRLAND_INSTANCE_SIGNATURE="$sig"
export WAYLAND_DISPLAY="$display"

# The logind session path, built like lib/idle.js sessionPath(): a letter or a digit (not first) stays, anything else
# is "_" and two lowercase hex digits.
session_path() {
    local id="$1" out="" c i
    for ((i = 0; i < ${#id}; i++)); do
        c="${id:i:1}"
        if [[ "$c" =~ [A-Za-z] ]] || { [[ "$c" =~ [0-9] ]] && [ "$i" -gt 0 ]; }; then
            out+="$c"
        else
            out+="$(printf '_%02x' "'$c")"
        fi
    done
    echo "/org/freedesktop/login1/session/$out"
}

# The graphical session: not the TTY's own (that is what `session/auto` would mean here).
session="${GUTTER_RESCUE_SESSION:-}"
if [ -z "$session" ] && [ -z "${GUTTER_LOCK_HINT_FILE:-}" ]; then
    session="$(loginctl show-user "$(id -u)" -p Display --value 2>/dev/null || true)"
fi

printf 'Instance %s on %s.\n' "$sig" "$display" >&2
printf 'This ends the Gutter lock screen that is still running there, and unlocks the session without a password.\nType the word unlock to go on: ' >&2
answer=""
read -r answer || true
if [ "$answer" != "unlock" ]; then
    echo "rescue-unlock: not unlocking" >&2
    exit 2
fi

if [ -n "$dry" ]; then
    echo "would use: HYPRLAND_INSTANCE_SIGNATURE=$sig WAYLAND_DISPLAY=$display"
fi
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

# 1. Let a new client take the lock over. Hyprland 0.56 has a Lua config: `eval` sets it (checked on a nested instance, with the
# option off before and on after). `keyword` only works with a legacy hyprlang config (0.56's Lua one answers "Use eval").
option_on() {
    hyprctl -j getoption misc:allow_session_lock_restore | grep -Eq '"(bool|int)": *(true|1)'
}
step hyprctl eval 'hl.config({ misc = { allow_session_lock_restore = true } })' || true
if [ -z "$dry" ] && ! option_on; then
    hyprctl keyword misc:allow_session_lock_restore 1 || true
    if ! option_on; then
        # Before anything is ended: the working lock screen stays in place, and so does the lock.
        echo "rescue-unlock: could not turn on misc:allow_session_lock_restore (hyprctl eval and keyword both failed, or the option reads off); nothing was ended or changed, the session is still locked as it was. Set the option by hand (hyprctl eval 'hl.config({ misc = { allow_session_lock_restore = true } })') and run this again." >&2
        exit 1
    fi
fi

# 2. End the lock screen that is still running in this instance: while a client holds the lock the compositor refuses
# another one, and a hung client never lets go. It answers `kill` or is killed by pid; the compositor keeps the session
# locked either way. Only instances in this XDG_RUNTIME_DIR's registry that run in this Hyprland instance are touched:
# `qs kill` without --pid asks only the oldest instance of the config on the current display, whichever Hyprland it runs in.
read -r -a qs_select <<<"${GUTTER_RESCUE_QS:--c gutter}"
kill_wait="${GUTTER_RESCUE_KILL_TIMEOUT:-5}"
poll="${GUTTER_RESCUE_POLL:-0.25}"
settle="${GUTTER_RESCUE_SETTLE:-0.5}"
# The pids `qs list` names (this runtime dir's registry, the selected config).
listed() {
    timeout -k 2 "$kill_wait" qs "${qs_select[@]}" list --json 2>/dev/null | sed -n 's/^ *"pid": *\([0-9][0-9]*\).*/\1/p' || true
}
# Whether a pid is a qs (or quickshell) process. Anything else the registry might name is left alone.
is_qs() {
    case "$(cat "/proc/$1/comm" 2>/dev/null)" in
        qs | quickshell*) return 0 ;;
    esac
    return 1
}
# Whether a process runs in the target instance (its environment says so); one whose environment cannot be read does not.
# grep reads all of it (no -q): an early exit would SIGPIPE tr and, under pipefail, read as no match.
in_instance() {
    grep -xF "HYPRLAND_INSTANCE_SIGNATURE=$sig" >/dev/null < <(tr '\0' '\n' <"/proc/$1/environ" 2>/dev/null)
}
if [ -n "${GUTTER_RESCUE_KILL_CMD:-}" ]; then
    read -r -a kill_cmd <<<"$GUTTER_RESCUE_KILL_CMD"
    step timeout -k 2 "$kill_wait" "${kill_cmd[@]}" || true
elif [ -n "$dry" ]; then
    printf 'would run: timeout -k 2 %q' "$kill_wait"
    printf ' %q' qs "${qs_select[@]}" kill --pid
    printf ' <each pid of'
    printf ' %q' qs "${qs_select[@]}" list --json
    printf ' that runs in instance %s>\n' "$sig"
else
    for pid in $(listed); do
        is_qs "$pid" || continue
        if ! in_instance "$pid"; then
            echo "rescue-unlock: a qs (pid $pid) is not (or cannot be shown to be) in instance $sig, so it is not asked to quit and is left running" >&2
            continue
        fi
        timeout -k 2 "$kill_wait" qs "${qs_select[@]}" kill --pid "$pid" || true
    done
fi
if [ -n "$dry" ]; then
    printf 'would run: kill -KILL <each pid of'
    printf ' %q' qs "${qs_select[@]}" list --json
    printf ' that runs in instance %s and did not end>\n' "$sig"
else
    # An instance that did not answer `kill` is still listed (give one that does a moment to go): its pid, from the
    # registry of this runtime dir, is ended.
    pids=""
    for _ in 1 2 3 4 5 6 7 8; do
        pids=""
        for pid in $(listed); do
            if is_qs "$pid" && in_instance "$pid"; then
                pids+=" $pid"
            fi
        done
        [ -n "$pids" ] || break
        sleep "$poll"
    done
    for pid in $pids; do
        echo "rescue-unlock: the lock screen (pid $pid) did not end; killing it" >&2
        kill -KILL "$pid" 2>/dev/null || true
    done
    [ -z "$pids" ] || sleep "$settle"
fi

# 3. The rescue shell takes the lock and lets it go (or exits non-zero if the compositor refuses it).
rescue_wait="${GUTTER_RESCUE_TIMEOUT:-15}"
rc=0
# QT_QPA_PLATFORM=wayland for this step only: from a TTY the environment may name nothing and Qt could fall back to xcb.
QT_QPA_PLATFORM=wayland step timeout -k 2 "$rescue_wait" qs -p "$here/lockscreen/rescue" || rc=$?
if [ "$rc" -ne 0 ]; then
    if [ "$rc" -eq 124 ]; then
        echo "rescue-unlock: the rescue shell did not finish within ${rescue_wait} s; the session is still locked (the LockedHint is kept). Try again, or run it from a TTY after ending the lock screen by hand." >&2
    else
        echo "rescue-unlock: the rescue shell failed (exit $rc); the session is still locked (the LockedHint is kept)" >&2
    fi
    exit "$rc"
fi

# 4. The lock is gone, so the "left locked" marks go too.
if [ -n "${GUTTER_LOCK_HINT_FILE:-}" ]; then
    if [ -n "$dry" ]; then
        echo "would run: printf 'false\\n' > $GUTTER_LOCK_HINT_FILE"
    else
        printf 'false\n' >"$GUTTER_LOCK_HINT_FILE"
    fi
elif [ -n "$session" ]; then
    step busctl --system call org.freedesktop.login1 "$(session_path "$session")" org.freedesktop.login1.Session SetLockedHint b false \
        || echo "rescue-unlock: could not clear the LockedHint; Gutter may lock again at its next start" >&2
else
    echo "rescue-unlock: no graphical session found to clear the LockedHint (set GUTTER_RESCUE_SESSION)" >&2
fi

cat >&2 <<DONE
Unlocked. Start Gutter again through the compositor (a bare TTY cannot run it itself):
  HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl eval 'hl.exec_cmd("qs -c gutter -n -d")'
or log out and in.
DONE
