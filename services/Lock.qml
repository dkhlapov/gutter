pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.settings
import "../lib/lock.js" as LockLib

// Whether to lock and what the lock is saying about itself: `request()` is the one place that decides, and every
// trigger calls it. The lock itself (the session-lock protocol) is held by LockScreen, which copies its state into
// `locked` and listens for `lockRequested`. With `dryRun` set (GUTTER_LOCK_DRY_RUN=1 at start, or `qs ipc call lock
// dryRun true`) a request only logs and shows the preview window, which takes no session lock and has no way to
// unlock one; `unlockDryRun()` closes it. Nothing here unlocks a real lock: that is `LockScreen` clearing
// `held` (which `WlSessionLock.locked` follows) on a successful `Auth` check, and nothing else. An inert run (a smoke or gallery instance next
// to the live shell) never locks. With `lockscreen.enabled` off a request does nothing at all (see lockDecision).
//
// The logind session's LockedHint is how a lock survives a restart of the shell: set when the lock is up, cleared
// when it is released, and read at start. A test run (GUTTER_LOCK_PAM_DIR) or a dry run never writes the real
// session's hint: they use the file named by GUTTER_LOCK_HINT_FILE, or no hint at all without it.
Singleton {
    id: root

    readonly property bool smoke: Quickshell.env("GUTTER_SMOKE") === "1"
    readonly property bool gallery: Quickshell.env("GUTTER_GALLERY") === "1"
    readonly property bool inert: smoke || gallery

    // The real session lock is held, wanted or on its way: LockScreen sets it to `held || confirmed` (asked for, or the
    // compositor confirmed it).
    property bool locked: false
    // The compositor has confirmed the real lock (LockScreen's `confirmed`, from `WlSessionLock.secure`): unlike
    // `locked`, not true for a lock only asked for.
    property bool secure: false
    // The dry-run preview is on screen.
    property bool preview: false
    property bool dryRun: Quickshell.env("GUTTER_LOCK_DRY_RUN") === "1"
    // The last thing a dry run would have done ("lock"), for checks.
    property string lastDryRun: ""
    // The unlock is in progress: LockScreen sets it synchronously when the unlock begins (the fade has not moved
    // yet, so `fade` alone still says "up") and clears it when the unlock ends, after the lock has been released.
    property bool unlocking: false
    // 1 while the screen is up; the unlock fade takes it to 0 (the surfaces and the preview draw their content with it).
    property real fade: 1

    // A real lock was decided on; LockScreen takes it.
    signal lockRequested
    // The answer to `hint.read()`: whether the session was left locked.
    signal hintRead(bool wasLocked)

    readonly property string pamDir: Quickshell.env("GUTTER_LOCK_PAM_DIR") ?? ""
    readonly property string hintPath: Quickshell.env("GUTTER_LOCK_HINT_FILE") ?? ""
    // "logind", or "file" / "none" for a test or dry run, which must not write the real session.
    readonly property string hintBackend: (pamDir !== "" || dryRun) ? (hintPath !== "" ? "file" : "none") : "logind"

    // A start waits for the settings (whether the lock is on) before it looks at the hint; the timer is the
    // fail-safe for settings that never load: a session left locked comes back locked.
    property bool restorePending: false
    property bool restoring: false
    property bool hintReading: false
    // A request arrived while the lock was being unlocked ("queue"): it is asked for again once the lock is gone.
    property bool pendingRequest: false

    function request(): void {
        const decision = LockLib.lockDecision({ locked: locked || preview, unlocking: unlocking, enabled: Settings.lockscreen.enabled });
        if (decision === "ignore")
            return;
        if (decision === "queue") {
            console.info("gutter: lock: requested during the unlock, queued until it has ended");
            pendingTimeout.stop();
            pendingRequest = true;
            return;
        }
        if (dryRun) {
            console.info("gutter: lock (dry run)");
            lastDryRun = "lock";
            preview = true;
        } else if (inert) {
            console.info("gutter: lock: inert, not locking");
        } else {
            lockRequested();
        }
    }

    // A queued request is made again, once, when the lock is gone (see LockLib.pendingStep). It is looked at from
    // the next turn of the event loop, never inside the unlock's own signals: they arrive while `locked` and the
    // lock object are still being torn down. The flag is cleared first and request() decides afresh (it ignores the
    // request if the lock screen has been disabled meanwhile). Should the lock never go (no code path ends an unlock
    // with the lock still up, but if one did, the lock would be up again and the request moot), `pendingTimeout`
    // drops the request.
    function retryPending(): void {
        const step = LockLib.pendingStep({ pending: pendingRequest, unlocking: unlocking, locked: locked, preview: preview });
        if (step !== "retry")
            return;
        pendingRequest = false;
        pendingTimeout.stop();
        console.info("gutter: lock: the lock has gone, making the queued request");
        request();
    }

    function schedulePending(): void {
        if (pendingRequest)
            Qt.callLater(retryPending);
    }

    onUnlockingChanged: {
        if (!unlocking && pendingRequest)
            pendingTimeout.restart();
        schedulePending();
    }
    onLockedChanged: schedulePending()
    onSecureChanged: schedulePending()
    onPreviewChanged: schedulePending()

    // Closes the dry-run preview. Does nothing outside a dry run, and never touches a real lock.
    function unlockDryRun(): void {
        if (dryRun)
            preview = false;
    }

    // A dry run is switched on or off; not while the real lock is held. Returns what happened, for the IPC answer.
    function setDryRun(on: bool): string {
        if (locked) {
            const message = "gutter: lock: locked, dry run not changed";
            console.warn(message);
            return message;
        }
        // A request queued in a dry run must not outlive it (it would open a preview nobody can close).
        pendingRequest = false;
        pendingTimeout.stop();
        if (!on)
            preview = false;
        dryRun = on;
        if (on) {
            const message = "gutter: lock: dry run ON: no real lock will be taken until restart or 'ipc call lock dryRun false'";
            console.warn(message);
            return message;
        }
        const message = "gutter: lock: dry run off: a lock request takes the real lock";
        console.info(message);
        warnPamDir();
        return message;
    }

    // The test PAM folder is in use for a real lock (see the start warning).
    function warnPamDir(): void {
        if (pamDir === "" || dryRun || inert)
            return;
        const hint = hintBackend === "file" ? "the LockedHint goes to GUTTER_LOCK_HINT_FILE, not the real session, so only that file brings the lock back after a restart" : "no LockedHint is written, so a crash will not relock on restart";
        console.warn(`gutter: lock: GUTTER_LOCK_PAM_DIR is set outside a dry run: the lock accepts the test PAM stack's password and ${hint}`);
    }

    // Looks at the hint once at start; a session left locked is locked again.
    function restore(): void {
        if (inert)
            return;
        restorePending = true;
        restoreWait.restart();
        tryRestore();
    }

    function tryRestore(): void {
        if (!restorePending || !Settings.loadedOnce)
            return;
        restoreNow();
    }

    function restoreNow(): void {
        if (!restorePending)
            return;
        restorePending = false;
        restoreWait.stop();
        if (!Settings.lockscreen.enabled)
            return;
        restoring = true;
        hint.read();
    }

    onHintRead: wasLocked => {
        if (!restoring)
            return;
        restoring = false;
        if (wasLocked) {
            console.info("gutter: lock: the session was left locked, locking again");
            request();
        }
    }

    // The LockedHint behind one pair of calls.
    readonly property var hint: QtObject {
        function set(on: bool): void {
            const value = on ? "true" : "false";
            if (root.hintBackend === "logind")
                Quickshell.execDetached(["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session", "SetLockedHint", "b", value]);
            else if (root.hintBackend === "file")
                hintFile.setText(value + "\n");
        }

        // Answers with `hintRead`; "none" has nothing to read.
        function read(): void {
            if (root.hintBackend === "logind") {
                hintProcess.running = true;
            } else if (root.hintBackend === "file") {
                root.hintReading = true;
                hintFile.reload();
            } else {
                root.hintRead(false);
            }
        }
    }

    Process {
        id: hintProcess

        command: ["busctl", "get-property", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session", "LockedHint"]
        stdout: StdioCollector {
            onStreamFinished: root.hintRead(LockLib.parseLockedHint(text))
        }
    }

    FileView {
        id: hintFile

        path: root.hintBackend === "file" ? root.hintPath : ""
        printErrors: false
        onLoaded: {
            if (!root.hintReading)
                return;
            root.hintReading = false;
            root.hintRead(LockLib.parseLockedHint(text()));
        }
        onLoadFailed: {
            if (!root.hintReading)
                return;
            root.hintReading = false;
            root.hintRead(false);
        }
    }

    Connections {
        target: Settings

        function onLoadedOnceChanged(): void {
            root.tryRestore();
        }
    }

    // The lock did not go after the unlock ended: the queued request is moot.
    Timer {
        id: pendingTimeout

        interval: 2000
        onTriggered: {
            if (root.pendingRequest) {
                root.pendingRequest = false;
                console.warn("gutter: lock: the lock did not go after the unlock, queued request dropped");
            }
        }
    }

    Timer {
        id: restoreWait

        interval: 3000
        onTriggered: root.restoreNow()
    }

    Component.onCompleted: {
        warnPamDir();
    }
}
