pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.settings
import qs.theme
import "../lib/themeMode.js" as ThemeModeLib
import "../lib/shelf.js" as ShelfLib

// Owns light and dark: works out the wanted mode (sun, schedule, fixed setting or a manual flip) on a 60 s tick
// and on every settings or location change, and runs `gutter theme apply <mode>` when it differs from the mode
// on screen (Theme.mode, from theme.json), nothing was applied yet, or the last apply of it failed. theme-auto.json,
// written only here, keeps the last location (so sun mode works offline) and the flip's override. It also runs
// `gutter hypr` whenever settings are read, so Hyprland's window shadow follows shadow.color (the tool reloads
// Hyprland only when its file differs from the one last loaded);
// that and an apply never run at once (ThemeModeLib.mayStart), so an older mode is never written last. A failure
// is logged and notified once; the tool notifies its own, the shell the ones the tool could not (cannot start,
// timed out) and a new failure of a retry, which runs with GUTTER_NO_NOTIFY.
// With GUTTER_SMOKE=1 (scripts/smoke.sh, which runs this checkout against the real HOME) or GUTTER_GALLERY=1 (a
// dev instance next to the live shell) nothing is applied and theme-auto.json is never written: the mode and
// tooltip are still worked out, but only in memory, so a second instance never undoes the live shell's flips.
Singleton {
    id: root

    readonly property bool smoke: Quickshell.env("GUTTER_SMOKE") === "1"
    readonly property bool gallery: Quickshell.env("GUTTER_GALLERY") === "1"
    // Neither applies nor saves (see above).
    readonly property bool inert: smoke || gallery
    // A `gutter theme apply` still running after this long is stopped and counted as failed.
    readonly property int applyTimeoutMs: 60000
    readonly property string tool: ShelfLib.pathFromUrl(Qt.resolvedUrl("../tools/gutter")) ?? ""
    readonly property string autoFile: Theme.stateDir ? `${Theme.stateDir}/theme-auto.json` : ""

    // From theme-auto.json at start, then kept current from Weather.location and flips. flipped is the manual
    // flip's override ({ mode, until, setFor }), or null.
    property var cachedLocation: null
    property var flipped: null
    readonly property var location: Weather.location ?? cachedLocation

    // Settings load asynchronously: until they have (or a grace period passed, for a config.json that never
    // parses) the defaults would decide, and could apply the wrong mode or clear an override set for another
    // theme.mode.
    property bool graceOver: false
    readonly property bool ready: Settings.loadedOnce || graceOver

    property real now: Date.now()
    readonly property var decision: ThemeModeLib.wanted(now, Settings.theme, location, flipped)
    // The wanted mode, "light" or "dark".
    readonly property string mode: decision.mode
    // "Dark until 07:12 (sunrise)", "Light until 20:00", "Dark (fixed)", for the cell and themeStatus.
    readonly property string tip: ThemeModeLib.tooltip(now, Settings.theme, location, decision.override, decision.mode)

    // The last apply failure logged, so a failure repeated every tick is logged (and notified) once.
    property string lastError: ""
    // The weather.location the last start-up or settings locate used (undefined before the first).
    property var locatedFor: undefined
    // `gutter hypr` bookkeeping ({ pending, failed }, see ThemeModeLib.hyprState): a settings load owes a run, a
    // failed run owes one at the next tick.
    property var hypr: ({ pending: false, failed: false })
    // The last `gutter hypr` failure logged, like lastError for applies.
    property string lastHyprError: ""

    // A manual flip: shows the other mode until the next automatic switch (for good in a fixed mode). Flipping
    // back to the automatic mode clears the override.
    function toggle(): void {
        now = Date.now();
        flipped = ThemeModeLib.flip(now, Settings.theme, location, mode);
        save();
        evaluate();
    }

    // A flip to `wanted`; nothing when that is already the mode.
    function set(wanted: string): void {
        if (wanted !== "light" && wanted !== "dark") {
            console.warn(`gutter: theme: unknown mode ${wanted}, expected light or dark`);
            return;
        }
        now = Date.now();
        if (wanted !== mode)
            toggle();
    }

    function evaluate(): void {
        now = Date.now();
        if (!ready)
            return;
        // An override that no longer wins (expired, or theme.mode changed since the flip) is cleared.
        if (flipped !== null && decision.override === null) {
            flipped = null;
            save();
        }
        if (!ThemeModeLib.mayStart(inert, applier.running, hyprRunner.running))
            return;
        const applied = Theme.modeApplied ? Theme.mode : null;
        if (!ThemeModeLib.needsApply(applied, mode, lastError !== "" ? applier.attempted : ""))
            return;
        applier.attempted = mode;
        applier.handled = false;
        // A retry of a failure already notified only prints (GUTTER_NO_NOTIFY), so a lasting failure notifies once;
        // a different failure of the retry is notified here, from applyFailed.
        applier.toolNotifies = lastError === "";
        const cmd = [tool, "theme", "apply", mode];
        // Before the run: a tool that cannot start stops the watchdog again in onRunningChanged.
        applyWatchdog.restart();
        // R9: the only place an apply starts; it must stay behind the `inert` (smoke/gallery) return above.
        applier.run(applier.toolNotifies ? cmd : ["env", "GUTTER_NO_NOTIFY=1", ...cmd], null);
    }

    function hyprEvent(event: string): void {
        hypr = ThemeModeLib.hyprState(hypr, event);
        refreshHypr();
    }

    // Rewrites Hyprland's config when a run is owed; `gutter hypr` reloads Hyprland only when the file differs from
    // the one last loaded.
    // Waits for a running apply (or hypr run), whose exit calls this again.
    function refreshHypr(): void {
        if (!ready || !hypr.pending || !ThemeModeLib.mayStart(inert, applier.running, hyprRunner.running))
            return;
        hypr = ThemeModeLib.hyprState(hypr, "start");
        hyprRunner.toolNotifies = lastHyprError === "";
        // R9: the only place `gutter hypr` starts; it must stay behind the `inert` (smoke/gallery) return above.
        hyprRunner.run(hyprRunner.toolNotifies ? [tool, "hypr"] : ["env", "GUTTER_NO_NOTIFY=1", tool, "hypr"], null);
    }

    // toolNotified: the tool failed on its own (exit status 1, which its fail() or its EXIT trap notifies from, and
    // every abort of the tool exits 1) in a run it was allowed to notify from: not a timeout, not a tool that could
    // not start, not a retry. A message the other runner's last failure was too is not notified twice (a tool that
    // cannot start fails both at start-up), only logged.
    function applyFailed(message: string, toolNotified: bool): void {
        const f = ThemeModeLib.failure(lastError, message, toolNotified, lastHyprError);
        if (!f.log)
            return;
        lastError = message;
        console.warn(`gutter: theme: ${message}`);
        if (f.notify)
            Quickshell.execDetached(["notify-send", "-a", "gutter", "--", "Gutter", message]);
    }

    function hyprFailed(message: string, toolNotified: bool): void {
        hypr = ThemeModeLib.hyprState(hypr, "failed");
        const f = ThemeModeLib.failure(lastHyprError, message, toolNotified, lastError);
        if (!f.log)
            return;
        lastHyprError = message;
        console.warn(`gutter: theme: ${message}`);
        if (f.notify)
            Quickshell.execDetached(["notify-send", "-a", "gutter", "--", "Gutter", message]);
    }

    function save(): void {
        // R9: the only way theme-auto.json is written (mkdir's onExited); it must stay behind this `inert` guard.
        if (inert || autoFile === "")
            return;
        mkdir.running = true;
    }

    function storeLocation(loc: var): void {
        if (loc === null || ThemeModeLib.sameLocation(loc, cachedLocation))
            return;
        cachedLocation = { lat: loc.lat, lon: loc.lon };
        save();
    }

    // Resolves the location once settings are read (so a configured city is geocoded, not the IP looked up), and
    // again whenever weather.location changes; a cached location may be stale. storeLocation saves only a change.
    function relocate(): void {
        if (!ready || Settings.weather.location === locatedFor)
            return;
        locatedFor = Settings.weather.location;
        Weather.locate();
    }

    Component.onCompleted: {
        if (autoFile !== "") {
            // Blocking, like theme.json in Theme: the first decision already knows the cached location and flip.
            const text = autoState.text();
            const parsed = ThemeModeLib.parseAuto(autoState.loaded ? text : null);
            if (parsed.error)
                console.warn(`gutter: theme: theme-auto.json: ${parsed.error}, ignoring it`);
            cachedLocation = parsed.location;
            flipped = parsed.override;
        }
        storeLocation(Weather.location);
        relocate();
        evaluate();
    }

    onReadyChanged: {
        relocate();
        evaluate();
        hyprEvent("settings");
    }

    Connections {
        target: Settings

        function onThemeChanged(): void {
            root.evaluate();
        }

        function onWeatherChanged(): void {
            root.relocate();
        }

        // Every load, not only a new colour: an apply may have written the file while config.json did not parse.
        function onShadowChanged(): void {
            root.hyprEvent("settings");
        }
    }

    Connections {
        target: Weather

        function onLocationChanged(): void {
            root.storeLocation(Weather.location);
            root.evaluate();
        }
    }

    // Catches suspend, resume and clock jumps too, without a timer aimed at an exact instant.
    Timer {
        running: true
        repeat: true
        interval: 60 * 1000
        onTriggered: {
            root.evaluate();
            root.hyprEvent("tick");
        }
    }

    // Sun mode without a location falls back to the schedule; keep asking while there is none.
    Timer {
        running: root.location === null
        repeat: true
        interval: 60 * 60 * 1000
        onTriggered: Weather.locate()
    }

    Timer {
        running: !root.ready
        interval: 5000
        onTriggered: root.graceOver = true
    }

    FileView {
        id: autoState

        path: root.autoFile
        blockLoading: true
        atomicWrites: true
        printErrors: false
    }

    // FileView does not create parent directories.
    Process {
        id: mkdir

        command: ["mkdir", "-p", "--", Theme.stateDir]
        onExited: code => {
            if (code === 0)
                autoState.setText(ThemeModeLib.autoText(root.cachedLocation, root.flipped));
            else
                console.warn("gutter: theme: cannot create the state folder, theme-auto.json not written");
        }
    }

    // An apply that never exits would keep `applier.running` true and block every later one: stop it and count it
    // as failed (handled, so its exit does not log again); the next evaluate retries. Still running another period
    // after the SIGTERM, it is killed.
    Timer {
        id: applyWatchdog

        interval: root.applyTimeoutMs
        onTriggered: {
            if (!applier.running)
                return;
            if (applier.handled) {
                applier.signal(9); // SIGKILL
                return;
            }
            applier.handled = true;
            root.applyFailed(`gutter theme apply ${applier.attempted} timed out`, false);
            applier.running = false; // SIGTERM
            restart();
        }
    }

    // One apply at a time (evaluate skips while one runs). A failure is retried on the next tick.
    QueuedProcess {
        id: applier

        property string attempted: ""
        property bool handled: false
        // The run may notify from the tool (it is not a retry of a failure already notified).
        property bool toolNotifies: true

        stderr: StdioCollector {
            id: applyErr
        }

        // The streams have finished by now, so applyErr holds all of stderr.
        onExited: code => {
            applyWatchdog.stop();
            // A settings load that waited for this apply.
            Qt.callLater(root.refreshHypr);
            if (handled)
                return; // timed out, already logged
            handled = true;
            if (code !== 0) {
                root.applyFailed(ThemeModeLib.exitMessage(code, toolNotifies, root.tool, applyErr.text,
                    `gutter theme apply ${attempted}`), toolNotifies && code === 1);
                return;
            }
            root.lastError = "";
            // A flip made while this one ran: apply it now rather than on the next tick. The same mode is not
            // re-run here; theme.json's watch brings Theme.mode up to date.
            if (root.mode !== attempted)
                Qt.callLater(root.evaluate);
        }
        // Ended without exiting: the tool could not be started.
        onRunningChanged: {
            if (running)
                return;
            applyWatchdog.stop();
            if (!handled) {
                handled = true;
                root.applyFailed(`cannot run ${root.tool}`, false);
            }
            Qt.callLater(root.refreshHypr);
        }
    }

    // One `gutter hypr` at a time (refreshHypr skips while one runs); quick, so it has no watchdog. A failure is
    // retried on the next tick.
    QueuedProcess {
        id: hyprRunner

        property bool exited: false
        // As for applier.
        property bool toolNotifies: true

        stderr: StdioCollector {
            id: hyprErr
        }

        onRunningChanged: {
            if (running) {
                exited = false;
                return;
            }
            // Ended without exiting: the tool could not be started.
            if (!exited)
                root.hyprFailed(`cannot run ${root.tool}`, false);
            // An apply, or a settings load, that waited for this run.
            Qt.callLater(root.evaluate);
            Qt.callLater(root.refreshHypr);
        }
        onExited: code => {
            exited = true;
            if (code !== 0)
                root.hyprFailed(ThemeModeLib.exitMessage(code, toolNotifies, root.tool, hyprErr.text, "gutter hypr"),
                    toolNotifies && code === 1);
            else
                root.lastHyprError = "";
        }
    }
}
