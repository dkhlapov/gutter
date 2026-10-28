#!/usr/bin/env bash
# Runs the lock's Quickshell checks, offscreen, from a scratch config root that links the repo's folders (like
# scripts/fit.sh and scripts/centring.sh):
# - tests/lockqml/auth.qml: the real services/Auth.qml against the test PAM folder (scripts/lock-test-pam.sh) and stub
#   `fprintd-list`s, for the fingerprint probe and the password flow.
# - tests/lockqml/idle.qml: the real services/Idle.qml and Lock.qml in a dry run, with `gdbus monitor` on a private
#   session bus where tests/lockqml/fake_logind.py plays logind: sleep, resume, the session's Lock, the retry of a
#   dropped lock request, the lock timeout, and the monitor ending. Only Media is a stub (tests/lockqml/stubs).
# Home, XDG folders, PATH and the bus are private, so the account's PAM, state and session bus are never touched.
# Needs: qs, gdbus, dbus-daemon (the private bus) and python3 with PyGObject and its Gio typelib (`gi`, for the fake logind).
set -uo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
command -v qs >/dev/null || { echo "lock-qml: qs is not installed" >&2; exit 1; }
command -v gdbus >/dev/null || { echo "lock-qml: gdbus is not installed (the idle check watches logind with it)" >&2; exit 1; }
command -v dbus-daemon >/dev/null || { echo "lock-qml: dbus-daemon is not installed (the idle check's private bus)" >&2; exit 1; }
python3 -I -c 'import gi; gi.require_version("Gio", "2.0"); from gi.repository import Gio' 2>/dev/null ||
    { echo "lock-qml: python3 is missing or cannot import gi with Gio (PyGObject, for the idle check's fake logind)" >&2; exit 1; }
root="$(mktemp -d /tmp/gl.XXXXXX)"
bus_pid=""
bus_start=""
stub_pid=""
stub_start=""
# start_of pid: the process's start time (field 22 of /proc/<pid>/stat, after the command name, which may hold spaces).
start_of() {
    local s
    read -r s 2>/dev/null <"/proc/$1/stat" || return 1
    s="${s##*) }"
    read -r -a s <<<"$s"
    echo "${s[19]}"
}
# stop pid start: ends a job this script launched, if the pid is still that process (bash reaps a job that ended on its
# own, and the pid may then be anyone's). Never by name.
stop() {
    [ -n "$1" ] && [ -n "$2" ] && [ "$(start_of "$1")" = "$2" ] && kill "$1" 2>/dev/null
}
cleanup() {
    stop "$stub_pid" "$stub_start"
    stop "$bus_pid" "$bus_start"
    wait "$stub_pid" "$bus_pid" 2>/dev/null
    rm -rf "$root"
}
trap cleanup EXIT

for d in bar components dev ipc launcher lib pill scripts settings theme wallpaper; do
    ln -s "$dir/$d" "$root/$d"
done
mkdir "$root/services" "$root/home" "$root/pam"
mkdir -m 700 "$root/run"
for f in "$dir"/services/*; do
    ln -s "$f" "$root/services/"
done
pam="$("$dir/scripts/lock-test-pam.sh" "$root/pam")" || exit 1
qs_bin="$(command -v qs)"

fail=0
wrong=nottherightone
bad() {
    echo "lock-qml: FAIL ($1)"
    fail=1
}

# A PATH folder with bash (the stub's interpreter), mkdir (the settings make their folder) and, for some
# scenarios, a stub fprintd-list. Nothing else is on the PATH, so the real fprintd-list is never found.
shim() {
    local bin="$root/bin-$1"
    mkdir "$bin"
    ln -s "$(command -v bash)" "$bin/bash"
    ln -s "$(command -v mkdir)" "$bin/mkdir"
    if [ -n "${2:-}" ]; then
        printf '#!%s\nprintf "%%s\\n" %q\n' "$bin/bash" "$2" >"$bin/fprintd-list"
        chmod +x "$bin/fprintd-list"
    fi
    echo "$bin"
}

# Runs one scenario of a harness shell (tests/lockqml/<qml>), with more environment after the PATH folder if given; its
# log is $root/log-<scenario>.
scenario() {
    local name="$1" qml="$2" bin="$3"
    shift 3
    local log="$root/log-$name"
    cp "$dir/tests/lockqml/$qml" "$root/shell.qml"
    timeout 60 env -i PATH="$bin" HOME="$root/home" XDG_CONFIG_HOME="$root/home/.config" XDG_STATE_HOME="$root/home/.local/state" \
        XDG_DATA_HOME="$root/home/.local/share" XDG_RUNTIME_DIR="$root/run" USER=gutter-test \
        GUTTER_LOCK_PAM_DIR="$pam" GUTTER_LOCK_HINT_FILE="$root/hint" GUTTER_IDLE_DRY_RUN=1 GUTTER_POWER_DRY_RUN=1 \
        GUTTER_LAUNCHER_DRY_RUN=1 LOCKQML_SCENARIO="$name" LOCKQML_WRONG="$wrong" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
        QSG_RENDER_LOOP=basic "$@" "$qs_bin" -p "$root" >"$log" 2>&1
    grep -E 'lockqml: ' "$log" | sed -E 's/^.*(lockqml: )/\1/'
    local errors='ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign'
    if grep -qE "$errors" "$log"; then
        grep -E "$errors" "$log"
        bad "$name: QML errors"
    fi
    grep -q 'lockqml: OK' "$log" || bad "$name: did not finish OK"
    # The password is typed in two scenarios and must be in no log, nor the wrong one.
    if grep -qE "guttertest|$wrong" "$log"; then
        bad "$name: a typed password is in the log"
    fi
}

# How often the log has the missing-fprintd-list warning.
warnings() {
    grep -cF 'gutter: lock: fprintd-list did not start, no fingerprint' "$root/log-$1" || true
}

scenario nofprintd auth.qml "$(shim none)"
[ "$(warnings nofprintd)" = 1 ] || bad "nofprintd: the missing fprintd-list is warned about $(warnings nofprintd) times, not once"

fprintd=$'found 1 devices\nDevice at /x\nFingerprints for user gutter-test on Reader (swipe):\n - #0: right-index-finger'
scenario fingerprint auth.qml "$(shim print "$fprintd")"
[ "$(warnings fingerprint)" = 0 ] || bad "fingerprint: a warning although fprintd-list runs"

scenario noprints auth.qml "$(shim empty $'found 1 devices\nDevice at /x\nUser gutter-test has no fingerprints enrolled for Reader.')"
[ "$(warnings noprints)" = 0 ] || bad "noprints: a warning although fprintd-list runs"

scenario password auth.qml "$(shim password)"

# --- idle: a private bus, a fake logind on it, and the monitor Idle starts reading it ---------------------------------

# The bus has no service folders, so nothing on the machine is ever started by a name asked for on it.
cat >"$root/bus.conf" <<EOF
<busconfig>
  <type>session</type>
  <listen>unix:path=$root/bus</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF
dbus-daemon --config-file="$root/bus.conf" --nofork >"$root/bus-log" 2>&1 &
bus_pid=$!
bus_start="$(start_of "$bus_pid")"
# The pid and start time, so that the harness shell ends the bus only while it is still this process.
echo "$bus_pid $bus_start" >"$root/bus.pid"
bus="unix:path=$root/bus"
mkfifo "$root/fifo"
# Held open here too, so that a write never blocks, even when the fake logind has gone (only this script holds it:
# the children close it).
exec 3<>"$root/fifo"
for _ in $(seq 50); do
    [ -S "$root/bus" ] && break
    sleep 0.1
done
env -i PATH="$PATH" DBUS_SESSION_BUS_ADDRESS="$bus" python3 -I "$dir/tests/lockqml/fake_logind.py" "$root/fifo" "$root/logind-log" 2>>"$root/logind-log" 3<&- &
stub_pid=$!
stub_start="$(start_of "$stub_pid")"
for _ in $(seq 50); do
    grep -qx ready "$root/logind-log" 2>/dev/null && break
    sleep 0.1
done
if grep -qx ready "$root/logind-log" 2>/dev/null; then
    # bash, mkdir, sh and gdbus, and for `cat` (the sleep helper in a dry run) a wrapper that notes its pid for the probe.
    idlebin="$root/bin-idle"
    mkdir "$idlebin"
    for tool in bash mkdir sh gdbus; do
        ln -s "$(command -v "$tool")" "$idlebin/$tool"
    done
    printf '#!%s\necho $$ >%q\nexec %q "$@"\n' "$idlebin/bash" "$root/helper.pid" "$(command -v cat)" >"$idlebin/cat"
    chmod +x "$idlebin/cat"
    ln -sf "$dir/tests/lockqml/stubs/Media.qml" "$root/services/Media.qml"

    scenario idle idle.qml "$idlebin" DBUS_SESSION_BUS_ADDRESS="$bus" XDG_SESSION_ID=gutter-test GUTTER_LOCK_DRY_RUN=1 \
        'GUTTER_IDLE_MONITOR_CMD=["gdbus","monitor","--session","--dest","org.freedesktop.login1"]' \
        LOCKQML_FIFO="$root/fifo" LOCKQML_HELPER_PID="$root/helper.pid" LOCKQML_BUS_PID="$root/bus.pid" 3<&-
    # The one lock request made while Lock's own dry run was off is refused by Idle, and said so.
    [ "$(grep -cF 'dry run, not asking for a lock (sleep)' "$root/log-idle")" = 1 ] || bad "idle: the refused lock request is not noted exactly once"
    grep -qF 'gutter: idle: the logind monitor stopped (' "$root/log-idle" || bad "idle: the end of the monitor is not noted"
    grep -qF 'starting it again in 1 s' "$root/log-idle" || bad "idle: the first pause before the monitor starts again is not 1 s"
    # A monitor command Idle could not take falls back to the real system bus.
    grep -qF 'GUTTER_IDLE_MONITOR_CMD is not a JSON array' "$root/log-idle" && bad "idle: the monitor command was not taken"
    grep -qF 'gutter: idle: the sleep inhibitor' "$root/log-idle" && bad "idle: the sleep helper failed"
    # The queued request that was left unanswered is dropped with its warning, once.
    [ "$(grep -cF 'queued request dropped' "$root/log-idle")" = 1 ] || bad "idle: the dropped queued request is not warned about exactly once"
    # What the fake logind sent: sleep and resume, and our session's and another's Lock, and our Unlock.
    for sent in 'Manager.PrepareForSleep (true,)' 'Manager.PrepareForSleep (false,)' 'gutter_2dtest org.freedesktop.login1.Session.Lock ()' \
        '_33 org.freedesktop.login1.Session.Lock ()' 'gutter_2dtest org.freedesktop.login1.Session.Unlock ()'; do
        grep -qF "$sent" "$root/logind-log" || bad "idle: the fake logind never sent $sent"
    done
    grep -qE 'unknown command|Traceback' "$root/logind-log" && bad "idle: the fake logind failed"
else
    bad "idle: the fake logind did not start"
fi
if [ "$fail" != 0 ]; then
    echo "--- fake logind:"
    cat "$root/logind-log" 2>/dev/null
    echo "--- idle log:"
    tail -n 40 "$root/log-idle" 2>/dev/null
fi

[ "$fail" = 0 ] && echo "lock-qml: OK"
exit "$fail"
