#!/usr/bin/env bash
# Clipboard watcher for Gutter: prints one line per copy, "t <base64 of the text>" or
# "i <path of a png>" (the png is kept in the directory given as $1). Needs wl-clipboard.
# Copies marked as secrets by a password manager are skipped. Run by services/Clipboard.qml; it keeps
# wl-paste --watch tied to its caller (see below) so a restarted shell does not leave watchers behind.
dir="${1:?usage: clipboard-watch.sh <dir>}"

if [ "${2:-}" != "--entry" ]; then
    umask 077
    mkdir -p -m 700 "$dir" || exit 1
    command -v wl-paste >/dev/null || exit 127

    # One watcher per directory. A reload takes over from the old one, a watcher whose shell is gone is
    # replaced, and while another live shell holds it this one exits 75 (Clipboard.qml tries again later).
    # Strays that an older version left (it exec'd wl-paste, which outlives its parent until the next copy)
    # are killed, unless a Quickshell still owns them.
    pidfile="$dir/watch.pid"
    status=75
    cleanup() {
        # The jobs, not $child: a signal can land after the fork and before $child is set.
        kill $(jobs -p) 2>/dev/null
        [ "$(cut -d" " -f1 "$pidfile" 2>/dev/null)" = "$$" ] && rm -f "$pidfile"
        exit "$status"
    }
    # The parent's pid lands in $ppid; empty when the process is gone. No process is forked for it.
    ppid_of() {
        ppid=
        while read -r key value; do
            if [ "$key" = "PPid:" ]; then
                ppid=$value
                break
            fi
        done 2>/dev/null <"/proc/$1/status"
    }
    trap cleanup TERM INT HUP

    exec 9>"$dir/watch.lock"
    # The lock is held from here until the new wl-paste is forked (it does not inherit it), so two shells
    # starting at once cannot both miss each other.
    flock 9
    old= oldparent=
    { read -r old oldparent <"$pidfile"; } 2>/dev/null
    if [ -n "$old" ] && { tr '\0' ' ' <"/proc/$old/cmdline"; } 2>/dev/null | grep -q 'clipboard-watch\.sh'; then
        if [ "$oldparent" != "$PPID" ]; then
            ppid_of "$old"
            [ "$ppid" = "$oldparent" ] && exit 75
        fi
        kill "$old" 2>/dev/null
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$old" 2>/dev/null || break
            sleep 0.2
        done
        kill -0 "$old" 2>/dev/null && kill -9 "$old" 2>/dev/null
    fi
    echo "$$ $PPID" >"$pidfile"
    pattern="$(printf '%s' "$dir" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
    for stray in $(pgrep -f -- "wl-paste --watch .*clipboard-watch\.sh $pattern --entry\$"); do
        ppid_of "$stray"
        case "$(ps -o comm= -p "${ppid:-0}" 2>/dev/null)" in
            quickshell | qs) ;;
            *) kill "$stray" 2>/dev/null ;;
        esac
    done

    parent=$PPID
    wl-paste --watch "$0" "$dir" --entry 9>&- &
    child=$!
    exec 9>&-
    # Followed by the shell: wl-paste does not notice that its output is gone until the next copy.
    while kill -0 "$child" 2>/dev/null && ppid_of $$ && [ "$ppid" = "$parent" ]; do
        sleep 1 &
        wait $!
    done
    # Out of the loop: the shell is gone (status 0), or wl-paste exited or was killed by a newer watcher.
    status=0
    if ! kill -0 "$child" 2>/dev/null; then
        wait "$child"
        status=$?
        [ "$(cut -d" " -f1 "$pidfile" 2>/dev/null)" = "$$" ] || status=75
    fi
    cleanup
fi

# Called by wl-paste for each change of the clipboard; its stdout is the watcher's. A source that never
# answers must not leave this (and its wl-paste) hanging, hence the timeouts. They wrap the reader too: a
# source can hand wl-paste's output to a process of its own (wl-copy forks one), which keeps the pipe open
# after wl-paste has exited, and head would wait for it. A copy that the timeout cut off is dropped.
types="$(timeout 5 wl-paste --list-types 2>/dev/null)" || exit 0
printf '%s\n' "$types" | grep -qi 'passwordManagerHint' && exit 0

if printf '%s\n' "$types" | grep -qx 'image/png' && ! printf '%s\n' "$types" | grep -q '^text/plain'; then
    tmp="$(mktemp "$dir/.new.XXXXXX")" || exit 0
    if timeout 5 sh -c 'wl-paste --type image/png | head -c 20000000' >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        name="$(sha1sum "$tmp" | cut -d' ' -f1)"
        mv -f "$tmp" "$dir/$name.png"
        printf 'i %s\n' "$dir/$name.png"
    else
        rm -f "$tmp"
    fi
elif printf '%s\n' "$types" | grep -qiE '^(text/|string$|utf8_string$)'; then
    text="$(timeout 5 sh -c 'wl-paste --no-newline --type text | head -c 100000 | base64 -w0' 2>/dev/null)" && [ -n "$text" ] && printf 't %s\n' "$text"
fi
exit 0
