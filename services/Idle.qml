pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.settings
import "../lib/idle.js" as IdleLib

// Idle timers, screen off and on, the lock before sleep and the reaction to logind's `Lock` signal. Idle only ever
// asks for a lock (`Lock.request()`, which is idempotent) and never unlocks anything.
//
// - Two IdleMonitors: after `lockscreen.idle.lock` seconds without input the lock is requested; after
//   `lockscreen.idle.screenOff` the screens go off, and the first activity after that turns them on again, without
//   unlocking. Audio playing (`inhibitWhenAudio`) stops both timers, and applications' idle inhibitors (and the
//   pill's "Keep awake") are respected. The screens are never left off while the user is active: they come on at
//   activity, on resume, on a sleep's lock, when the timer or Idle itself is switched off, and once at start (a
//   restart or reload may have found them off). The idle lock and other lock requests leave them as they are: a user
//   who is away is not woken by the lock.
// - A `gdbus monitor --system` process prints logind's signals (busctl's monitor needs root): the session's `Lock`
//   locks, and `PrepareForSleep` drives the sleep hold: a delay inhibitor (`helper`) is kept while sleeping is
//   allowed to wait for us and the monitor runs (a lock nobody listens to would only slow every suspend); on
//   "sleep" Gutter locks and drops the helper once the compositor has confirmed the lock (`Lock.secure`, not
//   merely `Lock.locked`, which is true at the request), or after two seconds so that a failure never blocks the
//   sleep, and takes it again on resume. `sleepState` is lib/idle.js' `{helper, waiting}` and `helper` is true only
//   while the inhibit process is meant to run (and is fed back if it exits by itself). The helper's stdin is kept
//   open: if the shell dies, `cat` sees the pipe close and the inhibitor goes with it.
//
// Dry run (GUTTER_IDLE_DRY_RUN=1): turning the screens off or on only logs and sets `lastDryRun` (`dpms:off`,
// `dpms:on`); an idle, logind or sleep lock logs and sets it to `lock (dry run)` and goes through `Lock.request()`,
// which has its own dry run (GUTTER_LOCK_DRY_RUN), and without that Idle does not ask for a lock at all, so a dry run
// can never lock the real session. Only in that dry run does the preview count as a lock that is up for a sleep. The
// sleep helper is then a plain `cat`, not a real inhibitor, and GUTTER_IDLE_MONITOR_CMD (a JSON array of strings)
// replaces the logind monitor command; both are ignored outside a dry run.
Singleton {
    id: root

    // Idle runs when the lock screen is on and this is not an inert (smoke or gallery) instance.
    readonly property bool active: Settings.lockscreen.enabled && !Lock.inert
    readonly property bool dryRun: Quickshell.env("GUTTER_IDLE_DRY_RUN") === "1"
    // The last thing a dry run would have done ("dpms:off", "dpms:on" or "lock (dry run)", the last one only when
    // Lock.request() went on to do something), for checks.
    property string lastDryRun: ""
    // The screens are off, as far as Idle knows.
    property bool screensOff: false
    // How often the 2 s sleep timeout has fired, for checks.
    property int sleepTimeouts: 0

    readonly property int lockSeconds: Settings.lockscreen.idle.lock
    readonly property int screenOffSeconds: Settings.lockscreen.idle.screenOff
    // An IdleMonitor keeps the timeout it was enabled with: a new one only counts after it is enabled again, in a
    // later turn of the event loop. A change of either timeout (the settings load a moment after start, or the
    // user edits them) therefore switches both monitors off and, 50 ms later, on again.
    property bool cycling: false
    // The screens were turned on for this start of Idle.
    property bool wokeAtStart: false
    readonly property bool audioInhibits: IdleLib.inhibited(Media.playing, Settings.lockscreen.idle.inhibitWhenAudio)
    readonly property bool lockTimerOn: active && !cycling && IdleLib.timerOn(lockSeconds, audioInhibits)
    readonly property bool screenTimerOn: active && !cycling && IdleLib.timerOn(screenOffSeconds, audioInhibits)
    // Locking before sleep is on.
    readonly property bool sleepEnabled: active && !!Settings.lockscreen.idle.lockBeforeSleep
    // The hold on sleep: `helper` (our delay inhibitor is meant to be held), `waiting` (a sleep waits for the lock).
    property var sleepState: ({ helper: false, waiting: false })
    // Times in a row the helper exited by itself; after a few Idle stops taking it again.
    property int helperFailures: 0
    property double helperStartedAt: 0
    // The compositor has confirmed the lock (or, in Idle's dry run, the preview is up) and it is not being unlocked
    // (`Lock.unlocking` is set before the fade moves): a sleep then has nothing left to lock. During the unlock the
    // lock is still held but about to go, so a request is queued by Lock and Idle's retry asks again when it has gone.
    readonly property bool lockUp: IdleLib.lockUp(Lock.secure, Lock.preview, Lock.fade, Lock.unlocking, dryRun)
    // The logind monitor runs, and a sleep may wait for us: only then is the delay inhibitor held.
    readonly property bool holdWanted: sleepEnabled && monitor.running
    // Pause before the monitor is started again after it exited: 1 s, doubling to 30 s while it keeps failing.
    property int monitorBackoff: 1000
    property double monitorStartedAt: 0

    readonly property string sessionId: Quickshell.env("XDG_SESSION_ID") ?? ""
    readonly property var monitorCmd: dryRunMonitorCmd() ?? IdleLib.monitorCommand()
    readonly property var helperCmd: dryRun ? ["cat"] : IdleLib.inhibitCommand()

    function dryRunMonitorCmd(): var {
        if (!dryRun)
            return null;
        const raw = Quickshell.env("GUTTER_IDLE_MONITOR_CMD") ?? "";
        if (raw === "")
            return null;
        try {
            const cmd = JSON.parse(raw);
            if (Array.isArray(cmd) && cmd.length > 0 && cmd.every(a => typeof a === "string"))
                return cmd;
        } catch (e) {}
        console.warn("gutter: idle: GUTTER_IDLE_MONITOR_CMD is not a JSON array of strings, using logind");
        return null;
    }

    // --- screens -----------------------------------------------------------------------------------------------

    // Turns the outputs off or on. Idle does not turn them back on when a lock ends: only activity, a resume, a
    // sleep's lock, the screen timer or Idle stopping, or Idle starting does.
    function setScreens(off: bool): void {
        screensOff = off;
        if (dryRun) {
            lastDryRun = off ? "dpms:off" : "dpms:on";
            console.info(`gutter: idle: ${lastDryRun} (dry run)`);
        } else {
            Quickshell.execDetached(IdleLib.dpmsCommand(!off));
        }
    }

    // --- locking -----------------------------------------------------------------------------------------------

    // Asks for the lock (idle, logind's Lock, a sleep, a retry). Lock.request() is idempotent. The screens come on
    // only for a sleep (`wake`): the idle lock must not wake a user who is away.
    function lockNow(why: string, wake: bool): void {
        if (dryRun && !Lock.dryRun) {
            console.warn(`gutter: idle: dry run, not asking for a lock (${why}): GUTTER_LOCK_DRY_RUN is off`);
            return;
        }
        if (wake && screensOff)
            setScreens(false);
        // A lock that is held or showing makes Lock.request() do nothing.
        if (dryRun && !Lock.locked && !Lock.preview) {
            lastDryRun = "lock (dry run)";
            console.info(`gutter: idle: lock (dry run) (${why})`);
        }
        Lock.request();
    }

    // The lock came up or went (the real lock, or the dry-run preview).
    function lockEdge(): void {
        const edge = IdleLib.lockEdge({ secure: Lock.secure, preview: Lock.preview, locked: Lock.locked, fade: Lock.fade, unlocking: Lock.unlocking, dryRun: dryRun }, sleepState.waiting);
        if (edge === "locked") {
            feedSleep("locked");
        } else if (edge === "retry") {
            // The request was lost or the lock failed (requests during an unlock are queued by Lock now): the
            // sleep still waits, so ask again. A pause keeps a request that fails at once from looping.
            retryLock.restart();
        }
    }

    // --- logind ------------------------------------------------------------------------------------------------

    function onLine(line: string): void {
        const event = IdleLib.logindEvent(line, sessionId);
        if (event === "lock") {
            lockNow("logind lock", false);
        } else if (event === "sleep" || event === "resume") {
            if (event === "resume") {
                helperFailures = 0;
                // Whatever turned the screens off before the sleep, they come on with the machine.
                setScreens(false);
            }
            feedSleep(event);
        }
    }

    // One step of the hold on sleep. The new state is stored before the actions run: a lock can answer at once.
    function feedSleep(event: string): void {
        const result = IdleLib.sleepStep(sleepState, event, { enabled: sleepEnabled, locked: lockUp });
        sleepState = result.state;
        if (result.actions.includes("lock")) {
            sleepTimeout.restart();
            lockNow("sleep", true);
        }
        syncHelper();
        if (!sleepState.waiting) {
            sleepTimeout.stop();
            retryLock.stop();
        }
    }

    // The helper process follows `sleepState.helper`.
    function syncHelper(): void {
        const want = sleepState.helper && holdWanted;
        if (want && !helper.running) {
            helperStartedAt = Date.now();
            helper.running = true;
        } else if (!want && helper.running) {
            helper.running = false;
        }
    }

    // The helper exited. If we asked (`helper` already false) that is all; if not, we do not hold the inhibitor we
    // thought we did: say so, and take it again a little later.
    function helperExited(code: int): void {
        if (!sleepState.helper || (code === -1 && helper.running))
            return;
        sleepState = { helper: false, waiting: sleepState.waiting };
        // One that ran for a while and died is not a failing start.
        if (Date.now() - helperStartedAt > 10000)
            helperFailures = 0;
        helperFailures++;
        if (code === 127 || helperFailures >= 5) {
            console.warn(`gutter: idle: the sleep inhibitor keeps failing (exit ${code}), not taking it again`);
            return;
        }
        console.warn(`gutter: idle: the sleep inhibitor exited (${code}), taking it again`);
        retakeHelper.restart();
    }

    function helperGone(): void {
        if (sleepState.helper && !helper.running)
            helperExited(-1);
    }

    // The hold was switched on or off: lock-before-sleep, Idle, or the logind monitor starting or stopping.
    function syncEnabled(): void {
        if (holdWanted) {
            if (!sleepState.helper && !sleepState.waiting) {
                helperFailures = 0;
                sleepState = { helper: true, waiting: false };
            }
        } else {
            sleepState = { helper: false, waiting: false };
            sleepTimeout.stop();
            retryLock.stop();
            retakeHelper.stop();
        }
        syncHelper();
    }

    function syncActive(): void {
        if (active) {
            startMonitor();
            // A restart or reload may have found the screens off, and nothing else would turn them on.
            if (!wokeAtStart) {
                wokeAtStart = true;
                setScreens(false);
            }
        } else {
            wokeAtStart = false;
            monitorRestart.stop();
            monitor.running = false;
            // Never leave the screens off behind.
            if (screensOff)
                setScreens(false);
        }
        syncEnabled();
    }

    onLockSecondsChanged: Qt.callLater(cycle)
    onScreenOffSecondsChanged: Qt.callLater(cycle)

    function cycle(): void {
        cycling = true;
        cycleTimer.restart();
    }

    // The timer was switched off (audio began, the setting went to 0, Idle stopped) while the screens were off.
    onScreenTimerOnChanged: {
        if (!screenTimerOn && screensOff)
            setScreens(false);
    }

    onActiveChanged: syncActive()
    onHoldWantedChanged: syncEnabled()

    function startMonitor(): void {
        if (monitor.running)
            return;
        monitorStartedAt = Date.now();
        monitor.running = true;
    }

    // The monitor is not running (it exited or could not start); it is started again after a growing pause.
    function monitorStopped(code: int): void {
        if (!active || monitor.running || monitorRestart.running)
            return;
        if (Date.now() - monitorStartedAt > 10000)
            monitorBackoff = 1000;
        const message = `gutter: idle: the logind monitor stopped (${code}), starting it again in ${monitorBackoff / 1000} s`;
        if (monitorBackoff < 30000)
            console.warn(message);
        else
            console.debug(message);
        monitorRestart.interval = monitorBackoff;
        monitorRestart.start();
        monitorBackoff = Math.min(30000, monitorBackoff * 2);
    }

    Component.onCompleted: {
        if (sessionId === "")
            console.warn("gutter: idle: XDG_SESSION_ID is not set, logind's Lock signal cannot be told from other sessions'");
        syncActive();
    }

    // --- timers ------------------------------------------------------------------------------------------------

    IdleMonitor {
        id: lockMonitor

        enabled: root.lockTimerOn
        timeout: Math.max(1, root.lockSeconds)
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle)
                root.lockNow("idle", false);
        }
    }

    IdleMonitor {
        id: screenMonitor

        enabled: root.screenTimerOn
        timeout: Math.max(1, root.screenOffSeconds)
        respectInhibitors: true
        onIsIdleChanged: root.setScreens(isIdle)
    }

    Timer {
        id: cycleTimer

        interval: 50
        onTriggered: root.cycling = false
    }

    // The lock came up, went, or was only asked for (which changes nothing for a sleep). The lock ending does
    // nothing about the screens.
    Connections {
        target: Lock

        function onLockedChanged(): void {
            root.lockEdge();
        }

        function onSecureChanged(): void {
            root.lockEdge();
        }

        function onPreviewChanged(): void {
            root.lockEdge();
        }

        // The end of an unlock matters like the fade did: a finished one lets a waiting sleep retry (and, should an
        // unlock ever end with the lock still up, the lock counts as up again).
        function onUnlockingChanged(): void {
            root.lockEdge();
        }
    }

    // --- processes ---------------------------------------------------------------------------------------------

    Process {
        id: monitor

        command: root.monitorCmd
        stdout: SplitParser {
            onRead: line => root.onLine(line)
        }
        onExited: code => root.monitorStopped(code)
        // A process that could not start gives no `exited`: look again once the signals have run.
        onRunningChanged: {
            if (!running)
                Qt.callLater(root.monitorStopped, -1);
        }
    }

    Timer {
        id: monitorRestart

        interval: 1000
        onTriggered: {
            if (root.active)
                root.startMonitor();
        }
    }

    // The delay inhibitor. `sleepState.helper` says whether it is meant to run; syncHelper() starts and stops it.
    Process {
        id: helper

        command: root.helperCmd
        // The pipe is never written: `cat` ends, and so does the inhibitor, when it closes with the shell.
        stdinEnabled: true
        onExited: code => root.helperExited(code)
        // A process that could not start gives no `exited`: look again once the signals have run.
        onRunningChanged: {
            if (!running)
                Qt.callLater(root.helperGone);
        }
    }

    Timer {
        id: retakeHelper

        interval: 3000
        onTriggered: {
            if (root.sleepEnabled && !root.sleepState.helper && !root.sleepState.waiting) {
                root.sleepState = { helper: true, waiting: false };
                root.syncHelper();
            }
        }
    }

    // A lock that is not up in time lets the sleep go.
    Timer {
        id: sleepTimeout

        interval: IdleLib.SLEEP_LOCK_TIMEOUT_MS
        onTriggered: {
            root.sleepTimeouts++;
            root.feedSleep("timeout");
        }
    }

    Timer {
        id: retryLock

        interval: 100
        onTriggered: {
            if (root.sleepState.waiting && !Lock.locked && !Lock.secure && !Lock.preview)
                root.lockNow("retry", true);
        }
    }
}
