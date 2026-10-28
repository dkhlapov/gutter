# Gutter

A Quickshell shell for Hyprland, drawn like a comic page: heavy ink outlines, flat accent colours, square corners and
hard offset shadows (teal by default, so they still read over a dark wallpaper).

A pill (the island) floats at the top centre of every monitor and unfolds into a panel with up to eleven sections:
overview, music, calendar, system, weather, tools, agents, shelf, clipboard, mixer and notifications. A bar at the top
right holds the tray, the status cells and a power menu; a workspace bar sits at the top left. Gutter also draws the
wallpaper, owns the notifications, and provides the launcher, the session screen and the lock screen. It owns the
Hyprland config too (borders, shadows, binds and the rest; see Hyprland).

The palette comes from the wallpaper (`tools/palette.py`) and reloads live. Gutter needs no other shell.

## Start

```sh
qs -c gutter -n -d      # start in the background (the config is ~/.config/quickshell/gutter -> this repo)
qs -c gutter kill       # stop
qs log -c gutter        # the log (QML errors start with "ERROR", Gutter's own lines with "gutter:")
```

Gutter's Hyprland config starts it itself. After editing QML, restart it with `kill` then `-n -d`.
`SUPER + I` toggles the panel on the focused monitor, a tap of `SUPER` opens the launcher and `CTRL + ALT + Delete` the
session screen.

| What | Where |
|---|---|
| Settings | `~/.config/gutter/config.json` (live reload; written with the defaults on first run) |
| State | `${XDG_STATE_HOME:-~/.local/state}/gutter/` (palette, wallpaper, clipboard, notification and launcher history, ...) |
| Generated Hyprland look | `…/gutter/hypr-gutter.lua` (by `gutter hypr`; do not edit) |
| Your Hyprland config | `~/.config/gutter/hypr-user.lua` (loaded last) and `~/.config/gutter/hypr-vars.lua` (overrides of `hypr/gutter/vars.lua`, loaded first) |
| App themes | foot, fuzzel, GTK 3/4 (and Thunar), Qt (qtengine), btop and Deezer files named `gutter.*` (by `gutter theme apply`) |

Settings keys: `openOnHover`, `hoverDelay`, `hideInFullscreen`, `idleContent` (`none`, `music`, `clock`),
`opensActivity`, `gestures`, `notifications`, `sections` (which sections show, in what order), `weather.location`,
`weather.units`, `worldClocks`, `theme.mode`, `theme.schedule.light`, `theme.schedule.dark`, `shadow.color`,
`shadow.keyline`, `shadow.offset`, `launcher.terminal`, `launcher.maxRows`, and the `lockscreen.*` keys (see Lock
screen).

### Shadows

Every box's hard shadow comes from three settings, applied as soon as `config.json` is saved, in both modes. An invalid
value is logged and its default used.

- `shadow.color`: `"ink"`, an accent (`navy`, `teal`, `magenta`, `coral`, `sun`, `lime`, `pink`) or a role (`active`,
  `urgent`, `focusBorder`, `ok`, `special`, `muted`). Default `"teal"`. Hyprland's window shadows take the same colour.
- `shadow.keyline`: a paper line, 0 to 2 px, round the shadows of surfaces that sit over the wallpaper or a window.
  Default `0`.
- `shadow.offset`: how far the shadow drops, 0 to 8 px (0 is no shadow). Default `3`.

```json
"shadow": { "color": "teal", "keyline": 0, "offset": 3 }
```

## Notifications

Gutter owns `org.freedesktop.Notifications` (the `notifications` setting, on by default): `notify-send`, browsers and
chat apps get a bubble at the pill with the sender's action buttons and an inline reply, and the `notifications`
section lists the history (the last 100, kept across restarts). Do-not-disturb holds back every bubble except critical
ones; they still reach the history.

If another daemon (dunst, mako) already holds the name, the section's header says so and Gutter takes over by itself
once that daemon exits. Sounds and per-app rules are not there yet.

## The island

The island rests at one size and shows the date and time; hovering it grows it a little (and opens the panel when
`openOnHover` is on). Short activities take over its body for a few seconds: volume, brightness, a keyboard-layout
switch or Caps/Num Lock (`KBD`, `CAPS`, `NUM`), timer and stopwatch, a track change, notifications.

Two pills sit beside it: a **music pill** on the left while a track plays (visualiser, title, artist), and an **agent
pill** on the right while a coding agent works or waits for you. A click opens the matching section. They fold away
over a fullscreen window and while the panel is open.

## Bars

- **Workspace bar** (top left): five of the monitor's ten workspaces (the half the active one is in), then each open
  special workspace. Each workspace is an ink box with its number and the icons of the apps on it. A click shows the
  workspace on that monitor; the wheel steps through them.
- **Top-right bar**: the **tray** (left click opens an item's menu, right click shows the app, middle click is the
  secondary action), the **status cells** (volume, microphone, keyboard layout, network, Bluetooth), a **sun/moon**
  cell that flips light and dark, and the **power menu** (Lock, Log out, Suspend, Hibernate, Restart, Power off; the
  last three that end the session ask again).

## Launcher

A tap of `SUPER` (or `qs -c gutter ipc call gutter launcher ""`) opens a search box on the focused monitor. Type to find
an installed app and press Enter. Apps are ranked by how well the name, keywords and comment match, plus how often and
recently you started them (history in `launcher.json` in the state folder). An app that runs in a terminal starts in
`launcher.terminal` (default `foot`; a bare command that takes `-e`). `launcher.maxRows` (4 to 12, default 8) is how many
rows show at once.

A query that starts with `/` lists Gutter's own commands:

| Command | Does |
|---|---|
| `/lock`, `/logout`, `/suspend`, `/hibernate`, `/reboot`, `/poweroff` | the power menu's actions (the last three that end the session ask again) |
| `/session` | open the session screen |
| `/dark`, `/light`, `/theme` | switch the page, or flip it |
| `/dnd` | toggle do-not-disturb |
| `/clear` | empty the notification history |
| `/mute` | toggle mute |
| `/timer <minutes>` | start a countdown (1 to 1440) |
| `/stopwatch` | start or stop the stopwatch |
| `/open <section>` | open that section of the panel |

Up and Down (or `Ctrl + K`/`Ctrl + P` and `Ctrl + J`/`Ctrl + N`) move, Enter runs, Tab fills in, `Ctrl + U` clears,
Escape closes. There is no emoji picker and no window switcher yet.

**Session screen.** `CTRL + ALT + Delete` (or `/session`) shows the session actions as tiles; arrows and Enter, or the
tile's letter: `L` lock, `O` log out, `S` suspend, `H` hibernate, `R` restart, `P` power off. The three that end the
session ask for a second Enter first.

`GUTTER_LAUNCHER_DRY_RUN=1` at start (or `launcherDryRun true` over IPC) only logs apps and commands.

## Lock screen

Gutter locks the session itself (Quickshell's `WlSessionLock`, the `ext-session-lock-v1` protocol) and runs the idle
timers and the lock before sleep. Everything that locks goes through one path, on every monitor, with one shared
password buffer: `/lock`, the session screen's `L`, the power menu, `SUPER + L`, `loginctl lock-session`, the `lock`
IPC target (`qs -c gutter ipc call lock lock`) and the idle timeout. Only a password (PAM) or a fingerprint unlocks.

- **Screen.** A big clock over the wallpaper, a password field (a wrong password shakes it and shows the tries left), a
  fingerprint glyph when `fprintd` has a print, the now-playing card, a count of waiting notifications per app (no
  text) and a strip with the keyboard layout and battery.
- **PAM.** The stacks are Gutter's own (`lockscreen/pam.d/passwd` with faillock and `pam_unix`, and `fprint`), so the
  system's `faillock.conf` applies. A check that has not ended after 30 s is aborted.
- **Idle and sleep.** Idle locks after `lockscreen.idle.lock` seconds and turns the screens off after
  `lockscreen.idle.screenOff`; playing audio, "Keep awake" and applications' inhibitors hold idle off. Suspend and
  hibernate wait (a `systemd-inhibit` delay lock) for the lock, for at most about 2 s, and the screen is locked on resume.
- **Survives a crash.** If the lock client dies or is reloaded, the compositor keeps the session locked. Gutter sets
  logind's `LockedHint` while locked and locks again at its next start if the hint is still set (this needs
  `misc:allow_session_lock_restore`, on in the usual Hyprland config).

Settings (live, `lockscreen` in `config.json`):

| Key | Default | Does |
|---|---|---|
| `lockscreen.enabled` | `true` | Gutter's lock and idle control; off makes every lock trigger do nothing and stops all of Gutter's idle handling |
| `lockscreen.idle.lock` | `180` | seconds idle until the lock; `0` is never |
| `lockscreen.idle.screenOff` | `300` | seconds idle until the screens turn off; `0` is never |
| `lockscreen.idle.inhibitWhenAudio` | `true` | no idling while audio plays |
| `lockscreen.idle.lockBeforeSleep` | `true` | lock before suspend and hibernate |
| `lockscreen.fingerprint` | `true` | use the fingerprint when `fprintd` has a print |

**Dry runs and test hooks.** `GUTTER_LOCK_DRY_RUN=1` at start, or `qs -c gutter ipc call lock dryRun true`, makes a lock
request show a preview window per monitor instead of taking the session lock (Escape closes it). `GUTTER_IDLE_DRY_RUN=1`
makes turning the screens off or on only log. `GUTTER_IDLE_MONITOR_CMD` (read only in that dry run) replaces the logind
monitor command with a JSON array of strings, so a test can feed signals as text. `GUTTER_LOCK_PAM_DIR` points the
password check at another PAM folder; `scripts/lock-test-pam.sh <parent-dir>` writes one that accepts only the dummy
password `guttertest` and never touches your account. `GUTTER_LOCK_HINT_FILE` names a file to hold the LockedHint
instead of logind's.

**Other lock handlers.** Gutter handles logind's `Lock` signal and the idle timers itself. If you also run hypridle or
swayidle, turn one of the two off, or both will try to lock. The `SUPER + L` bind is `bind_lock` in
`hypr/gutter/vars.lua`.

### The way out

If the lock screen hangs, dies or will not take the password, the session stays locked on purpose. From a TTY:

1. Press `Ctrl + Alt + F3` and log in as yourself (SSH from another machine works too).
2. Run `scripts/rescue-unlock.sh` from the checkout. It finds the newest live Hyprland instance and prints it.
3. Type `unlock` at the prompt. Anything else stops it; if the instance is the wrong one, run it again with
   `--instance SIGNATURE`.

It then turns on `misc:allow_session_lock_restore`, ends the Gutter lock client in that instance, runs a tiny `qs` shell
(`lockscreen/rescue`) that takes and releases the lock, and clears the LockedHint. Start Gutter again with the line the
script prints, or log out and in, then return to the graphical session (`Ctrl + Alt + F1` or `F2`).

The script refuses to run inside a Wayland session unless `--force` is given with `--instance` naming a nested
compositor, never the session it runs in. `GUTTER_RESCUE_DRY=1` prints each step instead of running it; the script's
header lists the other knobs.

### Trying it without locking the desktop

`scripts/lock-nested.sh start` runs a nested Hyprland in a window with Gutter inside it, with its own runtime dir,
D-Bus, home and a dummy password, so the real session lock, a crash, a reload and the rescue script can be tried
without touching the live desktop. `lock-nested.sh ipc`, `shell`, `ctl` and `env` talk to it, and `logind sleep|resume`
feeds it a fake sleep signal. `scripts/lock-nested-check.sh` runs the lock, outputs, kill, hang, reload and rescue
scenarios in such a session; it needs a running Wayland session and is not part of `scripts/test.sh`.

## Hyprland

Gutter owns the Hyprland config (Hyprland 0.56, Lua). The repo holds it in `hypr/`: the entry `hypr/gutter.lua` and its
modules in `hypr/gutter/` (`vars`, `env`, `general`, `input`, `misc`, `animations`, `decoration`, `group`, `execs`,
`rules`, `gestures`, `keybinds`, `utils/`). `~/.config/hypr/hyprland.lua` is only a loader (`hypr/loader.lua.in`, written
by `scripts/install-hyprland.sh`). It loads, in order, `~/.config/gutter/hypr-vars.lua` (overrides of `vars`), the
modules, the generated look (`hypr-gutter.lua`: borders, shadows, blur, rounding, group colours) and last
`~/.config/gutter/hypr-user.lua`, your own file for monitors, workspace pinning, screenshot binds and so on.

- **Binds.** Window, workspace, workspace-group, special-workspace (`SUPER + S`, and `SUPER + G` for games), app, media
  and sleep binds, each a `bind_*` setting in `hypr/gutter/vars.lua` (a chord, a list of chords, or `""` to turn one
  off). Gutter's own go through global shortcuts: `SUPER + I` (`toggle`), a tap of `SUPER` or `SUPER + Space`
  (`launcher`), `CTRL + ALT + Delete` (`session`), `SUPER + L` (`lock`), the volume and brightness keys and the media
  keys, which act on the player the pill shows, else on any playing MPRIS player. Screenshots and screen recording are
  not Gutter's: bind your own in `hypr-user.lua`.
- **Settings.** `vars.lua` lists every setting with its default; `hypr-vars.lua` returns a partial table over it (keys
  are replaced whole, so give a list bind as a full list). Programs (`terminal`, `browser`, `editor`, `file_manager`,
  `audio_mixer`), the cursor (`cursor_theme`, `cursor_size`; an empty theme leaves the cursor alone), touchpad
  (`touchpad_disable_while_typing`, `touchpad_scroll_factor`), gestures (`gesture_workspace_fingers`,
  `gesture_scratch_fingers`, `gesture_sleep_fingers`, `sleep_command`; 0 fingers turns one off), `shadow_render_power`,
  gaps (`gaps_workspaces`, `gaps_inner`, `gaps_outer`, `gaps_outer_alone`), the workspace-number modifiers
  (`mod_workspace_*`) and one `bind_*` per bind.
- **Workspace groups.** `SUPER + 1..0` targets workspace N of the current group of ten. The workspace bar shows the group
  of the monitor's active workspace, so it follows whatever pinning of workspaces to monitors you set in
  `hypr-user.lua` (for example a `workspace_rule` per monitor, ids 1-10 on the first and 11-20 on the second).
- **If the config fails.** The loader binds `SUPER + Return` to `foot`, starts the shell and sends a critical
  notification with the error. A `keybinds.lua` that errors gets the same terminal bind. A reload does not start the
  shell a second time.
- **The config follows the checkout.** Hyprland reads whatever the repo's working tree holds at each reload, so an old
  branch or a half-edited `hypr/` file can trigger the failsafe. `scripts/install-hyprland.sh` verifies `hypr/gutter.lua`
  with `Hyprland --verify-config` before it writes anything; that does not cover `keybinds.lua`.

## Light and dark

Gutter has a light page (paper and ink) and a dark night page (dark paper, cream lines), and themes Hyprland's borders,
foot, fuzzel, GTK (and Thunar), Qt, btop and Deezer to match.

```json
"theme": { "mode": "sun", "schedule": { "light": "07:00", "dark": "20:00" } }
```

- `theme.mode`: `"sun"` (the default) is light from sunrise to sunset where you are, `"schedule"` is light from
  `schedule.light` to `schedule.dark` (24-hour local times), and `"light"` or `"dark"` fix the mode.
- Sun times are worked out locally from `weather.location`, else an IP lookup, and cached in `theme-auto.json` so sun
  mode works offline.
- The shell checks every minute and runs `gutter theme apply <mode>` when the wanted mode is not the one on screen. A
  failed apply is retried each minute and notified.
- A flip by hand (the sun/moon cell, `themeToggle` over IPC, `gutter theme toggle`) shows the other mode until the next
  automatic switch; the cell's tooltip names the next change.

foot, btop and Deezer switch at once, libadwaita apps follow at once, some GTK 3 and Qt apps need a restart, and fuzzel
uses the new colours the next time it opens.

[deezer-linux](https://github.com/aunetx/deezer-linux) (8.0 or later) re-reads one custom CSS file when it changes.
`gutter theme apply` writes `gutter.css` into the Flatpak's config folder (`~/.var/app/dev.aunetx.deezer/config/`) or
`~/.config/deezer/`, and skips Deezer when neither exists. Point Deezer at it once:

```sh
flatpak override --user --env=DZ_CUSTOM_THEME=$HOME/.var/app/dev.aunetx.deezer/config/gutter.css dev.aunetx.deezer
```

Outside Flatpak, start it with `deezer-desktop --custom-theme=$HOME/.config/deezer/gutter.css`.

## IPC

```sh
qs -c gutter ipc show                       # list everything
qs -c gutter ipc call gutter <function> [args]
```

The functions include `toggle`, `open <section>`, `close`, `volumeUp`/`volumeDown`/`volumeMute`,
`brightnessUp`/`brightnessDown`, `timer <minutes>`, `timerToggle`, `stopwatchToggle`, `notificationsDnd`,
`notificationsClear`, `shelfAdd <path>`, `shelfClear`, `launcher <screen>`, `session <screen>`, `launcherQuery <text>`,
`themeToggle` and `themeSet <light|dark>`; `ipc show` has the full list.

The Hyprland binds use global shortcuts (appid `gutter`): `toggle`, `brightnessUp`, `brightnessDown`, `volumeUp`,
`volumeDown`, `volumeMute`, `capsLock`, `numLock`, `launcher`, `session`, `lock`, `mediaToggle`, `mediaNext`,
`mediaPrev` and `mediaStop`. The shell also registers `themeToggle`, which no bind in the repo uses: bind
`hl.dsp.global("gutter:themeToggle")` in `hypr-user.lua` if you want a key for it.

## CLI

`gutter` (linked to `~/.local/bin/gutter` by `scripts/install.sh`, or run `tools/gutter`) sets the wallpaper, rebuilds the
palette and switches light and dark. The pill, the Hyprland borders and the apps recolour without a restart.

```sh
gutter wall set <image>      # remember the image as the wallpaper, then regenerate the palette from it
gutter palette regen         # regenerate the palette from the current wallpaper
gutter palette default       # use the hand-tuned default palette (theme/default-palette.json)
gutter theme toggle          # flip the running shell between light and dark
gutter theme light|dark      # flip it to that mode
gutter theme apply <mode>    # switch everything now: palette, Hyprland, theme.json, then the apps
gutter hypr                  # rewrite Hyprland's generated look; reload only if it differs from the loaded one
```

`toggle`, `light` and `dark` go through the running shell. `apply` works without it, but a running shell puts back the
mode it wants within a minute. Python's `tools/` has no Quickshell dependency: `tools/palette.py <image> --out <file>`
and `tools/hypr.py --palette <file> --out <file> [--config <config.json>]` run on their own.

## Install

On a Hyprland session with Lua config (Arch; Quickshell 0.3.2 or `quickshell-git`, python3):

```sh
git clone https://github.com/dkhlapov/gutter && cd gutter
scripts/install.sh
scripts/install-hyprland.sh            # a dry run: prints every step as "would: ..."
scripts/install-hyprland.sh --apply
sudo pacman -S cava
```

Both scripts are idempotent. The checkout can live anywhere; run `install-hyprland.sh` from the one that
`~/.config/quickshell/gutter` links to.

`scripts/install.sh` links `~/.local/bin/gutter` to `tools/gutter`, links `~/.config/quickshell/gutter` to the checkout,
makes foot and fuzzel include Gutter's colour files (their configs are backed up once as `*.pre-gutter`), installs
Gutter's Claude Code hooks for the agent pill (`scripts/install-agent-hooks.sh`; `GUTTER_DRY=1` skips this step) and
creates the state folder.

`scripts/install-hyprland.sh` is what makes Hyprland load Gutter's config. It refuses, writing nothing, when
`Hyprland --verify-config` rejects the new config. Then it backs `~/.config/hypr` up once to `~/.config/hypr.pre-gutter`,
generates the Hyprland look, writes the loader to `~/.config/hypr/hyprland.lua` and runs `hyprctl reload`. It does not
restart Gutter: start it with `qs -c gutter -n -d`, or log in again. Neither `hypr-user.lua` nor `hypr-vars.lua` is
created for you. If a tool such as HyprMod writes its own Lua file, load it from `hypr-user.lua`.

**Rolling back.** Stop Gutter (`qs -c gutter kill`), copy back the one file the loader replaced
(`cp ~/.config/hypr.pre-gutter/hyprland.lua ~/.config/hypr/hyprland.lua`) and run `hyprctl reload`. Restore app configs
from their `*.pre-gutter` backups with `mv`; where the backup is an empty `*.pre-gutter-absent` marker, delete the file
Gutter created. Gutter's state and `~/.config/gutter` stay; delete them for a clean start.

**Dependencies.** `cava` drives the music visualiser (the bars stay flat without it). System stats come from `/proc`,
`/sys` and `df`; GPU stats are AMD only. Lyrics come from lrclib.net and are cached in the state folder.

## Development

```sh
scripts/check.sh               # everything: tests, smoke, mapped, lint (run before a commit)
scripts/test.sh                # Qt Quick Test (tests/tst_*.qml), Python unittest (tests/test_*.py) and the other checks
scripts/shot.sh <section> [out.png]   # screenshot a section on the focused monitor (SHOT_SCREEN=DP-2 for another)
GUTTER_GALLERY=1 qs -p .       # every ink component in one window
```

`scripts/smoke.sh` stops a running Gutter for a few seconds and starts it again afterwards.

Layout: `theme/` (the only reader of `palette.json`), `components/` (ink widgets), `services/` (data), `lib/` (pure JS),
`pill/` (the pill and its sections), `launcher/` (the launcher and session screen), `lockscreen/`, `wallpaper/`,
`settings/`, `ipc/`, `tools/` (palette and Hyprland generators, CLI), `hypr/` (the Hyprland config), `scripts/`,
`tests/`.

## License

MIT, see `LICENSE`. Reuse is welcome with the copyright notice kept. `hypr/gutter/utils/json.lua` is rxi's `json.lua` and
keeps its own MIT notice.
