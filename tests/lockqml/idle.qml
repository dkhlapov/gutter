//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// The idle service under Quickshell (scripts/lock-qml.sh): the real services/Idle.qml and Lock.qml in a dry run (no
// LockScreen: a lock request turns `Lock.preview` on), with `gdbus monitor` on a private session bus where
// tests/lockqml/fake_logind.py plays logind. The steps below send it commands through a FIFO (LOCKQML_FIFO), so that
// what Idle reads is genuine `gdbus monitor` output, and check what Idle and Lock make of them:
//   startup     the monitor runs and the sleep inhibitor (a `cat`, in a dry run) is held
//   sleep       PrepareForSleep(true) locks, and the lock lets the helper go well before the 2 s timeout; the resume
//               takes the helper again and turns the screens on, and the lock stays up
//   Lock        logind's Lock of our own session locks; another session's Lock and our Unlock do nothing
//   retry       a lock request that Lock ignores during a sleep (the lock is going away, but `Lock.unlocking` is not
//               set) is asked for again by Idle once it has gone, and the sleep is released by the lock that follows;
//               without a sleep there is no retry
//   queue       a request during the unlock (`Lock.unlocking`) is queued by Lock, waits while the lock is still
//               there, and is made once, by Lock, when it has gone; a request still queued 2 s after the unlock
//               ended is dropped with a warning, and a dry-run change clears the queue
//   timeout     with no lock to be had, the 2 s timeout lets the sleep go
//   monitor     the bus going away stops the monitor, which Idle notes and starts again after a pause
// The idle timers (IdleMonitor, Wayland) do not exist offscreen and are not checked. The script reads the log for
// what only the log shows; this file prints `lockqml: ...` lines and `lockqml: OK` when its expectations hold.
ShellRoot {
    id: shell

    // logind's object paths for the sessions, as sd_bus_path_encode makes them: "gutter-test" (XDG_SESSION_ID) has its
    // "-" as "_2d", "3" its digit as "_33".
    readonly property string ownSession: "/org/freedesktop/login1/session/gutter_2dtest"
    readonly property string otherSession: "/org/freedesktop/login1/session/_33"

    property var problems: []
    property int checks: 0
    // How often the dry-run preview came on since a step reset it.
    property int previewsOn: 0
    // The pid of the sleep helper (the `cat`) while it runs, "" otherwise (see the probe below).
    property string helperPid: ""
    property string firstHelperPid: ""
    property double sleepSentAt: 0
    // Idle.sleepTimeouts when a step began: "the lock released the sleep" is "the 2 s timeout did not fire".
    property int timeoutsBefore: 0
    property var queue: []
    property bool queuedBefore: false

    function expect(name, ok) {
        checks++;
        console.log("lockqml: idle: " + name + ": " + (ok ? "ok" : "FAIL"));
        if (!ok)
            problems.push(name);
    }

    function finish() {
        if (problems.length > 0)
            console.log("lockqml: FAIL (" + problems.join("; ") + ")");
        else
            console.log("lockqml: OK (idle, " + checks + " checks)");
        Qt.quit();
    }

    // Sends a line to the fake logind, one at a time and in order.
    function send(line) {
        queue.push(line);
        pump();
    }

    function pump() {
        if (sender.running || queue.length === 0)
            return;
        sender.command = ["sh", "-c", "printf '%s\\n' \"$1\" > \"$2\"", "sh", queue.shift(), Quickshell.env("LOCKQML_FIFO")];
        sender.running = true;
    }

    // The steps, run one after the other. `act` runs once; the step is done when `wait` is true (within `ms`, 1.5 s
    // unless said otherwise) or, with `hold`, after that many ms; then `after` checks. A step that does not finish
    // ends the run.
    readonly property var steps: [
        {
            name: "startup",
            ms: 5000,
            wait: () => Idle.holdWanted && Idle.sleepState.helper && shell.helperPid !== "",
            after: () => {
                shell.expect("startup: the logind monitor runs", Idle.holdWanted);
                shell.expect("startup: the sleep helper is held", Idle.sleepState.helper);
                shell.expect("startup: no sleep waits", !Idle.sleepState.waiting);
                shell.expect("startup: no lock yet", !Lock.preview);
                shell.expect("startup: the monitor has not stopped before", Idle.monitorBackoff === 1000);
                shell.firstHelperPid = shell.helperPid;
                shell.expect("startup: the sleep timeout has not fired", Idle.sleepTimeouts === 0);
            }
        },
        {
            name: "sleep: the lock lets the sleep go",
            act: () => {
                Idle.lastDryRun = "";
                shell.send("prepare true");
            },
            // The lock is up (the preview) at once, so the helper goes long before the 2 s timeout would let it.
            wait: () => Lock.preview && !Idle.sleepState.helper && !Idle.sleepState.waiting,
            after: () => {
                shell.expect("sleep: Idle asked for a lock", Idle.lastDryRun === "lock (dry run)");
                shell.expect("sleep: the lock request went through Lock", Lock.lastDryRun === "lock");
            }
        },
        {
            name: "sleep: the helper process ends",
            wait: () => shell.helperPid === ""
        },
        {
            name: "resume",
            act: () => {
                Idle.lastDryRun = "";
                shell.send("prepare false");
            },
            wait: () => Idle.sleepState.helper && shell.helperPid !== "" && Idle.lastDryRun === "dpms:on",
            after: () => {
                shell.expect("resume: the screens are on", !Idle.screensOff);
                shell.expect("resume: a new helper runs", shell.helperPid !== shell.firstHelperPid);
                shell.expect("resume: no sleep waits", !Idle.sleepState.waiting);
                shell.expect("resume: the lock stays up", Lock.preview);
            }
        },
        {
            name: "logind Lock of our session",
            act: () => {
                Lock.unlockDryRun();
                Lock.lastDryRun = "";
                Idle.lastDryRun = "";
                shell.send("lock " + shell.ownSession);
            },
            wait: () => Lock.preview,
            after: () => {
                shell.expect("Lock: our session's Lock locks", Idle.lastDryRun === "lock (dry run)");
                shell.expect("Lock: through Lock.request", Lock.lastDryRun === "lock");
            }
        },
        {
            // The sentinel (a resume, which turns the screens on) is read after the Unlock: when it has been, the
            // Unlock has been too.
            name: "logind Unlock of our session",
            act: () => {
                Idle.lastDryRun = "";
                shell.send("unlock " + shell.ownSession);
                shell.send("prepare false");
            },
            wait: () => Idle.lastDryRun === "dpms:on",
            after: () => shell.expect("Unlock: Idle never unlocks", Lock.preview)
        },
        {
            name: "logind Lock of another session",
            act: () => {
                Lock.unlockDryRun();
                Lock.lastDryRun = "";
                Idle.lastDryRun = "";
                shell.send("lock " + shell.otherSession);
                shell.send("prepare false");
            },
            wait: () => Idle.lastDryRun === "dpms:on",
            after: () => {
                shell.expect("Lock: another session's Lock does not lock", !Lock.preview);
                shell.expect("Lock: nor asks for a lock", Lock.lastDryRun === "");
            }
        },
        {
            // The lock is going away (not up: fade below 1) when the sleep comes, with no `Lock.unlocking` (that is the
            // "queue" steps below): Lock ignores the request, and it is Idle's own retry that asks again.
            name: "retry: a sleep while the lock goes away",
            act: () => {
                Lock.fade = 0.5;
                Lock.preview = true;
                Lock.lastDryRun = "";
                Idle.lastDryRun = "";
                shell.timeoutsBefore = Idle.sleepTimeouts;
                shell.send("prepare true");
            },
            wait: () => Idle.sleepState.waiting,
            after: () => {
                shell.expect("retry: the sleep waits", Idle.sleepState.waiting);
                shell.expect("retry: the helper is still held", Idle.sleepState.helper);
                shell.expect("retry: a fading lock is not up", !Idle.lockUp);
                shell.expect("retry: no request while the lock is still there", Idle.lastDryRun === "" && Lock.lastDryRun === "");
            }
        },
        {
            name: "retry: the lock goes, the request is made again",
            act: () => {
                shell.previewsOn = 0;
                Lock.preview = false;
            },
            wait: () => Lock.preview,
            after: () => {
                shell.expect("retry: asked for again", shell.previewsOn === 1 && Idle.lastDryRun === "lock (dry run)" && Lock.lastDryRun === "lock");
                shell.expect("retry: the lock is still going away, so the sleep still waits", Idle.sleepState.waiting && Idle.sleepState.helper);
            }
        },
        {
            // fade back at 1 is no change Idle hears; the next retry finds the lock up.
            name: "retry: the lock is up, the sleep goes",
            act: () => {
                Lock.fade = 1;
                shell.previewsOn = 0;
                Lock.preview = false;
            },
            wait: () => Lock.preview && !Idle.sleepState.waiting && !Idle.sleepState.helper,
            after: () => {
                shell.expect("retry: asked for again, once", shell.previewsOn === 1);
                shell.expect("retry: the lock, not the 2 s timeout, released the sleep", Idle.sleepTimeouts === shell.timeoutsBefore);
            }
        },
        {
            // No sleep waits, so a lock that goes is not asked for again.
            name: "retry: not without a sleep",
            act: () => {
                Lock.fade = 0.5;
                Idle.lastDryRun = "";
                shell.previewsOn = 0;
                Lock.preview = false;
            },
            hold: 600,
            after: () => {
                shell.expect("retry: no sleep waits", !Idle.sleepState.waiting);
                shell.expect("retry: the lock that went is not asked for", !Lock.preview && shell.previewsOn === 0 && Idle.lastDryRun === "");
                Lock.fade = 1;
            }
        },
        {
            name: "resume before the timeout test",
            act: () => shell.send("prepare false"),
            wait: () => Idle.sleepState.helper && shell.helperPid !== ""
        },
        {
            // The unlock is in progress (`Lock.unlocking`) when the sleep comes: Lock queues the request.
            name: "queue: a sleep during the unlock",
            act: () => {
                Lock.fade = 1;
                Lock.unlocking = true;
                Lock.preview = true;
                shell.previewsOn = 0;
                Lock.lastDryRun = "";
                Idle.lastDryRun = "";
                shell.timeoutsBefore = Idle.sleepTimeouts;
                shell.send("prepare true");
            },
            wait: () => Idle.sleepState.waiting,
            after: () => {
                shell.expect("queue: the sleep waits", Idle.sleepState.waiting && Idle.sleepState.helper);
                shell.expect("queue: an unlocking lock is not up, even at fade 1", !Idle.lockUp);
                shell.expect("queue: the request is queued", Lock.pendingRequest);
                shell.expect("queue: no request was made yet", Lock.lastDryRun === "" && shell.previewsOn === 0);
            }
        },
        {
            // The unlock ends while the lock is still there (`locked` follows the release a moment later): wait.
            name: "queue: the unlock ended, the lock is still there",
            act: () => {
                // LockScreen's order: the lock stops being secure, then `unlocking` clears; `locked` follows later.
                Lock.locked = true;
                Lock.preview = false;
                Lock.unlocking = false;
                Idle.lastDryRun = "";
            },
            hold: 300,
            after: () => {
                shell.expect("queue: still queued while the lock is there", Lock.pendingRequest);
                shell.expect("queue: the dying lock did not release the sleep", Idle.sleepState.waiting && Idle.sleepState.helper);
                shell.expect("queue: still no request", shell.previewsOn === 0 && Lock.lastDryRun === "");
            }
        },
        {
            name: "queue: the lock goes, the request is made once",
            act: () => {
                Lock.locked = false;
            },
            wait: () => Lock.preview && !Idle.sleepState.waiting && !Idle.sleepState.helper,
            after: () => {
                shell.expect("queue: made by Lock", Lock.lastDryRun === "lock" && !Lock.pendingRequest);
                shell.expect("queue: not by Idle's own retry", Idle.lastDryRun === "");
                shell.expect("queue: the lock, not the 2 s timeout, released the sleep", Idle.sleepTimeouts === shell.timeoutsBefore);
            }
        },
        {
            // Idle's own retry (100 ms) must find the lock back and not ask a second time.
            name: "queue: exactly one request",
            hold: 400,
            after: () => shell.expect("queue: one preview, not two", shell.previewsOn === 1 && Lock.preview)
        },
        {
            name: "queue: resume",
            act: () => shell.send("prepare false"),
            wait: () => Idle.sleepState.helper && shell.helperPid !== ""
        },
        {
            // No sleep: a request during an unlock whose lock never goes is dropped after 2 s, with its warning.
            name: "queue: the lock does not go",
            act: () => {
                shell.previewsOn = 0;
                Lock.unlocking = true;
                Lock.request();
                shell.sleepSentAt = Date.now();
                Lock.unlocking = false;
            },
            wait: () => !Lock.pendingRequest,
            ms: 3500,
            after: () => {
                shell.expect("queue: dropped only after 2 s", Date.now() - shell.sleepSentAt >= 1800);
                shell.expect("queue: dropped, not made", shell.previewsOn === 0 && Lock.preview);
            }
        },
        {
            name: "queue: a dry-run change clears the queue",
            act: () => {
                Lock.unlocking = true;
                Lock.request();
                shell.queuedBefore = Lock.pendingRequest;
                // The unlock ends first, so the drop timer runs when the dry-run change clears the queue; it must not
                // drop (and warn about) anything afterwards: the script counts that warning, once, from the step above.
                Lock.unlocking = false;
                Lock.setDryRun(true);
                Lock.preview = false;
            },
            hold: 2300,
            after: () => {
                shell.expect("queue: the request had been queued", shell.queuedBefore);
                shell.expect("queue: the dry-run change cleared it", !Lock.pendingRequest);
                shell.expect("queue: so it was never made", shell.previewsOn === 0 && !Lock.preview);
            }
        },
        {
            // A real (not dry-run) Lock that Idle's dry run will not ask: no lock comes up, and only the timeout
            // lets the sleep go.
            name: "timeout: no lock can be had",
            act: () => {
                Lock.setDryRun(false);
                shell.timeoutsBefore = Idle.sleepTimeouts;
                shell.sleepSentAt = Date.now();
                shell.send("prepare true");
            },
            wait: () => Idle.sleepState.waiting,
            after: () => shell.expect("timeout: the sleep waits for a lock", !Lock.preview && Idle.sleepState.helper)
        },
        {
            name: "timeout: the sleep is let go",
            wait: () => !Idle.sleepState.waiting && !Idle.sleepState.helper,
            ms: 3500,
            after: () => {
                shell.expect("timeout: only after the 2 s", Date.now() - shell.sleepSentAt >= 1900);
                shell.expect("timeout: the 2 s timeout fired", Idle.sleepTimeouts === shell.timeoutsBefore + 1);
                shell.expect("timeout: there was no lock", !Lock.preview && !Lock.locked);
            }
        },
        {
            name: "timeout: the resume",
            act: () => {
                Lock.setDryRun(true);
                shell.send("prepare false");
            },
            wait: () => Idle.sleepState.helper && shell.helperPid !== ""
        },
        {
            // Killing the bus ends `gdbus monitor` (it stays when only the name goes away).
            name: "monitor: the bus goes away",
            act: () => killBus.running = true,
            wait: () => !Idle.holdWanted && Idle.monitorBackoff === 2000 && shell.helperPid === "",
            ms: 3000,
            after: () => {
                shell.expect("monitor: the hold on sleep is dropped", !Idle.sleepState.helper && !Idle.sleepState.waiting);
            }
        }
    ]
    property int stepIndex: 0
    property bool stepActed: false
    property double stepStartedAt: 0

    function tick() {
        if (stepIndex >= steps.length)
            return;
        const step = steps[stepIndex];
        if (!stepActed) {
            stepActed = true;
            stepStartedAt = Date.now();
            if (step.act)
                step.act();
        }
        const elapsed = Date.now() - stepStartedAt;
        if (step.hold !== undefined) {
            if (elapsed < step.hold)
                return;
        } else if (step.wait && !step.wait()) {
            if (elapsed > (step.ms ?? 1500)) {
                expect(step.name + " (timed out)", false);
                stepIndex = steps.length;
                finish();
            }
            return;
        }
        if (step.after)
            step.after();
        stepActed = false;
        stepIndex++;
        if (stepIndex >= steps.length)
            finish();
    }

    Connections {
        target: Lock

        function onPreviewChanged() {
            if (Lock.preview)
                shell.previewsOn++;
        }
    }

    Process {
        id: sender

        onRunningChanged: {
            if (!running)
                shell.pump();
        }
    }

    // Kills the private bus: the script writes its pid and start time to a file, and the bus is killed only while that
    // pid still has that start time (field 22 of /proc/<pid>/stat), so never another process that got the pid.
    Process {
        id: killBus

        command: ["sh", "-c", "read pid st < \"$1\" && read -r s < \"/proc/$pid/stat\" && s=\"${s##*) }\" && set -- $s && shift 19 && [ \"$1\" = \"$st\" ] && kill \"$pid\"", "sh", Quickshell.env("LOCKQML_BUS_PID")]
    }

    // Looks for the sleep helper: the script's `cat` stand-in writes its pid to a file, and the helper runs while
    // that process does.
    Process {
        id: probe

        command: ["sh", "-c", "read pid < \"$1\" && kill -0 \"$pid\" && echo \"$pid\"", "sh", Quickshell.env("LOCKQML_HELPER_PID")]
        stdout: StdioCollector {
            onStreamFinished: shell.helperPid = text.trim()
        }
        stderr: StdioCollector {}
    }

    Timer {
        interval: 40
        repeat: true
        running: true
        onTriggered: {
            if (!probe.running)
                probe.running = true;
        }
    }

    Timer {
        id: runner

        interval: 20
        repeat: true
        running: true
        onTriggered: shell.tick()
    }

    // A run that never ends fails loudly rather than hanging.
    Timer {
        interval: 30000
        running: true
        onTriggered: {
            console.log("lockqml: FAIL (idle timed out at step " + shell.stepIndex + ")");
            Qt.quit();
        }
    }
}
