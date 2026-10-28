//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import qs.services

// The lock's Auth service under Quickshell (scripts/lock-qml.sh): the real services/Auth.qml, with the test PAM
// folder (GUTTER_LOCK_PAM_DIR) and a PATH the script sets up. One scenario per run, named by LOCKQML_SCENARIO:
//   nofprintd   no `fprintd-list` on PATH: the warning is said once, however often the lock begins; no fingerprint
//   fingerprint `fprintd-list` lists a print: the reader is live, and the lock's end puts it away
//   noprints    `fprintd-list` says no print is enrolled: no fingerprint, and no warning
//   password    a wrong password, then the right one
// The script reads the log for what only the log shows (the warning, and that no password reaches it); this file
// prints `lockqml: ...` lines and `lockqml: OK` when its own expectations hold.
ShellRoot {
    id: shell

    readonly property string scenario: Quickshell.env("LOCKQML_SCENARIO") ?? ""
    readonly property string wrong: Quickshell.env("LOCKQML_WRONG") ?? ""
    readonly property string right: "guttertest"

    property var problems: []
    property int checks: 0
    property int wrongFlashes: 0
    property int unlocks: 0

    function expect(name, ok) {
        checks++;
        console.log("lockqml: " + scenario + ": " + name + ": " + (ok ? "ok" : "FAIL"));
        if (!ok)
            problems.push(name);
    }

    // Types a string, key by key, and presses Enter.
    function type(text, enter) {
        for (const ch of text)
            Auth.key({ key: Qt.Key_A, text: ch, modifiers: 0, isAutoRepeat: false });
        if (enter)
            Auth.key({ key: Qt.Key_Return, text: "\r", modifiers: 0, isAutoRepeat: false });
    }

    function finish() {
        Auth.end();
        if (problems.length > 0)
            console.log("lockqml: FAIL (" + problems.join("; ") + ")");
        else
            console.log("lockqml: OK (" + scenario + ", " + checks + " checks)");
        Qt.quit();
    }

    function run() {
        expect("the test PAM folder is in use", Auth.testPam);
        switch (scenario) {
        case "nofprintd":
            // The checks follow the warning (onProbeWarnedChanged).
            Auth.begin();
            break;
        case "noprints":
            Auth.begin();
            settle.restart();
            break;
        case "fingerprint":
            Auth.begin();
            break;
        case "password":
            // No reader: the scenario is about the password alone.
            Auth.fingerprintAllowed = false;
            Auth.begin();
            type(wrong, true);
            break;
        default:
            problems.push("unknown scenario \"" + scenario + "\"");
            finish();
        }
    }

    Connections {
        target: Auth

        function onFlash() {
            shell.wrongFlashes++;
            if (shell.scenario !== "password")
                return;
            shell.expect("a wrong password is wrong", Auth.stateKind === "wrong");
            shell.expect("a wrong password counts once", Auth.failures === 1);
            shell.expect("a wrong password empties the buffer", Auth.buffer === "" && Auth.length === 0);
            shell.expect("a wrong password does not unlock", shell.unlocks === 0);
            // Not from inside the failed check's own completion: the next conversation starts after it.
            Qt.callLater(() => shell.type(shell.right, true));
        }

        function onSucceeded() {
            shell.unlocks++;
            if (shell.scenario !== "password")
                return;
            shell.expect("one wrong password flashed once", shell.wrongFlashes === 1);
            shell.expect("the right password is no failure", Auth.failures === 1);
            shell.expect("the right password empties the buffer", Auth.buffer === "");
            shell.expect("the right password leaves no failure text", Auth.stateKind === "");
            shell.finish();
        }

        function onProbeWarnedChanged() {
            if (shell.scenario !== "nofprintd")
                return;
            shell.expect("the missing fprintd-list is noted", Auth.probeWarned);
            shell.expect("no fingerprint without fprintd-list", !Auth.fingerprintLive);
            // The lock appears a second time: the warning is not said again (the script counts the log's lines).
            // Not from inside the probe's own end: the lock goes away and comes back after it.
            Qt.callLater(() => {
                Auth.end();
                Auth.begin();
                again.restart();
            });
        }

        function onFingerprintLiveChanged() {
            if (shell.scenario === "fingerprint" && Auth.fingerprintLive) {
                // Give the reader's PAM run time to fail and be restarted, then release the lock.
                settle.restart();
            }
        }
    }

    // Time for a probe that finds nothing to have ended (noprints), or for the reader's loop to run.
    Timer {
        id: settle

        interval: 1500
        onTriggered: {
            if (shell.scenario === "fingerprint") {
                shell.expect("fprintd-list ran", Auth.probeStarted);
                shell.expect("the reader is still live", Auth.fingerprintLive);
                Auth.end();
                shell.expect("the end of the lock puts the reader away", !Auth.fingerprintLive);
                shell.finish();
            } else {
                shell.expect("fprintd-list ran", Auth.probeStarted);
                shell.expect("no fingerprint without a print", !Auth.fingerprintLive);
                shell.finish();
            }
        }
    }

    // After the second begin() of nofprintd; the script checks that its log has the warning only once.
    Timer {
        id: again

        interval: 1000
        onTriggered: {
            shell.expect("no fingerprint the second time either", !Auth.fingerprintLive);
            shell.expect("the warning stays noted", Auth.probeWarned);
            shell.finish();
        }
    }

    // A scenario that never ends fails loudly rather than hanging the run.
    Timer {
        interval: 20000
        running: true
        onTriggered: {
            console.log("lockqml: FAIL (" + shell.scenario + " timed out)");
            Qt.quit();
        }
    }

    Timer {
        interval: 300
        running: true
        onTriggered: shell.run()
    }
}
