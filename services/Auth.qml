pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import qs.settings
import "../lib/lock.js" as LockLib

// Unlocking: the typed password, the PAM checks of the password and of a fingerprint, and what the screen says
// about them. The password lives only in `buffer` and in the PAM response; it is never logged, never in a
// message. Only a `Success` result of a PAM run emits `succeeded()`, and nothing else is a way to unlock; the lock
// itself listens for it. `key()` takes the keys the surfaces get, `begin()` runs when the lock appears and
// `end()` when it is released.
//
// Only the repo's own `lockscreen/pam.d` is used, or the folder named by GUTTER_LOCK_PAM_DIR (for checks that must
// not touch the account: `testPam` is then true). libpam falls back to the system's stack when the folder lacks
// the service's file, which would check the real account, so a test folder without a `passwd` (or `fprint`) file
// is refused: the check fails with "error" and the fingerprint is not used.
//
// A password check that has not ended after `passwdTimeoutMs` (a stuck PAM module) is aborted and reported as an
// error, so the screen never stays deaf to keys. `lockscreen.fingerprint` is followed while locked.
Singleton {
    id: root

    // The typed password. Shown to nobody: surfaces draw `length` dots.
    property string buffer: ""
    // Characters (graphemes) in the buffer: an accent, a flag or an emoji family counts one.
    readonly property int length: LockLib.graphemes(buffer).length
    // The password check is running: keys are ignored until it ends.
    readonly property bool checking: passwd.active
    // A fingerprint is enrolled and the reader is in use.
    property bool fingerprintLive: false
    // "", "wrong", "locked" or "error", and what to say about it.
    property string stateKind: ""
    property string stateText: ""
    // Wrong passwords since the lock appeared.
    property int failures: 0
    // The PAM folder is a test one, not the repo's.
    readonly property bool testPam: pamDir !== ""
    // False keeps the fingerprint reader unused (the dry-run preview, which must not touch the account's PAM).
    property bool fingerprintAllowed: true
    // How long a password check may run before it is given up on (milliseconds; a plain property so a test can
    // lower it).
    property int passwdTimeoutMs: 30000

    // A failed check, for the field to shake on.
    signal flash
    // The right password or fingerprint. The only way to unlock.
    signal succeeded

    readonly property string pamDir: Quickshell.env("GUTTER_LOCK_PAM_DIR") ?? ""
    // The failed logins that lock the account, from faillock.conf (3 when it cannot be read).
    property int deny: 3
    // The lock is up between begin() and end(); late PAM results after end() change nothing.
    property bool live: false
    // What PAM said during the current password check (faillock says its lockout over two messages). Never the
    // password: the prompt and the info lines only.
    property string pamMessages: ""
    // Fingerprint runs in a row that ended in an error within fprintQuickMs of starting (a reader that is gone or
    // broken). A run that errors only after its own timeout (pam_fprintd waits 30 s) is not counted.
    property int fprintErrors: 0
    property double fprintStartedAt: 0
    property bool fprintReported: false
    readonly property int fprintQuickMs: 5000
    readonly property int fprintMaxQuickErrors: 5
    // The password check has already been reported (PAM can say `error` and `completed` for one run; a timed-out
    // run is reported too).
    property bool reported: false
    property bool probeStarted: false
    property bool probeWarned: false
    // `lockscreen.fingerprint` as the lock last saw it (read at begin(), and again when the settings change).
    property bool fingerprintWanted: false

    // A key from a surface. `event` is a KeyEvent.
    function key(event: var): void {
        if (passwd.active || stateKind === "locked")
            return;
        let descriptor = { name: "char", text: event.text };
        switch (event.key) {
        case Qt.Key_Return:
        case Qt.Key_Enter:
            descriptor = { name: "enter", repeat: event.isAutoRepeat };
            break;
        case Qt.Key_Backspace:
            descriptor = { name: "backspace", ctrl: (event.modifiers & Qt.ControlModifier) !== 0 };
            break;
        case Qt.Key_Escape:
            descriptor = { name: "escape" };
            break;
        }
        const edit = LockLib.keyEdit(buffer, descriptor);
        if (edit.buffer !== buffer)
            buffer = edit.buffer;
        if (edit.submit)
            check();
    }

    // The lock appeared: forget everything, and use the fingerprint reader when a print is enrolled.
    function begin(): void {
        if (live) {
            console.warn("gutter: lock: Auth.begin() while already begun, starting over");
            end();
        }
        stopContexts();
        buffer = "";
        // faillock's own tally persists across locks, so "N left" can overcount after a re-lock.
        failures = 0;
        fprintErrors = 0;
        clearState();
        live = true;
        fingerprintWanted = !!Settings.lockscreen.fingerprint;
        startProbe();
    }

    // Asks whether a print is enrolled; the fingerprint runs once it is.
    function startProbe(): void {
        if (!fingerprintAllowed || !fingerprintWanted || !Quickshell.env("USER"))
            return;
        if (!pamStackFound("fprint"))
            return;
        // A probe that is still being stopped has already started; its exit is not "never started".
        if (!probe.running)
            probeStarted = false;
        probe.running = true;
    }

    // `lockscreen.fingerprint` changed while locked: stop the reader, or look for a print.
    function applyFingerprintSetting(): void {
        const wanted = !!Settings.lockscreen.fingerprint;
        if (!live || wanted === fingerprintWanted)
            return;
        fingerprintWanted = wanted;
        if (wanted) {
            fprintErrors = 0;
            startProbe();
        } else {
            stopFingerprint();
        }
    }

    // Whether the test PAM folder holds the stack for `service`, read now (a file that is there and not empty).
    // Without it libpam would use the system's stack, which is the real account's. Always true for the repo's own
    // folder.
    function pamStackFound(service: string): bool {
        if (!testPam)
            return true;
        const view = pamFile.createObject(root, { path: `${pamDir}/${service}` });
        // text() makes the blocking load; a missing, unreadable or empty file (or a folder) gives "".
        const found = view !== null && view.text() !== "";
        if (view)
            view.destroy();
        if (!found)
            console.warn(`gutter: lock: GUTTER_LOCK_PAM_DIR has no readable, non-empty "${service}" file, refusing to use PAM`);
        return found;
    }

    // The lock was released (or is being): stop every check and drop the password.
    function end(): void {
        live = false;
        stopContexts();
        buffer = "";
        clearState();
    }

    function check(): void {
        if (passwd.active || !live)
            return;
        pamMessages = "";
        reported = false;
        if (!pamStackFound("passwd")) {
            fail("error");
            return;
        }
        if (passwd.start()) {
            passwdTimeout.restart();
        } else {
            // PAM could not start. The screen stays locked and says so.
            console.warn("gutter: lock: the password check could not start");
            fail("error");
        }
    }

    function startFprint(): void {
        // A run is going (a stale probe answer, or a second one).
        if (fprint.active)
            return;
        if (!pamStackFound("fprint")) {
            fingerprintLive = false;
            return;
        }
        fprintStartedAt = Date.now();
        fprintReported = false;
        if (!fprint.start())
            fprintEnded(true);
    }

    // A fingerprint run ended without a match. `errored` is a PAM error (not a plain miss). A miss or a timeout
    // starts again in a second; a reader that fails at once, over and over, is given up on.
    function fprintEnded(errored: bool): void {
        if (fprintReported)
            return;
        fprintReported = true;
        const quick = Date.now() - fprintStartedAt < fprintQuickMs;
        fprintErrors = errored && quick ? fprintErrors + 1 : 0;
        if (fprintErrors >= fprintMaxQuickErrors) {
            console.warn("gutter: lock: the fingerprint reader keeps failing, giving up");
            fingerprintLive = false;
            return;
        }
        if (live && fingerprintLive)
            restartFprint.restart();
    }

    function stopContexts(): void {
        restartFprint.stop();
        stateReset.stop();
        unlockRetry.stop();
        passwdTimeout.stop();
        passwd.abort();
        stopFingerprint();
    }

    // Stop the probe and the fingerprint run and forget the reader.
    function stopFingerprint(): void {
        restartFprint.stop();
        probe.running = false;
        // The aborted run's own completion is not a result.
        fprintReported = true;
        fprint.abort();
        fingerprintLive = false;
    }

    function clearState(): void {
        stateReset.stop();
        unlockRetry.stop();
        stateKind = "";
        stateText = "";
    }

    // A password check ended without success: `result` is "failed", "error" or "maxtries".
    function fail(result: string): void {
        if (!live || reported)
            return;
        reported = true;
        if (result === "failed")
            failures++;
        const state = LockLib.authState(result, { message: pamMessages, deny: deny, failures: failures });
        stateKind = state.kind;
        stateText = state.text;
        buffer = "";
        console.info(`gutter: lock: password check ${result}`);
        flash();
        if (state.kind === "locked") {
            // Input stays refused while faillock holds the account; the screen takes input again when it is over.
            stateReset.stop();
            const minutes = LockLib.parseFaillock(pamMessages).minutes;
            unlockRetry.interval = (minutes > 0 ? minutes * 60 + 2 : 60) * 1000;
            unlockRetry.restart();
        } else {
            unlockRetry.stop();
            stateReset.restart();
        }
    }

    PamContext {
        id: passwd

        config: "passwd"
        configDirectory: root.testPam ? root.pamDir : Quickshell.shellPath("lockscreen/pam.d")

        // Once per message, where messageChanged skips a line that repeats the one before (faillock repeats lines).
        onPamMessage: {
            if (message !== "")
                root.pamMessages = (root.pamMessages + "\n" + message).slice(-1000);
        }

        onResponseRequiredChanged: {
            if (!responseRequired)
                return;
            // The password goes to PAM and out of memory at once.
            respond(root.buffer);
            root.buffer = "";
        }

        onCompleted: result => {
            passwdTimeout.stop();
            // Not a result: the run was given up on (timed out) or already reported, and a late Success must not
            // unlock a screen that said "error".
            if (!root.live || root.reported)
                return;
            if (result === PamResult.Success) {
                root.reported = true;
                root.buffer = "";
                root.clearState();
                root.succeeded();
            } else if (result === PamResult.Failed) {
                root.fail("failed");
            } else if (result === PamResult.MaxTries) {
                root.fail("maxtries");
            } else {
                root.fail("error");
            }
        }

        onError: error => {
            console.warn(`gutter: lock: PAM error ${PamError.toString(error)}`);
            passwdTimeout.stop();
            root.fail("error");
        }
    }

    PamContext {
        id: fprint

        config: "fprint"
        configDirectory: root.testPam ? root.pamDir : Quickshell.shellPath("lockscreen/pam.d")

        onCompleted: result => {
            if (result === PamResult.Success) {
                // An aborted run's late result (fprintReported is set by then) changes nothing.
                if (root.live && root.fingerprintLive && !root.fprintReported) {
                    root.fprintReported = true;
                    root.succeeded();
                }
                return;
            }
            root.fprintEnded(result === PamResult.Error);
        }

        onError: error => {
            console.warn(`gutter: lock: fingerprint PAM error ${PamError.toString(error)}`);
            root.fprintEnded(true);
        }
    }

    Timer {
        id: restartFprint

        interval: 1000
        onTriggered: {
            if (root.live && root.fingerprintLive && root.fingerprintWanted && !fprint.active)
                root.startFprint();
        }
    }

    // A password check that never ends (a stuck module) is aborted and reported as an error. The report comes first,
    // so nothing the aborted run says after it counts.
    Timer {
        id: passwdTimeout

        interval: root.passwdTimeoutMs
        onTriggered: {
            if (!passwd.active)
                return;
            console.warn("gutter: lock: the password check timed out");
            root.fail("error");
            passwd.abort();
        }
    }

    // The failure text goes away after a few seconds; a lockout is kept until it is over.
    Timer {
        id: stateReset

        interval: 4000
        onTriggered: root.clearState()
    }

    Timer {
        id: unlockRetry

        onTriggered: root.clearState()
    }

    // Whether the user has an enrolled print.
    Process {
        id: probe

        command: ["fprintd-list", Quickshell.env("USER") ?? ""]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.live || !root.fingerprintWanted || !LockLib.hasPrints(text))
                    return;
                root.fingerprintLive = true;
                root.startFprint();
            }
        }
        onStarted: root.probeStarted = true
        // A run that ends without ever starting: fprintd-list is not installed. Said once, then no fingerprint.
        onRunningChanged: {
            if (!running && root.live && !root.probeStarted && !root.probeWarned) {
                root.probeWarned = true;
                console.warn("gutter: lock: fprintd-list did not start, no fingerprint");
            }
        }
    }

    Connections {
        target: Settings

        function onLockscreenChanged(): void {
            root.applyFingerprintSetting();
        }
    }

    // A file of the test PAM folder, read when it is made (see pamStackFound).
    Component {
        id: pamFile

        FileView {
            blockLoading: true
            printErrors: false
        }
    }

    FileView {
        path: "/etc/security/faillock.conf"
        printErrors: false
        onLoaded: root.deny = LockLib.parseDeny(text())
        onLoadFailed: root.deny = 3
    }

    Component.onCompleted: {
        if (testPam)
            console.warn("gutter: lock: TEST PAM directory in use");
    }
}
