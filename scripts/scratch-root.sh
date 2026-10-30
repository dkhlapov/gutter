# Sourced by scripts/scrollbar.sh and scripts/components.sh, the checks that run tests/<name>/shell.qml from a scratch
# config root. scratch_root <repo dir> <name> sets $root (a temporary folder, removed on exit), $log (inside it) and
# $errors (the pattern for QML errors in the log), links the repo's folders and its real services into the root and
# copies the test's shell.qml there. The caller adds whatever else the check needs and starts Quickshell on "$root".
scratch_root() {
    local repo="$1" name="$2" d f
    root="$(mktemp -d)"
    log="$root/log"
    errors='ERROR|TypeError|ReferenceError|is not a type|is not installed|Cannot assign|Unable to assign'
    trap 'rm -rf "$root"' EXIT

    for d in bar components dev ipc launcher lib pill scripts settings theme wallpaper; do
        ln -s "$repo/$d" "$root/$d"
    done
    mkdir "$root/services"
    for f in "$repo"/services/*; do
        ln -s "$f" "$root/services/"
    done
    cp "$repo/tests/$name/shell.qml" "$root/shell.qml"
}
