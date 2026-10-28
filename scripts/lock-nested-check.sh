#!/usr/bin/env bash
# Opt-in checks of the lock screen's real session-lock path, in a nested Hyprland (scripts/lock-nested.sh). Not part of
# scripts/test.sh: the nested compositor opens as a window in the Wayland session you run this from (Hyprland 0.56 has no
# headless-only mode), so it needs one, and the window is on your desktop for the 15 seconds or so a run takes. Do not type
# into it or click anywhere meanwhile: the nested compositor's keyboard is the outer one's.
#
# Usage: lock-nested-check.sh [--skip-if-no-session]
#   --skip-if-no-session  without WAYLAND_DISPLAY and HYPRLAND_INSTANCE_SIGNATURE print SKIP and exit 0 (for a runner
#                         that may or may not have a session); otherwise that is an error (exit 1)
# Exit codes: 0 every check passed (or SKIP); 1 a check failed or the setup did; 2 bad usage.
# Environment:
#   GUTTER_NESTED_CHECK_KEEP=1  keep the session's folders (logs) after the run
#   GUTTER_NESTED_CHECK_SETTLE  seconds the teardown gives the session's processes to end by themselves after the
#                               harness's stop (default 10, whole decimal seconds, leading zeros allowed; the tests
#                               shorten it)
#
# What it checks, in the nested session (state is read from Gutter's IPC `lock isLocked`, the LockedHint file the test
# setup uses instead of logind, `hyprctl monitors`, qs.log and process liveness):
#   1. lock: the lock is taken, the compositor confirms it (the hint file says true), no QML error;
#   2. outputs added and removed while locked: still locked, the same shell process, no error or protocol error;
#   3. the shell ended (TERM, KILL) or frozen (STOP/CONT) while locked: the compositor keeps the session locked; a new
#      shell locks again ("the session was left locked, locking again");
#   4. a hot reload while locked (a QML file changed): the lock carries over, the shell is the same process;
#   5. scripts/rescue-unlock.sh --force --instance <nested> with the lock client ended: the rescue shell takes the lock
#      and releases it, exits 0, the hint says false, and the next Gutter starts unlocked.
# What those observations are. Nothing asks the compositor whether the session is locked, so "the compositor keeps the
# session locked" is a proxy: the hint file stays true (Gutter wrote it when the compositor confirmed the lock, and
# nothing clears it but an unlock) and a new shell takes the lock again (which, without a lock still held, would not
# be reported as a restore of a left lock). "The next shell starts unlocked" is that shell's own state (Lock.locked,
# its hint file said false), not the compositor's. The rescue shell exits 0 only after the compositor confirmed its lock
# and the lock was released, which is the check of the compositor's side there.
# Not covered: the password path (LockScreen's finishUnlock; there is no safe way to send keys into the nested
# compositor) and the rescue script on a real TTY.
#
# Safety. It never touches the outer session: it runs the harness only (which gives every hyprctl, qs and the rescue
# script the nested compositor's own runtime dir, signature and display), never calls `loginctl lock-session`, and
# runs everything from a scratch COPY of the checkout (so the hot reload edits the copy, never the checkout, and the
# checkout's .qmlls.ini is not touched). The nested compositor has a watchdog and is always ended (trap). At the end
# every process of the session is gone. A process counts as the session's, and only then is ended (by pid, never by
# name), if it is this user's with exactly the session's runtime dir in its environment, or one of this script's own
# descendants (the harness's runner and the `timeout` around its compositor), recorded with its start time. Anything
# of the session still running after the harness's stop (and a short settle time) is ended and fails the run; the
# harness's fake logind monitor (`tail --pid` of the shell) ends with its shell, so nothing is exempt. A process that
# merely names the session's folders in its command line (a `tail -f` of its log, an editor) is reported and left
# alone. The compositor's pid and the session's folders are checked to be gone too.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

skip=0
case "${1:-}" in
    '') ;;
    --skip-if-no-session) skip=1 ;;
    *)
        echo "usage: lock-nested-check.sh [--skip-if-no-session]" >&2
        exit 2
        ;;
esac
[ "$#" -le 1 ] || { echo "usage: lock-nested-check.sh [--skip-if-no-session]" >&2; exit 2; }
settle="${GUTTER_NESTED_CHECK_SETTLE:-10}"
case "$settle" in
    '' | *[!0-9]*)
        echo "lock-nested-check: GUTTER_NESTED_CHECK_SETTLE must be whole seconds" >&2
        exit 2
        ;;
esac
settle=$((10#$settle)) # decimal even with leading zeros (08 would be a bad octal number, 010 eight)

if [ -z "${WAYLAND_DISPLAY:-}" ] || [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    if [ "$skip" -eq 1 ]; then
        echo "lock-nested-check: SKIP (needs a running Wayland/Hyprland session: WAYLAND_DISPLAY and HYPRLAND_INSTANCE_SIGNATURE)"
        exit 0
    fi
    echo "lock-nested-check: needs a running Wayland/Hyprland session (WAYLAND_DISPLAY and HYPRLAND_INSTANCE_SIGNATURE are not both set); --skip-if-no-session makes this a skip" >&2
    exit 1
fi
for tool in Hyprland dbus-daemon qs hyprctl git tar timeout; do
    command -v "$tool" >/dev/null || { echo "lock-nested-check: $tool is not installed" >&2; exit 1; }
done

outer_sig="$HYPRLAND_INSTANCE_SIGNATURE"
dir="/tmp/gn-chk-$$"      # the nested session's folder (the harness removes it)
src="/tmp/gn-chk-$$.src"  # a copy of the checkout the session runs from
outd="/tmp/gn-chk-$$.out" # this script's own output files, outside the config root
export GUTTER_NESTED_DIR="$dir"
export GUTTER_NESTED_TIMEOUT=240
[ "${GUTTER_NESTED_CHECK_KEEP:-}" != 1 ] || export GUTTER_NESTED_KEEP=1
nl="$src/scripts/lock-nested.sh"
fails=0
complete=0
runner=""
cpid=""
rescue_pid=""
qmlls_state() { readlink "$here/.qmlls.ini" 2>/dev/null || stat -c '%s %Y' "$here/.qmlls.ini" 2>/dev/null || echo none; }
qmlls_before="$(qmlls_state)"

# A leftover of an earlier run's pid is never taken over: refuse before any trap that would clean it up.
for d in "$dir" "$src" "$outd"; do
    [ ! -e "$d" ] || { echo "lock-nested-check: $d exists" >&2; exit 1; }
done
git -C "$here" rev-parse --git-dir >/dev/null 2>&1 || { echo "lock-nested-check: $here is not a git checkout" >&2; exit 1; }

pass() { echo "ok - $*"; }
fail() {
    echo "not ok - $*"
    fails=$((fails + 1))
    return 1
}
# check "what" command...: the command succeeds.
check() {
    local what="$1"
    shift
    if "$@"; then pass "$what"; else fail "$what"; fi
}
# wait_for seconds command...: polls (a quarter second apart) until the command succeeds.
wait_for() {
    local end=$((SECONDS + $1))
    shift
    while true; do
        "$@" && return 0
        [ "$SECONDS" -lt "$end" ] || return 1
        sleep 0.25
    done
}

# Everything aimed at the nested session goes through the harness.
nested() { "$nl" "$@"; }
ipc() { timeout -k 2 8 "$nl" ipc "$@" 2>/dev/null; }
ctl() { timeout -k 2 8 "$nl" ctl "$@" 2>/dev/null; }
locked() { [ "$(ipc call lock isLocked)" = true ]; }
unlocked() { [ "$(ipc call lock isLocked)" = false ]; }
hint_is() { [ "$(cat "$dir/hint" 2>/dev/null)" = "$1" ]; }
shell_pid() { cat "$dir/qs.pid" 2>/dev/null; }
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
gone() { ! alive "$1"; }
state() { sed -n 's/^State:[[:space:]]*\(.\).*/\1/p' "/proc/$1/status" 2>/dev/null; }
stopped() { [ "$(state "$1")" = T ]; }
monitors() { ctl monitors | grep -c '^Monitor'; }
monitors_ge() { [ "$(monitors)" -ge "$1" ]; }
monitors_gt() { [ "$(monitors)" -gt "$1" ]; }
monitors_eq() { [ "$(monitors)" -eq "$1" ]; }
# The names of the nested outputs.
monitor_names() { ctl monitors | sed -n 's/^Monitor \([^ ]*\) .*/\1/p'; }
# Lines of qs.log from line $1 on.
log_from() { tail -n "+$(($1 + 1))" "$dir/qs.log" 2>/dev/null; }
log_lines() { wc -l 2>/dev/null <"$dir/qs.log" || echo 0; }
log_has() { log_from "$1" | grep -q -- "$2"; }

# Errors in a log (stdin). Two kinds of known noise of the nested session are not counted: Quickshell's PipeWire
# service finds no PipeWire there, and the bar, pill and launcher windows warn about a null screen (its name, height
# or width) while an output comes or goes (and at start); neither is the lock's. Quickshell's "Session lock object was
# destroyed without unlocking" (and the line after it) is what the real logs show on a reload while locked and when the
# rescue ends the lock screen (not when the shell is TERM'd or KILLed), so it is allowed only there (argument 1 = allow).
bad_log='ERROR|TypeError|ReferenceError|is not a type|Cannot assign|Unable to assign|Aborting|rotocol error|Segmentation|terminated|core dumped'
noise_log="quickshell\\.service\\.pipewire|@(pill|bar|launcher)/[A-Za-z]+\\.qml\\[[0-9:-]+\\]: TypeError: Cannot read property '(name|height|width)' of null"
destroyed_log='Session lock object was destroyed without unlocking|Component\.onDestruction may be used if this behavior is required'
filter_bad() {
    if [ "${1:-}" = 1 ]; then
        grep -E "$bad_log" | grep -vE "$noise_log" | grep -vE "$destroyed_log"
    else
        grep -E "$bad_log" | grep -vE "$noise_log"
    fi
}
# log_clean mark [allow]: no error in qs.log since line mark.
log_clean() { ! log_from "$1" | filter_bad "${2:-}" | grep . >/dev/null; }
show_bad() { log_from "$1" | filter_bad "${2:-}" | head -5 | sed 's/^/    log: /'; }

# The session's processes, found in /proc, never by name. Ours (and only ours are ever ended) are (a) this user's
# processes with exactly the session's runtime dir in their environment (everything the harness runs in the session:
# compositor, bus, shells, their helpers, hyprctl and qs calls, the rescue run) and (b) this script's descendants as
# recorded by `snapshot` (the harness's runner and the `timeout` around its compositor have the outer environment),
# by pid and start time, so a pid used again by another process is not taken for one.
uid="$(id -u)"
ours_snap=""
pid_of() {
    local p="${1#/proc/}"
    echo "${p%%/*}"
}
start_of() {
    local s
    read -r s 2>/dev/null <"/proc/$1/stat" || return 1
    s="${s##*) }" # after the command name, which may hold spaces; the start time is field 22 of the whole line
    read -r -a s <<<"$s"
    echo "${s[19]}"
}
# env_ours pid: the process is this user's and has exactly the session's runtime dir in its environment.
env_ours() {
    [ "$(stat -c %u "/proc/$1" 2>/dev/null)" = "$uid" ] &&
        grep -qazxF "XDG_RUNTIME_DIR=$dir/run" "/proc/$1/environ" 2>/dev/null
}
# snap_ours pid: the process is one `snapshot` recorded, with the same start time.
snap_ours() {
    local st
    st="$(start_of "$1")" && [ -n "$st" ] && grep -qxF "$1:$st" <<<"$ours_snap"
}
# still_ours pid: asked again right before each signal, so a pid that changed hands in between is left alone.
still_ours() { [ -n "$1" ] && [ "$1" != "$$" ] && { env_ours "$1" || snap_ours "$1"; }; }
# remember pid: records a job this script just launched (pid and start time), for still_ours. A job already gone is
# not recorded, so it is never signalled.
remember() {
    local st
    st="$(start_of "$1")" && [ -n "$st" ] && ours_snap="$(printf '%s\n%s:%s\n' "$ours_snap" "$1" "$st" | grep . | sort -u)"
}
# Lines "pid:start time" of this script's descendants, but for the subshell that asks and what that runs. Call it only
# as `x="$(descendants)"`: the command substitution's own subshell is then $BASHPID, the one child of $$ left out.
descendants() {
    local f s pid ppid p c
    local -A kids=()
    for f in /proc/[0-9]*/stat; do
        read -r s 2>/dev/null <"$f" || continue
        pid="${f#/proc/}"
        pid="${pid%/stat}"
        s="${s##*) }"
        read -r _ ppid _ <<<"$s"
        kids[$ppid]+=" $pid"
    done
    local queue=("$$")
    while [ "${#queue[@]}" -gt 0 ]; do
        p="${queue[0]}"
        queue=("${queue[@]:1}")
        for c in ${kids[$p]:-}; do
            [ "$c" != "$BASHPID" ] || continue
            echo "$c:$(start_of "$c")"
            queue+=("$c")
        done
    done
}
snapshot() {
    local now
    now="$(descendants)"
    ours_snap="$(printf '%s\n%s\n' "$ours_snap" "$now" | grep . | sort -u)"
}
ours_pids() {
    local f pid
    {
        grep -lazxF "XDG_RUNTIME_DIR=$dir/run" /proc/[0-9]*/environ 2>/dev/null | while IFS= read -r f; do
            pid="$(pid_of "$f")"
            env_ours "$pid" && echo "$pid"
        done
        while IFS=: read -r pid _; do
            [ -n "$pid" ] && snap_ours "$pid" && echo "$pid"
        done <<<"$ours_snap"
    } | grep -vxF "$$" | sort -un
}
no_ours_left() { [ -z "$(ours_pids)" ]; }
# end_ours pid...: TERM, then KILL what is still there 3 seconds later; each signal only to a pid that is still ours.
none_ours() {
    local pid
    for pid in "$@"; do ! still_ours "$pid" || return 1; done
}
end_ours() {
    local pid
    [ "$#" -gt 0 ] || return 0
    for pid in "$@"; do still_ours "$pid" && kill -TERM "$pid" 2>/dev/null; done
    wait_for 3 none_ours "$@" && return 0
    for pid in "$@"; do still_ours "$pid" && kill -KILL "$pid" 2>/dev/null; done
    wait_for 2 none_ours "$@"
}
# Processes that are not ours but name the session's folders in their command line: reported, never signalled.
foreign_pids() {
    local f pid ours
    ours="$(ours_pids)"
    grep -lazE "/tmp/gn-chk-$$([./]|\$)" /proc/[0-9]*/cmdline 2>/dev/null | while IFS= read -r f; do
        pid="$(pid_of "$f")"
        [ "$pid" != "$$" ] && ! grep -qxF "$pid" <<<"$ours" && echo "$pid"
    done
}
describe() { printf '%s (%s)' "$1" "$(tr '\0' ' ' 2>/dev/null <"/proc/$1/cmdline" | cut -c1-100 | sed 's/ $//')"; }

teardown_done=0
teardown() {
    [ "$teardown_done" -eq 0 ] || return 0
    teardown_done=1
    trap - EXIT INT TERM HUP
    # Recorded before anything is told to stop: what is ended below leaves orphans that are no longer descendants.
    snapshot
    # The rescue run and the runner are this script's own jobs, but bash reaps a job that ended without being waited
    # for, and its pid can then be another process's: each is signalled only while it is still the one launched (the
    # pid and start time `remember` recorded then).
    [ -z "$rescue_pid" ] || { still_ours "$rescue_pid" && kill -TERM "$rescue_pid" 2>/dev/null; }
    if [ -n "$runner" ] && still_ours "$runner"; then
        # The harness ends its compositor, shell and bus itself, when told to (`stop` needs its record, else TERM the runner).
        { [ -f "$dir/env" ] && "$nl" stop >/dev/null 2>&1; } || { still_ours "$runner" && kill -TERM "$runner" 2>/dev/null; }
        local i
        for i in $(seq 1 40); do
            still_ours "$runner" || break
            sleep 0.25
        done
        still_ours "$runner" && kill -KILL "$runner" 2>/dev/null
        wait "$runner" 2>/dev/null
    fi
    # What the session left running goes by itself soon after the harness's stop (a helper of a killed shell, such as
    # the fake logind monitor's tail, which checks once a second whether its shell still runs, takes a moment).
    # Anything of ours still there then is ended, by pid, and fails: the harness's stop did not end it.
    local pid strays=()
    wait_for "$settle" no_ours_left
    for pid in $(ours_pids); do strays+=("$pid"); done
    if [ "${#strays[@]}" -gt 0 ]; then
        fail "not ended by the harness's stop (ended by pid now):$(
            for pid in "${strays[@]}"; do printf ' %s' "$(describe "$pid")"; done)"
    fi
    end_ours "${strays[@]}"
    check "no process of the session is left" wait_for 3 no_ours_left
    for pid in $(foreign_pids); do
        echo "note - not ours, left alone: $(describe "$pid")"
    done
    if [ -n "$cpid" ]; then
        check "the nested compositor (pid $cpid) is gone" gone "$cpid"
    fi
    if [ "${GUTTER_NESTED_CHECK_KEEP:-}" != 1 ] && [ -d "$dir" ]; then
        fail "$dir was not removed"
        rm -rf "$dir"
    fi
    if [ "${GUTTER_NESTED_CHECK_KEEP:-}" = 1 ]; then
        echo "lock-nested-check: kept $dir, $src and $outd" >&2
    else
        rm -rf "$src" "$outd"
    fi
    check "the checkout's .qmlls.ini is as it was" test "$(qmlls_state)" = "$qmlls_before"
    # Ending early (a setup that failed, a signal) is a failure even when no check had run.
    if [ "$fails" -eq 0 ] && [ "$complete" -ne 1 ]; then
        fails=1
        echo "lock-nested-check: ended before the checks were done"
    fi
    if [ "$fails" -eq 0 ]; then
        echo "lock-nested-check: OK"
    else
        echo "lock-nested-check: FAIL ($fails)"
    fi
}
finish() {
    teardown
    [ "$fails" -eq 0 ]
    exit $?
}
# A setup that failed: said, counted, cleaned up after.
setup_fail() {
    echo "lock-nested-check: $*" >&2
    fails=$((fails + 1))
    finish
}
trap 'teardown; exit 1' INT TERM HUP
trap 'teardown' EXIT

mkdir -p "$src" "$outd" || setup_fail "cannot make $src"
# A scratch copy of what the checkout holds now (tracked files as they are, a tracked file deleted in the working tree
# left out, untracked ones that are not ignored added), for the hot reload to edit. .claude/ (agent worktrees and
# notes) is left out by name, whatever the local excludes say.
(
    cd "$here" && git ls-files -z --cached --others --exclude-standard -- . ':(exclude).claude' |
        while IFS= read -r -d '' f; do
            # (a folder is a nested repository, worktree or submodule, which git lists as one entry; not copied)
            if [ -d "$f" ] && [ ! -L "$f" ]; then continue; fi
            if [ -e "$f" ] || [ -L "$f" ]; then printf '%s\0' "$f"; fi
        done | tar --null --no-recursion -T - -cf -
) | tar -xf - -C "$src" || setup_fail "cannot copy the checkout"
[ -x "$nl" ] || setup_fail "no $nl in the copy"

echo "lock-nested-check: starting the nested session in $dir (it opens as a window on this desktop; do not touch it)"
"$nl" start >"$outd/start.out" 2>&1 </dev/null &
runner=$!
remember "$runner"

# The record is written last (the runner's pid is its last field), once the session is up.
env_ready_or_runner_gone() { env_ready || ! still_ours "$runner"; }
env_ready() { grep -q '^runner=' "$dir/env" 2>/dev/null; }
if ! wait_for 60 env_ready_or_runner_gone || ! env_ready; then
    cat "$outd/start.out" >&2
    setup_fail "the nested session did not come up"
fi
# shellcheck disable=SC1090
eval "$(sed -n 's/^\(cpid\|sig\|wl\)=/n_\1=/p' "$dir/env")"
cpid="${n_cpid:-}"
sig="${n_sig:-}"
[ -n "$sig" ] && [ -n "$cpid" ] || setup_fail "the nested session's record does not name its instance and compositor"
[ "$sig" != "$outer_sig" ] || setup_fail "the nested instance is the outer one (refusing)"
wait_for 20 monitors_ge 2 || setup_fail "the nested session has fewer than two outputs"
if ! wait_for 60 unlocked; then
    tail -20 "$dir/qs.log" >&2
    setup_fail "Gutter does not answer IPC in the nested session"
fi
pass "the nested session is up ($(monitors) outputs, instance $sig), unlocked"
check "the hint starts false" hint_is false
check "start: no error in qs.log" log_clean 0 || show_bad 0
mark=$(log_lines)

# --- 1. lock ---
ipc call lock lock >/dev/null
check "lock: isLocked turns true" wait_for 10 locked
check "lock: the compositor confirmed it (hint true)" wait_for 10 hint_is true
check "lock: no QML error in qs.log" log_clean "$mark" || show_bad "$mark"
pid0="$(shell_pid)"
check "lock: the shell runs" alive "$pid0"

# --- 2. outputs come and go while locked ---
mark=$(log_lines)
for round in 1 2 3; do
    before="$(monitor_names | sort)"
    count="$(wc -l <<<"$before")"
    ctl output create headless >/dev/null
    check "outputs $round: the new output is there" wait_for 10 monitors_gt "$count"
    new="$(comm -13 <(echo "$before") <(monitor_names | sort) | head -1)"
    if [ -z "$new" ]; then
        fail "outputs $round: found the new output"
        continue
    fi
    sleep 0.5 # a dwell: the lock gets to put a surface on the new output before it goes
    ctl output remove "$new" >/dev/null
    check "outputs $round: the output is gone" wait_for 10 monitors_eq "$count"
    sleep 0.5 # a dwell: the lock gets to drop that surface
done
check "outputs: still locked" wait_for 5 locked
check "outputs: the same shell process" test "$(shell_pid)" = "$pid0"
check "outputs: the shell lives" alive "$pid0"
check "outputs: the hint is still true" hint_is true
check "outputs: no error or protocol error in qs.log" log_clean "$mark" || show_bad "$mark"

# --- 3. the shell dies or hangs while locked ---
for how in kill kill9; do
    mark=$(log_lines)
    nested shell "$how" >/dev/null 2>&1
    check "$how: the shell is gone" wait_for 10 gone "$pid0"
    check "$how: the compositor lives" alive "$cpid"
    check "$how: the compositor still answers" test "$(monitors)" -ge 2
    check "$how: the hint is still true" hint_is true
    nested shell start >/dev/null 2>&1
    check "$how: a new shell locks again" wait_for 20 locked
    check "$how: it says it was left locked" wait_for 5 log_has "$mark" "the session was left locked, locking again"
    check "$how: the hint is true" hint_is true
    pid0="$(shell_pid)"
    check "$how: the new shell runs" alive "$pid0"
    check "$how: no error in qs.log" log_clean "$mark" || show_bad "$mark"
done
mark=$(log_lines)
nested shell hang >/dev/null 2>&1
check "hang: the shell is frozen" wait_for 5 stopped "$pid0"
check "hang: the compositor lives" alive "$cpid"
check "hang: the compositor still answers" test "$(monitors)" -ge 2
check "hang: the hint is still true" hint_is true
nested shell cont >/dev/null 2>&1
check "hang: the shell answers again, locked" wait_for 15 locked
check "hang: the same shell process" test "$(shell_pid)" = "$pid0"
check "hang: no error in qs.log" log_clean "$mark" || show_bad "$mark"

# --- 4. hot reload while locked ---
for round in 1 2; do
    mark=$(log_lines)
    printf '\n// reload check %s\n' "$round" >>"$src/lockscreen/LockSurface.qml"
    check "reload $round: Quickshell reloads" wait_for 15 log_has "$mark" "Configuration Loaded"
    sleep 1 # a dwell: a protocol error from the swap of the lock objects would arrive after the reload said it was done
    check "reload $round: still locked" wait_for 10 locked
    check "reload $round: the same shell process" test "$(shell_pid)" = "$pid0"
    check "reload $round: the hint is still true" hint_is true
    check "reload $round: the compositor lives" alive "$cpid"
    check "reload $round: no error or protocol error in qs.log" log_clean "$mark" 1 || show_bad "$mark" 1
done

# --- 5. the rescue script, against the nested compositor only ---
mark=$(log_lines)
rescue_out="$outd/rescue.out"
(
    eval "$(nested env)"
    # The nested environment is in force from here on; refuse to go on if it is not the nested one.
    case "$XDG_RUNTIME_DIR" in "$dir"/run) ;; *) exit 97 ;; esac
    [ "$HYPRLAND_INSTANCE_SIGNATURE" = "$sig" ] && [ "$sig" != "$outer_sig" ] || exit 98
    export GUTTER_RESCUE_QS="-p $src"
    cd "$src" && echo unlock | timeout -k 2 60 "$src/scripts/rescue-unlock.sh" --force --instance "$sig"
) >"$rescue_out" 2>&1 &
rescue_pid=$!
remember "$rescue_pid"
wait "$rescue_pid"
rc=$?
rescue_pid=""
check "rescue: exits 0" test "$rc" -eq 0
[ "$rc" -eq 0 ] || sed 's/^/    rescue: /' "$rescue_out" | tail -15
check "rescue: its output has no error" test -z "$(filter_bad 1 <"$rescue_out")"
check "rescue: the lock screen was ended" wait_for 10 gone "$pid0"
check "rescue: the hint is false" hint_is false
check "rescue: the compositor lives" alive "$cpid"
nested shell start >/dev/null 2>&1
check "rescue: the next shell starts unlocked" wait_for 30 unlocked
sleep 1 # a dwell: it must stay unlocked (a restore of a left lock would come a moment after the start)
check "rescue: and stays unlocked" unlocked
check "rescue: no error in qs.log" log_clean "$mark" 1 || show_bad "$mark" 1
ipc call lock lock >/dev/null
check "rescue: the session can be locked again" wait_for 10 locked

complete=1
finish
