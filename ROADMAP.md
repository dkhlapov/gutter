# Roadmap

Consolidates the 29 open issues ([dkhlapov/gutter](https://github.com/dkhlapov/gutter/issues)) into target release tags.
The latest tag is `v0.1.0`. Patch tags carry fixes only; each minor tag carries one theme. Tags after `v0.2.0` are
tentative and get re-cut as work lands. Every open issue appears exactly once.

| Tag | Theme | Issues |
|---|---|---|
| v0.1.1 | Runtime polish | #1 #2 #3 #4 |
| v0.1.2 | Lock hardening and test gaps | #6 #7 #5 #8 |
| v0.2.0 | Portable and installable | #17 #9 #18 #16 |
| v0.3.0 | Launcher breadth | #15 #26 #27 #28 #29 |
| v0.4.0 | Everyday controls | #12 #13 #22 |
| v0.5.0 | Lock screen and notifications | #10 #20 |
| v0.6.0 | Settings app | #11 #19 |
| v0.7.0 | Capture and calendar | #14 #23 |
| v0.8.0 | Window overview | #21 |
| v0.9.0 | Dock, widgets, greeter | #25 |
| v1.0.0 | Plugin API (stable extension surface) | #24 |

## v0.1.1: runtime polish (patch)
Small, independent fixes in code that already ships. No new features, no live-state migration.
- #1 Notification service edge cases
- #2 Shared component polish
- #3 Bars and tray polish
- #4 Launcher and session screen polish (its "no window switcher" line moves to #27)

## v0.1.2: lock hardening and test gaps (patch)
Touches the lock lifecycle, so verify with `scripts/lock-nested.sh` before a real lock/unlock on the live desktop.
- #6 Lock screen auth and lifecycle rough edges
- #7 Rescue script and nested harness edge cases
- #5 Launcher test and fit-check gaps
- #8 Lock screen test gaps (the real suspend/resume and TTY rescue checks are manual)

Ordered before v0.2.0 so #9 reworks the lock state with the hardening and its tests already in place.

## v0.2.0: portable and installable
Makes Gutter usable on a machine that is not this one. Everything later benefits from CI, so it goes first.
- #17 Portability: monitor-agnostic workspace groups, NVIDIA/Intel GPU stats, personal defaults, the unused `width` key
- #9 Lock screen on stable Quickshell. Unblocks CI without a quickshell-git build.
- #18 Packaging and CI. Depends on #9 (CI) and on #17's removal of checkout-path assumptions.
- #16 Laptop support: battery widget and sysfs/brightnessctl backlight

## v0.3.0: launcher breadth
Closes the tracking issue #15; update the launcher spec and the README out-of-scope list in the same release.
Order inside the release, each mode independent:
1. #26 Clipboard history mode (reuses `services/Clipboard.qml`)
2. #27 Window switcher (reuses `services/Hypr.qml`; respects per-monitor workspace groups)
3. #28 Calculator. Arithmetic and units first, currency last. Currency needs a decision on the network call and the
   README's outbound-host list.
4. #29 Emoji picker (dataset licence check, colour-font detection)

Write the modes from documented behaviour, not Vicinae's GPL source (see #15).

## v0.4.0: everyday controls
Things most shells ship that Gutter makes you do elsewhere.
- #12 Quick settings: Wi-Fi/Bluetooth lists, audio device choice, power profiles. Decide panel section vs popout first.
- #13 Wallpaper picker, per-monitor wallpaper, transitions. Build it as a panel section so the README's launcher
  exclusion is not touched.
- #22 Night light, VPN and updates indicators

## v0.5.0: lock screen and notifications
Visual and behavioural work on two surfaces. Both come after the v0.1.2 and v0.2.0 lifecycle work.
- #10 Lock screen redesign. Starts with mockups the user chooses between; the implementation keeps the existing auth,
  lifecycle and dry-run preview.
- #20 Notifications: grouping, per-app rules, unread indicator, stacked bubbles (decide whether a stack fits the island)

## v0.6.0: settings app
The largest item. First split #11 into sub-issues: window and navigation, schema-driven page generator, config writer,
then one per page group. The pages expose features from v0.3.0 to v0.5.0, which is why it follows them.
- #11 Settings UI (tracking)
- #19 Theming breadth: more app templates, scheme variants. Per-app opt-outs belong in the Theming page.

## v0.7.0: capture and calendar
- #14 Screenshot and screen recording. **Gate:** the README lists this as out of scope; decide whether to lift that or
  ship only an indicator plus a grim/slurp wrapper.
- #23 Calendar events: local vdir/.ics first, CalDAV later

## v0.8.0: window overview
- #21 Window overview. Starts with a spike on preview-capture cost, then a decision on overlap with #27.

## v0.9.0: dock, widgets, greeter
- #25 Optional dock, desktop widgets, greetd greeter. Independent and low priority given the island-first design; can
  be split into three tags or dropped without affecting anything else.

## v1.0.0: plugin API
- #24 Plugin API for third-party sections and widgets. It fixes the extension surface of the Ink components and
  services, which is the contract a 1.0 should commit to. Only worth doing once there are users besides the author,
  after packaging (#18) is in place.

## Notes
- Several issue bodies cite `v1.4.0`, `v1.0.0` and "phase one/five/six". The repository has one commit and one tag
  (`v0.1.0`), so those refer to earlier history. This roadmap numbers from `v0.1.0`.
- A release that changes live state needs the CLAUDE.md sequence: `qs -c gutter kill`, merge, run the migration script.
  None of the planned tags currently needs a migration; #17 (workspace groups) and #11 (config writer) are the likely ones.
