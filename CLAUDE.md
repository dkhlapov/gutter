# Gutter

Quickshell (QML) shell for Hyprland. README.md has the feature tour and settings; this file is what you
can't read off the code.

## Check your work
- `scripts/check.sh` runs everything (tests, smoke, pills, sides, mapped, lint). Run it before a commit.
- `scripts/test.sh`: Qt Quick Test (`tests/tst_*.qml`), Python unittest (`tests/test_*.py`), fit and centring checks.
- `scripts/lint.sh` fails only on warnings missing from `scripts/lint-baseline.txt`; `--update` rewrites the baseline.
  A section folder needs every `.qml` listed in its hand-written `qmldir`.
- UI changes: look at the result. `scripts/shot.sh <section> [out.png]` screenshots a section; `GUTTER_GALLERY=1 qs -p .`
  shows every component.

## The live shell is the user's desktop
- It runs from this checkout (`~/.config/quickshell/gutter` → here) and Quickshell **hot-reloads on file changes**.
  Merging into main here restarts it on new code before any migration script has run. For a release that
  changes live state: `qs -c gutter kill`, merge, then run the migration script (it restarts Gutter itself).
  (A user-level hook blocks `git merge`/`git pull` here while the shell is running.)
- `scripts/smoke.sh` stops a running Gutter for a few seconds and restarts it. It runs with `GUTTER_SMOKE=1` so
  theme switching never touches the real state files. Dev instances from a worktree: `qs -p <worktree> -d`;
  restore live files afterwards.
- Never mutation-test or run scripts that call real `pkill`/`killall`/`qs … kill` against the live system: a
  subagent once killed the user's bar that way. Mutate with `echo` stand-ins or a shimmed PATH. After any run
  that touches process-control scripts: `pgrep -af '^qs -c gutter'`, and `qs -c gutter -n -d` if it is gone.
- `qs -c gutter kill` then `qs -c gutter -n -d` after editing QML that hot reload doesn't pick up; `qs log -c gutter`
  shows errors.

## Conventions
- `theme/` is the only reader of `palette.json`.
- Releases are tags. Patch fixes go out as patch versions on top of the latest tag. The user merges PRs.
