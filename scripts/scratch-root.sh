# Sourced by scripts/scrollbar.sh and scripts/components.sh, the checks that run tests/<name>/shell.qml from a scratch
# config root. scratch_root <repo dir> <name> sets $root (a temporary folder, removed on exit), $log (inside it) and
# $errors (the pattern for QML errors in the log), links the repo's folders and its real services into the root,
# copies the test's shell.qml there and makes a private home, bin and run folder. scratch_run <seconds> starts
# Quickshell on "$root" offscreen, logging to $log, with nothing of the caller's environment: a private HOME and XDG
# folders (so Theme and Settings never read or create the account's own palette, theme state or config), a PATH of
# bash and mkdir only, and a bus address pointing at a socket nobody listens on. Returns Quickshell's exit status.
scratch_root() {
    local repo="$1" name="$2" d f
    root="$(mktemp -d)"
    log="$root/log"
    errors='ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign'
    qs_bin="$(command -v qs)"
    trap 'rm -rf "$root"' EXIT

    for d in bar components dev ipc launcher lib pill scripts settings theme wallpaper; do
        ln -s "$repo/$d" "$root/$d"
    done
    mkdir "$root/services" "$root/home" "$root/bin"
    mkdir -m 700 "$root/run"
    for f in "$repo"/services/*; do
        ln -s "$f" "$root/services/"
    done
    cp "$repo/tests/$name/shell.qml" "$root/shell.qml"
    # The only tools on the PATH: bash and mkdir (the settings make their folder).
    ln -s "$(command -v bash)" "$root/bin/bash"
    ln -s "$(command -v mkdir)" "$root/bin/mkdir"
}

scratch_run() {
    timeout "$1" env -i PATH="$root/bin" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$root/run/bus" HOME="$root/home" XDG_CONFIG_HOME="$root/home/.config" \
        XDG_STATE_HOME="$root/home/.local/state" XDG_DATA_HOME="$root/home/.local/share" \
        XDG_CACHE_HOME="$root/home/.cache" XDG_RUNTIME_DIR="$root/run" \
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic \
        "$qs_bin" -p "$root" >"$log" 2>&1
}
