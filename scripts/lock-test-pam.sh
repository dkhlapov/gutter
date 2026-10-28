#!/usr/bin/env bash
# Writes a test PAM folder for the lock screen (GUTTER_LOCK_PAM_DIR) and prints its path. Its `passwd` stack
# accepts one fixed dummy password, "guttertest", and nothing else; it never touches the account's own PAM
# stack. `fprint` always fails.
#
# Usage: lock-test-pam.sh <parent-dir>
# <parent-dir> must exist (a scratchpad or temp folder). The folder is always a fresh one made inside it, never the
# parent itself, so an existing PAM folder is never overwritten. A parent that is, or sits in, a `lockscreen` or
# `pam.d` folder, /etc, the repo, the main checkout the repo is a git worktree of, or the shell's own config folder
# (~/.config/quickshell and $XDG_CONFIG_HOME/quickshell, and where the `gutter` install link in them points) is
# refused. The repo, main checkout and config folders are compared by their real paths, so a symlinked config folder
# or install link is no way in.
# The folder's own path may only use letters, digits and `. _ / + - : @ = ,`: it goes unquoted into a PAM line.
set -euo pipefail
# An exported CDPATH would make `cd` print the path it went to, which `$(cd ... && pwd -P)` would then get twice.
unset CDPATH
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    echo "usage: lock-test-pam.sh <existing parent dir>" >&2
    exit 2
fi
if [ ! -d "$1" ]; then
    echo "lock-test-pam: $1 is not an existing directory" >&2
    exit 2
fi
parent="$(cd "$1" && pwd -P)"

refuse() {
    echo "lock-test-pam: refusing $parent ($1)" >&2
    exit 1
}
inside() { [ "$parent" = "$1" ] || [[ "$parent" == "$1"/* ]]; }
# The real path of a folder, or nothing when it does not exist (so a missing config folder refuses nothing).
resolved() { (cd "$1" 2>/dev/null && pwd -P) || true; }

case "/$parent/" in
    */lockscreen/* | */pam.d/*) refuse "a lockscreen or pam.d folder" ;;
esac
inside /etc && refuse "under /etc"
inside "$here" && refuse "inside the repo"
# The repo may be a worktree of a main checkout (the live shell hot-reloads from it): its git common dir is that
# checkout's .git. Without git, or outside a repo, there is nothing to derive and this quietly checks nothing.
common="$(env -u GIT_DIR -u GIT_COMMON_DIR -u GIT_WORK_TREE git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || common=""
if [[ "$common" == */.git ]]; then
    main="$(resolved "${common%/.git}")"
    [ -n "$main" ] && inside "$main" && refuse "inside the main checkout"
fi
# Both the folder and the `gutter` link in it (the install link into the repo) are compared as real paths: the
# parent was made physical above, so an unresolved path here would let a symlinked config folder through.
for cfg in "${HOME:-/nonexistent}/.config/quickshell" "${XDG_CONFIG_HOME:-${HOME:-/nonexistent}/.config}/quickshell"; do
    for guarded in "$cfg" "$(resolved "$cfg")" "$(resolved "$cfg/gutter")"; do
        [ -n "$guarded" ] && inside "$guarded" && refuse "the shell's config folder"
    done
done

dir="$(mktemp -d "$parent/gutter-lock-pam.XXXXXX")"
dir="$(cd "$dir" && pwd -P)"
# The path goes unquoted into the pam_exec line. Linux-PAM's only quoting is a `[...]` argument (which then needs its
# `]` escaped, and other PAM implementations lack it), while `#` starts a comment anywhere on the line and
# whitespace splits arguments. So rather than quote, anything outside a short safe set is refused. (The locale is
# pinned so the ranges mean ASCII letters.)
if ! (LC_ALL=C; [[ "$dir" =~ ^[A-Za-z0-9._/+:@=,-]+$ ]]); then
    rmdir "$dir"
    echo "lock-test-pam: refusing the path $dir (only letters, digits and . _ / + - : @ = , are allowed in it)" >&2
    exit 1
fi

cat >"$dir/check.sh" <<'CHECK'
#!/usr/bin/env bash
IFS= read -r given
[ "$given" = "guttertest" ]
CHECK
chmod +x "$dir/check.sh"
# pam_exec turns a failing script into a system error, which the lock would show as an error rather than a wrong
# password: so a pass skips the deny that follows (and reaches the permit, which only this throwaway stack has),
# anything else lands on the deny (PAM_AUTH_ERR).
printf '#%%PAM-1.0\nauth [success=1 default=ignore] pam_exec.so quiet expose_authtok %s/check.sh\nauth requisite pam_deny.so\nauth required pam_permit.so\n' "$dir" >"$dir/passwd"
printf '#%%PAM-1.0\nauth required pam_deny.so\n' >"$dir/fprint"
echo "$dir"
