#!/usr/bin/env bash
# Runs tests/auth/shell.qml in Quickshell, offscreen, once per scenario: the real services/Auth.qml against a dummy
# PAM folder (scripts/lock-test-pam.sh, password "guttertest") or one made to be refused, with an `fprintd-list`
# shim as the only one on PATH. Nothing here reaches the account's own PAM stack, and the lock is never taken: the
# scenarios are the password check and its busy guard and timeout, a PAM folder without the stack, a fprintd-list
# that never answers, begin() twice, and the fingerprint setting changing while locked. Like scripts/lock-qml.sh,
# each run is from a scratch config root that links the repo's folders, with a private environment (home, XDG
# folders, a PATH of a few tools, a user that does not exist), and no typed password may be in a run's log.
set -uo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
command -v qs >/dev/null || { echo "auth: qs is not installed" >&2; exit 1; }
qs_bin="$(command -v qs)"
# A short path (the IPC socket lives in it) without symlinks (the PAM folder is compared with it by its real path).
work="$(mktemp -d /tmp/gutter-auth.XXXXXX)" || exit 1
work="$(cd "$work" && pwd -P)" && [ -d "$work" ] || exit 1
trap 'rm -rf "$work"' EXIT

root="$work/root"
mkdir "$root" "$root/services"
for d in bar components dev ipc launcher lib pill scripts settings theme wallpaper; do
    ln -s "$dir/$d" "$root/$d"
done
for f in "$dir"/services/*; do
    ln -s "$f" "$root/services/"
done
cp "$dir/tests/auth/shell.qml" "$root/shell.qml"

failed=0
wrong=nottherightone
fail() {
    echo "auth: $1 FAIL: $2"
    failed=1
}

# The shims for fprintd-list, written into $1 (the scenario's only PATH folder, which also holds the few tools the
# shims and the harness use). The ones that log write to $AUTH_DIR/probes.
shim() {
    local kind="$1" bin="$2" tool
    mkdir -p "$bin"
    for tool in bash sleep cat mkdir; do
        ln -s "$(command -v "$tool")" "$bin/$tool"
    done
    case "$kind" in
        none)
            printf '#!%s\necho "found 1 devices"\necho "User $1 has no fingerprints enrolled for Reader."\n' "$bin/bash" ;;
        enrolled)
            printf '#!%s\necho start >>"$AUTH_DIR/probes"\nsleep 0.4\necho done >>"$AUTH_DIR/probes"\necho "Fingerprints for user $1 on Reader (swipe):"\necho " - #0: right-index-finger"\n' "$bin/bash" ;;
        hang)
            printf '#!%s\necho $$ >"$AUTH_DIR/probe.pid"\nexec sleep 300\n' "$bin/bash" ;;
    esac >"$bin/fprintd-list"
    chmod +x "$bin/fprintd-list"
}

# run <scenario[-variant]> <fprintd-list shim> <PAM folder kind>; fails (1) when it could not get as far as qs.
run() {
    local name="$1" kind="$2" pamkind="$3"
    local scratch="$work/$name" pam=""
    mkdir -p "$scratch/config" "$scratch/home"
    mkdir -m 700 "$scratch/run"
    shim "$kind" "$scratch/bin"
    case "$pamkind" in
        dummy) pam="$("$dir/scripts/lock-test-pam.sh" "$scratch")" || { fail "$name" "no test PAM folder"; return 1; } ;;
        slow | stuck)
            pam="$("$dir/scripts/lock-test-pam.sh" "$scratch")" || { fail "$name" "no test PAM folder"; return 1; }
            # Each run of the check is logged (pam_exec gives the script no environment: the path is written in).
            local nap=1
            [ "$pamkind" = stuck ] && nap=3
            printf '#!/usr/bin/env bash\nIFS= read -r given\necho run >>"%s/runs"\nsleep %s\n[ "$given" = "guttertest" ]\n' "$scratch" "$nap" >"$pam/check.sh"
            ;;
        nofprint)
            pam="$("$dir/scripts/lock-test-pam.sh" "$scratch")" || { fail "$name" "no test PAM folder"; return 1; }
            rm "$pam/fprint"
            ;;
        missing) pam="$scratch/nonexistent" ;;
        empty)
            pam="$scratch/empty"
            mkdir "$pam"
            ;;
        emptyfile)
            pam="$("$dir/scripts/lock-test-pam.sh" "$scratch")" || { fail "$name" "no test PAM folder"; return 1; }
            : >"$pam/passwd"
            : >"$pam/fprint"
            ;;
    esac
    # The scenario that follows the config file starts from a file that is current (so nothing migrates or rewrites it)
    # and has the fingerprint on, rather than from Settings' first run, which creates the file while the scenario runs.
    if [ "${name%%-*}" = setting ]; then
        local version
        version="$(sed -n 's/^[[:space:]]*\(var\|let\|const\)[[:space:]]\{1,\}CONFIG_VERSION[[:space:]]*=[[:space:]]*\([0-9]\{1,\}\).*/\2/p' "$dir/lib/config.js" | head -n 1)"
        [ -n "$version" ] || { fail "$name" "no CONFIG_VERSION in lib/config.js"; return 1; }
        mkdir -p "$scratch/config/gutter"
        printf '{"configVersion": %s, "lockscreen": {"fingerprint": true}}\n' "$version" >"$scratch/config/gutter/config.json"
    fi
    # Without a folder named, Auth would use the repo's own stack: the account's.
    [ -n "$pam" ] || { fail "$name" "no PAM folder named"; return 1; }
    local log="$scratch/log"
    timeout 30 env -i PATH="$scratch/bin" HOME="$scratch/home" XDG_CONFIG_HOME="$scratch/config" \
        XDG_STATE_HOME="$scratch/home/.local/state" XDG_DATA_HOME="$scratch/home/.local/share" XDG_RUNTIME_DIR="$scratch/run" \
        USER=gutter-test AUTH_SCENARIO="${name%%-*}" AUTH_WRONG="$wrong" AUTH_DIR="$scratch" GUTTER_LOCK_PAM_DIR="$pam" \
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic "$qs_bin" -p "$root" >"$log" 2>&1
    local status=$?
    grep -E 'auth: ' "$log" | sed -E 's/^.*(auth: )/\1/' | sed -E "s/^auth: ${name%%-*} /auth: $name /"
    if ! grep -qE "auth: ${name%%-*} ok" "$log"; then
        failed=1
        if [ "$status" -eq 124 ]; then
            echo "auth: $name FAIL: timed out"
        elif ! grep -qE "auth: ${name%%-*} FAIL" "$log"; then
            echo "auth: $name FAIL: did not finish (qs exit $status)"
        fi
    fi
    if grep -E 'ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign' "$log"; then
        fail "$name" "QML errors"
    fi
    if grep -qE "guttertest|$wrong" "$log"; then
        fail "$name" "a typed password is in the log"
    fi
    return 0
}

# Lines in a scratch file (0 when it is not there).
lines() {
    local n
    n=$(grep -c "$2" "$work/$1" 2>/dev/null) || n=0
    echo "$n"
}

# expect <scenario> <what> <got> <want>
expect() {
    if [ "$3" != "$4" ]; then
        fail "$1" "$2: got $3, want $4"
    fi
}

# warned <scenario> <fixed text>: the text is in the scenario's log.
warned() {
    grep -qsF "$2" "$work/$1/log" || fail "$1" "no warning \"$2\" in the log"
}

run password none dummy
if run busy none slow; then
    expect busy "runs of the check" "$(lines busy/runs run)" 1
fi
if run timeout none stuck; then
    expect timeout "runs of the check" "$(lines timeout/runs run)" 1
    warned timeout "the password check timed out"
fi
for kind in missing empty emptyfile; do
    if run "refused-$kind" enrolled "$kind"; then
        expect "refused-$kind" "fprintd-list runs" "$(lines "refused-$kind/probes" start)" 0
        warned "refused-$kind" 'has no readable, non-empty "passwd" file, refusing to use PAM'
    fi
done
if run nofprint enrolled nofprint; then
    expect nofprint "fprintd-list runs" "$(lines nofprint/probes start)" 0
    warned nofprint 'has no readable, non-empty "fprint" file, refusing to use PAM'
fi
run hanging hang dummy
if run twice enrolled dummy; then
    # The first begin()'s probe is killed by the second one's end() (whether or not it had spawned yet), so one finishes.
    expect twice "probes that finished" "$(lines twice/probes done)" 1
    warned twice "Auth.begin() while already begun"
fi
if run setting enrolled dummy; then
    expect setting "probes" "$(lines setting/probes done)" 2
fi

if [ "$failed" -ne 0 ]; then
    echo "auth: FAIL"
    exit 1
fi
echo "auth: OK"
