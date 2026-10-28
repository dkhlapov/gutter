//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.settings
import "lib/config.js" as ConfigLib

// The Auth check (scripts/auth.sh), one scenario per run (AUTH_SCENARIO), against the real services/Auth.qml. The
// script sets GUTTER_LOCK_PAM_DIR to a dummy PAM folder (or one made to be refused), a PATH with an `fprintd-list`
// shim and AUTH_DIR, a scratch folder the shims write their logs to; counting what the shims logged is left to the
// script. Each scenario is a list of steps: wait `wait` ms, then until `until` holds (`max` ms at the most, a
// failure when it does not), then `run`.
ShellRoot {
    id: shell

    readonly property string scenario: Quickshell.env("AUTH_SCENARIO") ?? ""
    readonly property string scratch: Quickshell.env("AUTH_DIR") ?? ""
    // A password that is none of the right ones; like the right one, it must reach no log.
    readonly property string wrong: Quickshell.env("AUTH_WRONG") ?? ""
    property var failures: []
    property int checks: 0
    property int flashes: 0
    property int successes: 0
    property int stepIndex: -1
    property double stepStart: 0
    property var steps: []
    property bool finished: false
    property double beganAt: 0

    function expect(ok, what) {
        checks++;
        if (!ok)
            failures.push(what);
    }

    // A key the way a surface hands it over.
    function press(key, text, modifiers) {
        Auth.key({ key: key, text: text, modifiers: modifiers ?? 0, isAutoRepeat: false });
    }

    function type(word) {
        for (const ch of word)
            press(ch.toUpperCase().charCodeAt(0), ch);
    }

    function enter() {
        press(Qt.Key_Return, "\r");
    }

    function resetCounts() {
        flashes = 0;
        successes = 0;
    }

    // Whether the process in AUTH_DIR/probe.pid is still alive: polled by a step until it is not.
    Process {
        id: alive

        property bool done: false
        property int code: -1

        command: ["bash", "-c", 'kill -0 "$(cat "$AUTH_DIR/probe.pid")" 2>/dev/null']
        onExited: code => {
            alive.code = code;
            alive.done = true;
        }
    }

    function aliveProbe() {
        alive.done = false;
        alive.running = true;
    }

    // Writes the config file the settings follow (a plain truncating write, which the watch sees).
    Process {
        id: writer
    }

    function writeConfig(fingerprint) {
        writer.command = ["bash", "-c", 'printf "%s" "$1" > "$XDG_CONFIG_HOME/gutter/config.json"', "x",
            JSON.stringify({ configVersion: ConfigLib.defaults().configVersion, lockscreen: { fingerprint: fingerprint } })];
        writer.running = true;
    }

    Connections {
        target: Auth

        function onFlash(): void {
            shell.flashes++;
        }

        function onSucceeded(): void {
            shell.successes++;
        }
    }

    readonly property var scenarios: ({
        // A wrong password is reported (state, count, flash) and does not unlock; the right one unlocks once.
        "password": () => [
            {
                name: "begin",
                run: () => {
                    Auth.begin();
                    resetCounts();
                    type(wrong);
                    enter();
                    expect(Auth.checking, "the check did not start on Enter");
                }
            },
            {
                name: "a wrong password",
                until: () => Auth.stateKind !== "",
                run: () => {
                    expect(Auth.stateKind === "wrong", `state after a wrong password is "${Auth.stateKind}"`);
                    expect(Auth.failures === 1, `failures is ${Auth.failures}`);
                    expect(flashes === 1, `flash fired ${flashes} times`);
                    expect(successes === 0, "a wrong password unlocked");
                    expect(Auth.buffer === "", "the buffer kept a wrong password");
                    expect(!Auth.checking, "still checking after the answer");
                    type("guttertest");
                    enter();
                }
            },
            {
                name: "the right password",
                until: () => successes > 0,
                run: () => expect(Auth.stateKind === "", `state after the right password is "${Auth.stateKind}"`)
            },
            {
                name: "once",
                wait: 600,
                run: () => {
                    expect(successes === 1, `succeeded fired ${successes} times`);
                    expect(Auth.failures === 1, `failures is ${Auth.failures} after the right password`);
                }
            }
        ],

        // While the check runs, keys change nothing and start nothing (the script logs each run of the check).
        "busy": () => [
            {
                name: "start a slow check",
                run: () => {
                    Auth.begin();
                    resetCounts();
                    type("guttertest");
                    enter();
                    expect(Auth.checking, "the check did not start");
                }
            },
            {
                name: "keys while checking",
                wait: 200,
                run: () => {
                    expect(Auth.checking, "the check ended early");
                    // The password is with PAM by now; this one is a stand-in for something typed after it.
                    expect(Auth.buffer === "", "the password was not handed to PAM");
                    Auth.buffer = "keep";
                    const before = Auth.buffer;
                    // After each key, so that one key undoing another cannot hide it.
                    const keys = [
                        ["a letter", () => type("x")],
                        ["Enter", () => enter()],
                        ["Backspace", () => press(Qt.Key_Backspace, "\b")],
                        ["Ctrl+Backspace", () => press(Qt.Key_Backspace, "\b", Qt.ControlModifier)],
                        ["Escape", () => press(Qt.Key_Escape, "\u001b")],
                        ["two letters", () => type("yz")]
                    ];
                    for (const [label, send] of keys) {
                        send();
                        expect(Auth.buffer === before, `${label} changed the buffer while checking`);
                    }
                    // A second check() starts nothing: Quickshell would not start a second run of a running
                    // context anyway, so the guard's own effect is pinned by the timeout scenario.
                    Auth.check();
                    Auth.check();
                    expect(Auth.checking, "the check stopped");
                }
            },
            {
                name: "the right password",
                until: () => successes > 0
            },
            {
                name: "once",
                wait: 1500,
                run: () => {
                    expect(successes === 1, `succeeded fired ${successes} times`);
                    expect(flashes === 0, `flash fired ${flashes} times`);
                    expect(!Auth.checking, "still checking");
                }
            }
        ],

        // A check that outlives passwdTimeoutMs is an error, takes keys again, and cannot unlock when it ends. (The
        // `|| root.reported` guard in passwd.onCompleted cannot be reached from here: abort() makes the late result
        // a non-success, so it is defence in depth.)
        "timeout": () => [
            {
                name: "start a stuck check",
                run: () => {
                    Auth.passwdTimeoutMs = 500;
                    Auth.begin();
                    resetCounts();
                    type("guttertest");
                    enter();
                    beganAt = Date.now();
                    expect(Auth.checking, "the check did not start");
                }
            },
            {
                // A check() while one runs must not start a second one or push the timeout back: late in the run, so
                // that a guard that restarts the timer would show as an error well after 500 ms.
                name: "a check meanwhile",
                wait: 450,
                run: () => {
                    // A machine so loaded that the timeout has fired already has nothing to show here.
                    if (Auth.stateKind !== "")
                        return;
                    expect(Auth.checking, "the check ended without an answer");
                    Auth.check();
                    expect(Auth.checking && Auth.stateKind === "", `a second check() changed things (state "${Auth.stateKind}")`);
                }
            },
            {
                name: "the timeout",
                until: () => Auth.stateKind !== "",
                max: 3000,
                run: () => {
                    const took = Date.now() - beganAt;
                    expect(took < 900, `the timeout came after ${took} ms, not about 500`);
                    expect(Auth.stateKind === "error", `state after the timeout is "${Auth.stateKind}"`);
                    expect(!Auth.checking, "still checking after the timeout");
                    expect(flashes === 1, `flash fired ${flashes} times`);
                    expect(Auth.failures === 0, "a timeout counted as a wrong password");
                    press(Qt.Key_A, "a");
                    expect(Auth.buffer === "a", `keys are still refused after the timeout (buffer "${Auth.buffer}")`);
                }
            },
            {
                name: "the late end",
                wait: 3500,
                run: () => {
                    expect(successes === 0, "the late success of a timed out check unlocked");
                    expect(Auth.stateKind === "error" || Auth.stateKind === "", `state at the end is "${Auth.stateKind}"`);
                }
            }
        ],

        // A PAM folder without the stack refuses the check before PAM starts, so the account's own stack is never
        // asked. `Auth.pamStackFound` is looked at first, and nothing is typed unless it says no.
        "refused": () => [
            {
                name: "begin",
                run: () => {
                    // Before begin(), which would start the probe: a guard that fails ends the run here.
                    const found = Auth.pamStackFound("passwd");
                    expect(!found, "the guard accepted a folder without a usable passwd file");
                    expect(!Auth.pamStackFound("fprint"), "the guard accepted a folder without a usable fprint file");
                    if (found) {
                        finish();
                        return;
                    }
                    Auth.begin();
                    resetCounts();
                    expect(Auth.testPam, "the test folder is not in use");
                    expect(!Auth.fingerprintLive, "the fingerprint is live without its stack");
                    type(wrong);
                    enter();
                    expect(!Auth.checking, "a check started without a passwd stack");
                    expect(Auth.stateKind === "error", `state is "${Auth.stateKind}"`);
                    expect(flashes === 1, `flash fired ${flashes} times`);
                    expect(Auth.buffer === "", "the buffer kept the password");
                    Auth.check();
                    expect(!Auth.checking, "a check started on a second try");
                }
            },
            {
                name: "still refused",
                wait: 1500,
                run: () => {
                    expect(!Auth.checking, "a check started later");
                    expect(!Auth.fingerprintLive, "the fingerprint went live");
                    expect(successes === 0, "succeeded fired");
                }
            }
        ],

        // The password stack is there and the fingerprint's is not: the password works, the reader is not touched.
        "nofprint": () => [
            {
                name: "begin",
                run: () => {
                    Auth.begin();
                    resetCounts();
                    expect(Auth.pamStackFound("passwd"), "the guard refused the passwd file");
                    expect(!Auth.pamStackFound("fprint"), "the guard accepted a missing fprint file");
                    type("guttertest");
                    enter();
                }
            },
            {
                name: "the right password",
                until: () => successes > 0,
                run: () => expect(!Auth.fingerprintLive, "the fingerprint is live without its stack")
            },
            {
                name: "no reader",
                wait: 1200,
                run: () => {
                    expect(successes === 1, `succeeded fired ${successes} times`);
                    expect(!Auth.fingerprintLive, "the fingerprint went live");
                }
            }
        ],

        // fprintd-list never answers: begin() returns, the password works, and end() kills the probe.
        "hanging": () => [
            {
                name: "begin",
                run: () => {
                    beganAt = Date.now();
                    Auth.begin();
                    expect(Date.now() - beganAt < 500, `begin() took ${Date.now() - beganAt} ms`);
                    resetCounts();
                    type("guttertest");
                    enter();
                }
            },
            {
                name: "the password meanwhile",
                until: () => successes > 0,
                run: () => {
                    expect(!Auth.fingerprintLive, "the fingerprint is live while the probe hangs");
                    aliveProbe();
                }
            },
            {
                name: "the probe is running",
                until: () => alive.done,
                run: () => expect(alive.code === 0, "the probe is not running before end()")
            },
            {
                name: "end",
                run: () => {
                    Auth.end();
                    aliveProbe();
                }
            },
            {
                name: "the probe is gone",
                max: 4000,
                until: () => {
                    if (alive.running || !alive.done)
                        return false;
                    if (alive.code !== 0)
                        return true;
                    aliveProbe();
                    return false;
                },
                run: () => {
                    expect(successes === 1, `succeeded fired ${successes} times`);
                    expect(!Auth.fingerprintLive, "the fingerprint went live");
                }
            }
        ],

        // begin() twice in a row: one probe is let finish, the reader ends up in use, a warning says so.
        "twice": () => [
            {
                name: "begin twice",
                run: () => {
                    Auth.begin();
                    Auth.begin();
                }
            },
            {
                name: "the reader",
                until: () => Auth.fingerprintLive,
                run: () => expect(Auth.live, "the lock is not live")
            },
            {
                name: "stays",
                wait: 1500,
                run: () => {
                    expect(Auth.fingerprintLive, "the reader was given up on");
                    expect(Auth.live, "the lock is not live");
                    expect(successes === 0, "succeeded fired");
                }
            }
        ],

        // The setting follows the file: off stops the reader, on probes again.
        "setting": () => [
            {
                name: "the settings",
                until: () => Settings.loadedOnce && Settings.lockscreen.fingerprint === true
            },
            {
                name: "begin",
                run: () => {
                    expect(Settings.lockscreen.fingerprint === true, "the fingerprint setting is not on");
                    Auth.begin();
                }
            },
            {
                name: "the reader",
                until: () => Auth.fingerprintLive
            },
            {
                name: "off",
                run: () => writeConfig(false)
            },
            {
                name: "the reader stops",
                until: () => !Auth.fingerprintLive,
                max: 4000,
                run: () => {
                    expect(Settings.lockscreen.fingerprint === false, "the setting did not change");
                    expect(Auth.live, "the lock is not live");
                }
            },
            {
                name: "stays off",
                wait: 1500,
                run: () => {
                    expect(!Auth.fingerprintLive, "the reader came back with the setting off");
                    writeConfig(true);
                }
            },
            {
                name: "the reader again",
                until: () => Auth.fingerprintLive,
                max: 4000,
                run: () => expect(Settings.lockscreen.fingerprint === true, "the setting did not change back")
            },
            {
                name: "stays on",
                wait: 1500,
                run: () => {
                    expect(Auth.fingerprintLive, "the reader was given up on");
                    expect(successes === 0, "succeeded fired");
                }
            }
        ]
    })

    function finish() {
        if (finished)
            return;
        finished = true;
        tick.stop();
        for (const f of failures)
            console.log(`auth: ${scenario} FAIL: ${f}`);
        if (failures.length === 0)
            console.log(`auth: ${scenario} ok (${checks} checks)`);
        else
            console.log(`auth: ${scenario} FAIL (${failures.length} of ${checks} checks)`);
        Auth.end();
        Qt.quit();
    }

    function next() {
        stepIndex++;
        stepStart = Date.now();
        if (stepIndex >= steps.length)
            finish();
    }

    function advance() {
        const step = steps[stepIndex];
        const elapsed = Date.now() - stepStart;
        if (elapsed < (step.wait ?? 0))
            return;
        if (step.until && !step.until()) {
            if (elapsed >= (step.max ?? 5000)) {
                failures.push(`timed out waiting for: ${step.name}`);
                finish();
            }
            return;
        }
        try {
            if (step.run)
                step.run();
        } catch (e) {
            failures.push(`${step.name}: ${e}`);
            finish();
            return;
        }
        if (!finished)
            next();
    }

    Timer {
        id: tick

        interval: 20
        repeat: true
        onTriggered: shell.advance()
    }

    Component.onCompleted: {
        if (!scenarios[scenario] || scratch === "") {
            console.log(`auth: ${scenario} FAIL: unknown scenario or no AUTH_DIR`);
            Qt.callLater(Qt.quit);
            return;
        }
        // Nothing is typed unless the PAM folder is the scenario's own test one: otherwise the account's would be asked.
        if (!Auth.testPam || !Auth.pamDir.startsWith(scratch + "/")) {
            console.log(`auth: ${scenario} FAIL: not a test PAM folder of this run ("${Auth.pamDir}")`);
            Qt.callLater(Qt.quit);
            return;
        }
        steps = scenarios[scenario]();
        next();
        tick.start();
    }
}
