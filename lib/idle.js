.pragma library

// How long a sleep waits for the lock screen to cover the outputs before it lets the machine go, in ms.
var SLEEP_LOCK_TIMEOUT_MS = 2000;

// The command that prints logind's signals as text, one per line. (`busctl monitor` would need root: the bus refuses
// BecomeMonitor to a user.) A line looks like
//   /org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)
//   /org/freedesktop/login1/session/_33: org.freedesktop.login1.Session.Lock ()
function monitorCommand() {
    return ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"];
}

// The command that holds a delay lock on sleep for as long as it runs, so logind waits for us before it sleeps.
// `cat` waits for its stdin to close: the caller keeps a pipe to it open, so the lock goes with the caller if that
// dies without stopping it.
function inhibitCommand() {
    return ["systemd-inhibit", "--what=sleep", "--mode=delay", "--who=Gutter", "--why=Lock before sleep", "cat"];
}

// The object path logind gives a session. It builds it with sd_bus_path_encode: a letter stays as it is, a digit
// too unless it comes first, and any other character becomes "_" and two lowercase hex digits. So session "3" is
// at ".../session/_33" and "c2" at ".../session/c2".
function sessionPath(id) {
    var out = String(id).replace(/[^A-Za-z0-9]|^[0-9]/g, function (c) {
        return "_" + ("0" + c.charCodeAt(0).toString(16)).slice(-2);
    });
    return "/org/freedesktop/login1/session/" + out;
}

// What a line of the logind monitor (see monitorCommand) means for us: "sleep" and "resume" (PrepareForSleep true and
// false), and "lock" and "unlock" (the Lock and Unlock signals of our own session, `sessionId` being e.g. "3").
// Anything else, including another session's signals and lines that are not signals, gives null.
function logindEvent(line, sessionId) {
    var m = /^(\/\S*): org\.freedesktop\.login1\.(Manager\.PrepareForSleep|Session\.Lock|Session\.Unlock) \((.*)\)\s*$/.exec(String(line));
    if (!m)
        return null;
    switch (m[2]) {
    case "Manager.PrepareForSleep":
        if (m[1] !== "/org/freedesktop/login1")
            return null;
        if (/^true,?$/.test(m[3].trim()))
            return "sleep";
        if (/^false,?$/.test(m[3].trim()))
            return "resume";
        return null;
    case "Session.Lock":
    case "Session.Unlock":
        if (m[1] !== sessionPath(sessionId))
            return null;
        return m[2] === "Session.Lock" ? "lock" : "unlock";
    }
    return null;
}

// Whether something keeps the screen from going idle: audio playing, when the setting says it should.
function inhibited(audioPlaying, inhibitWhenAudio) {
    return !!audioPlaying && !!inhibitWhenAudio;
}

// Whether an idle timer of `seconds` runs: it is off at 0 and while something inhibits idling.
function timerOn(seconds, inhibited) {
    return seconds > 0 && !inhibited;
}

// One step of locking before sleep. `state` is whether our delay lock is held (`helper`) and whether we wait for the
// lock screen to cover the outputs (`waiting`); `event` is "sleep" or "resume" from logind, "locked" when the lock
// screen is up, or "timeout" when it took too long; `ctx` says whether locking on sleep is on and whether the
// session is already locked. Returns the new state and what to do: "lock" the session, "release" the delay lock
// (the machine may sleep) or "take" it again (after waking up).
function sleepStep(state, event, ctx) {
    var next = { helper: !!state.helper, waiting: !!state.waiting };
    var actions = [];
    switch (event) {
    case "sleep":
        if (!ctx.enabled) {
            if (next.helper)
                actions.push("release");
            next = { helper: false, waiting: false };
        } else if (ctx.locked) {
            if (next.helper)
                actions.push("release");
            next = { helper: false, waiting: false };
        } else {
            actions.push("lock");
            next.waiting = true;
        }
        break;
    case "locked":
    case "timeout":
        if (next.waiting) {
            if (next.helper)
                actions.push("release");
            next = { helper: false, waiting: false };
        }
        break;
    case "resume":
        next.waiting = false;
        if (ctx.enabled && !next.helper) {
            actions.push("take");
            next.helper = true;
        }
        break;
    }
    return { state: next, actions: actions };
}

// The command that turns the outputs on or off.
function dpmsCommand(on) {
    return ["hyprctl", "dispatch", "hl.dsp.dpms({ action = \"" + (on ? "enable" : "disable") + "\" })"];
}

// Whether the lock is up for a sleep: the compositor has confirmed it (`secure`; a lock that was only asked for
// does not count) or, in Idle's dry run (`dryRun`), the preview is on; and the unlock has not begun (`unlocking`,
// which is set a moment before `fade` moves: the lock is then about to go). Outside the dry run a preview is not a
// lock: it covers nothing the compositor knows about.
function lockUp(secure, preview, fade, unlocking, dryRun) {
    return (!!secure || (!!dryRun && !!preview)) && fade >= 1 && !unlocking;
}

// What a change in the lock's state (`lock` is {secure, preview, locked, fade, unlocking, dryRun}) means for a sleep:
// "locked" when the lock is up (see lockUp), "retry" when a sleep still waits (`waiting`) and nothing is held,
// confirmed or showing, so the request was dropped or the lock failed and has to be asked for again, otherwise null
// (a lock that is only pending, or one that is being unlocked, changes nothing yet: the next change decides).
function lockEdge(lock, waiting) {
    if (lockUp(lock.secure, lock.preview, lock.fade, lock.unlocking, lock.dryRun))
        return "locked";
    if (waiting && !lock.locked && !lock.secure && !lock.preview)
        return "retry";
    return null;
}
