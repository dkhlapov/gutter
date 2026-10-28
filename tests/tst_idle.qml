import QtQuick
import QtTest
import "../lib/idle.js" as Idle

TestCase {
    name: "Idle"

    // Lines as `gdbus monitor --system --dest org.freedesktop.login1` prints logind's signals. Session "3" lives at
    // /org/freedesktop/login1/session/_33: logind escapes the id with sd_bus_path_encode.
    readonly property string sleepLine: "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)"
    readonly property string resumeLine: "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)"
    readonly property string lockLine: "/org/freedesktop/login1/session/_33: org.freedesktop.login1.Session.Lock ()"
    readonly property string unlockLine: "/org/freedesktop/login1/session/_33: org.freedesktop.login1.Session.Unlock ()"
    readonly property string lockLine4: lockLine.replace("_33", "_34")
    readonly property string unlockLine4: unlockLine.replace("_33", "_34")

    function test_logindEvent() {
        compare(Idle.logindEvent(sleepLine, "3"), "sleep");
        compare(Idle.logindEvent(resumeLine, "3"), "resume");
        compare(Idle.logindEvent(lockLine, "3"), "lock");
        compare(Idle.logindEvent(unlockLine, "3"), "unlock");
        // Another session's Lock and Unlock are not ours.
        compare(Idle.logindEvent(lockLine4, "3"), null);
        compare(Idle.logindEvent(unlockLine4, "3"), null);
        compare(Idle.logindEvent(lockLine4, "4"), "lock");
        // Session 3 is not session 30: _33 against _330.
        compare(Idle.logindEvent(lockLine.replace("_33", "_330"), "3"), null);
        // Noise: the header lines gdbus prints, text that is not a signal, other signals, odd arguments.
        compare(Idle.logindEvent("Monitoring signals from all objects owned by org.freedesktop.login1", "3"), null);
        compare(Idle.logindEvent("The name org.freedesktop.login1 is owned by :1.7", "3"), null);
        compare(Idle.logindEvent("not a signal", "3"), null);
        compare(Idle.logindEvent("", "3"), null);
        compare(Idle.logindEvent(sleepLine.replace("PrepareForSleep", "PrepareForShutdown"), "3"), null);
        compare(Idle.logindEvent(sleepLine.replace("(true,)", "()"), "3"), null);
        compare(Idle.logindEvent(sleepLine.replace("(true,)", "(1,)"), "3"), null);
        // PrepareForSleep comes from the manager object only; Lock and Unlock from the session's.
        compare(Idle.logindEvent(sleepLine.replace("login1:", "login1/session/_33:"), "3"), null);
        compare(Idle.logindEvent(lockLine.replace("Session.Lock", "Manager.Lock"), "3"), null);
        compare(Idle.logindEvent("/org/freedesktop/login1: org.freedesktop.login1.Manager.SessionNew ('3', objectpath '/org/freedesktop/login1/session/_33')", "3"), null);
        // A missing session id never matches a session.
        compare(Idle.logindEvent(lockLine, ""), null);
    }
    function test_sessionPath() {
        compare(Idle.sessionPath("3"), "/org/freedesktop/login1/session/_33");
        compare(Idle.sessionPath("30"), "/org/freedesktop/login1/session/_330");
        compare(Idle.sessionPath("c2"), "/org/freedesktop/login1/session/c2");
        compare(Idle.sessionPath("c12"), "/org/freedesktop/login1/session/c12");
        compare(Idle.sessionPath("a-b"), "/org/freedesktop/login1/session/a_2db");
        compare(Idle.sessionPath(3), "/org/freedesktop/login1/session/_33");
    }
    function test_timerOn_and_inhibited() {
        compare(Idle.timerOn(180, false), true);
        compare(Idle.timerOn(0, false), false);
        compare(Idle.timerOn(180, true), false);
        compare(Idle.inhibited(true, true), true);
        compare(Idle.inhibited(true, false), false);
        compare(Idle.inhibited(false, true), false);
    }
    function test_sleepStep_sleep_locks_then_releases() {
        var r = Idle.sleepStep({ helper: true, waiting: false }, "sleep", { enabled: true, locked: false });
        compare(r.actions, ["lock"]);
        compare(r.state, { helper: true, waiting: true });
        r = Idle.sleepStep(r.state, "locked", { enabled: true, locked: true });
        compare(r.actions, ["release"]);
        compare(r.state, { helper: false, waiting: false });
        r = Idle.sleepStep(r.state, "resume", { enabled: true, locked: true });
        compare(r.actions, ["take"]);
        compare(r.state, { helper: true, waiting: false });
    }
    function test_sleepStep_timeout_releases() {
        var r = Idle.sleepStep({ helper: true, waiting: true }, "timeout", { enabled: true, locked: false });
        compare(r.actions, ["release"]);
        compare(r.state, { helper: false, waiting: false });
        r = Idle.sleepStep({ helper: true, waiting: false }, "timeout", { enabled: true, locked: false });
        compare(r.actions, []);
        compare(r.state, { helper: true, waiting: false });
        r = Idle.sleepStep({ helper: true, waiting: false }, "locked", { enabled: true, locked: true });
        compare(r.actions, []);
        compare(r.state, { helper: true, waiting: false });
    }
    function test_sleepStep_already_locked() {
        var r = Idle.sleepStep({ helper: true, waiting: false }, "sleep", { enabled: true, locked: true });
        compare(r.actions, ["release"]);
        compare(r.state, { helper: false, waiting: false });
        // Disabled: let the machine sleep at once, and never lock.
        r = Idle.sleepStep({ helper: true, waiting: false }, "sleep", { enabled: false, locked: false });
        compare(r.actions, ["release"]);
        compare(r.state, { helper: false, waiting: false });
        r = Idle.sleepStep({ helper: false, waiting: false }, "sleep", { enabled: false, locked: false });
        compare(r.actions, []);
        compare(r.state, { helper: false, waiting: false });
    }
    function test_sleepStep_resume_without_sleep() {
        var r = Idle.sleepStep({ helper: true, waiting: false }, "resume", { enabled: true, locked: false });
        compare(r.actions, []);
        compare(r.state, { helper: true, waiting: false });
        r = Idle.sleepStep({ helper: false, waiting: false }, "resume", { enabled: false, locked: false });
        compare(r.actions, []);
        compare(r.state, { helper: false, waiting: false });
    }
    function test_sleepStep_resume_while_waiting() {
        // The lock never completed and logind's delay ran out: the machine slept and woke with us still waiting.
        var r = Idle.sleepStep({ helper: true, waiting: true }, "resume", { enabled: true, locked: false });
        compare(r.actions, []);
        compare(r.state, { helper: true, waiting: false });
        // A late timeout from that wait changes nothing.
        r = Idle.sleepStep(r.state, "timeout", { enabled: true, locked: false });
        compare(r.actions, []);
        compare(r.state, { helper: true, waiting: false });
    }
    function test_sleepStep_sleep_while_waiting() {
        // Current behaviour: a second sleep asks for the lock again and keeps waiting (locking twice is harmless).
        var r = Idle.sleepStep({ helper: true, waiting: true }, "sleep", { enabled: true, locked: false });
        compare(r.actions, ["lock"]);
        compare(r.state, { helper: true, waiting: true });
    }
    function test_sleepStep_release_needs_the_helper() {
        // Without the delay lock there is nothing to release, but the wait still ends.
        var r = Idle.sleepStep({ helper: false, waiting: true }, "locked", { enabled: true, locked: true });
        compare(r.actions, []);
        compare(r.state, { helper: false, waiting: false });
        r = Idle.sleepStep({ helper: false, waiting: true }, "timeout", { enabled: true, locked: false });
        compare(r.actions, []);
        compare(r.state, { helper: false, waiting: false });
        r = Idle.sleepStep({ helper: false, waiting: false }, "sleep", { enabled: true, locked: true });
        compare(r.actions, []);
        compare(r.state, { helper: false, waiting: false });
    }
    function test_sleepStep_does_not_change_its_input() {
        var state = { helper: true, waiting: false };
        Idle.sleepStep(state, "sleep", { enabled: true, locked: false });
        compare(state, { helper: true, waiting: false });
    }
    function test_lockUp() {
        // Asked for but not confirmed does not count: only `secure` (or the preview in Idle's dry run) does.
        compare(Idle.lockUp(true, false, 1, false, false), true);
        compare(Idle.lockUp(false, false, 1, false, false), false);
        compare(Idle.lockUp(false, true, 1, false, true), true);
        compare(Idle.lockUp(true, true, 1, false, true), true);
        // A preview outside the dry run is not a lock.
        compare(Idle.lockUp(false, true, 1, false, false), false);
        compare(Idle.lockUp(true, true, 1, false, false), true);
        // The unlock fade has begun: the lock is about to go.
        compare(Idle.lockUp(true, false, 0.5, false, false), false);
        compare(Idle.lockUp(false, true, 0.99, false, true), false);
        // The unlock has begun but the fade has not moved yet (fade is still 1): also not up.
        compare(Idle.lockUp(true, false, 1, true, false), false);
        compare(Idle.lockUp(false, true, 1, true, true), false);
    }
    function lockState(over) {
        var s = { secure: false, preview: false, locked: false, fade: 1, unlocking: false, dryRun: false };
        for (var k in over)
            s[k] = over[k];
        return s;
    }
    function test_lockEdge() {
        compare(Idle.lockEdge(lockState({ secure: true, locked: true }), true), "locked");
        compare(Idle.lockEdge(lockState({ preview: true, dryRun: true }), true), "locked");
        compare(Idle.lockEdge(lockState({ secure: true, locked: true }), false), "locked");
        // A preview outside Idle's dry run is showing, so nothing is gone, but it is not a lock that is up either.
        compare(Idle.lockEdge(lockState({ preview: true }), true), null);
        // Pending (asked for, not yet confirmed): nothing changes.
        compare(Idle.lockEdge(lockState({ locked: true }), true), null);
        // Being unlocked (the fade runs, or `locked` went before `secure` did): not up, and not yet gone.
        compare(Idle.lockEdge(lockState({ secure: true, locked: true, fade: 0.4, unlocking: true }), true), null);
        compare(Idle.lockEdge(lockState({ secure: true, locked: false, fade: 0, unlocking: true }), true), null);
        // The unlock has begun and the fade has not moved yet.
        compare(Idle.lockEdge(lockState({ secure: true, locked: true, unlocking: true }), true), null);
        compare(Idle.lockEdge(lockState({ preview: true, dryRun: true, unlocking: true }), true), null);
        // Gone while a sleep waits (a dropped request, a lock that failed at once, the unlock finished): ask again.
        compare(Idle.lockEdge(lockState({}), true), "retry");
        compare(Idle.lockEdge(lockState({}), false), null);
    }
    function test_commands() {
        verify(Idle.dpmsCommand(false)[2].indexOf("disable") >= 0);
        verify(Idle.dpmsCommand(true)[2].indexOf("enable") >= 0);
        verify(Idle.dpmsCommand(true)[2].indexOf("disable") < 0);
        compare(Idle.dpmsCommand(true)[0], "hyprctl");
        compare(Idle.inhibitCommand()[0], "systemd-inhibit");
        verify(Idle.inhibitCommand().indexOf("--mode=delay") >= 0);
        verify(Idle.inhibitCommand().indexOf("--what=sleep") >= 0);
        compare(Idle.inhibitCommand().slice(-1), ["cat"]);
        compare(Idle.monitorCommand(), ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]);
        compare(Idle.SLEEP_LOCK_TIMEOUT_MS, 2000);
    }
}
