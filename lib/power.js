.pragma library

// The power menu's entries, top to bottom. `can` names the logind method that says whether the action is
// possible; `confirm` asks again before an action that ends the session. Glyphs are Material Design Icons.
var ENTRIES = [
    { id: "lock", label: "Lock", icon: "\u{f033e}", confirm: false }, // md-lock
    { id: "logout", label: "Log out", icon: "\u{f0343}", confirm: true }, // md-logout
    { id: "suspend", label: "Suspend", icon: "\u{f04b2}", confirm: false, can: "CanSuspend" }, // md-sleep
    { id: "hibernate", label: "Hibernate", icon: "\u{f0717}", confirm: false, can: "CanHibernate", needsYes: true }, // md-snowflake
    { id: "reboot", label: "Restart", icon: "\u{f0709}", confirm: true, can: "CanReboot" }, // md-restart
    { id: "poweroff", label: "Power off", icon: "\u{f0425}", confirm: true, can: "CanPowerOff" } // md-power
];

// logind answers "yes", "challenge" (allowed after asking for authentication), "no" or "na".
function possible(answer) {
    return answer === "yes" || answer === "challenge";
}

// The command that asks logind about every method, printing one `<Method> s "<answer>"` line each.
function canQuery() {
    var methods = ENTRIES.filter(function (e) { return e.can; }).map(function (e) { return e.can; });
    return ["sh", "-c", "for m in " + methods.join(" ") + "; do printf '%s ' \"$m\"; busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager \"$m\"; done"];
}

// { CanSuspend: "yes", ... } from canQuery's output; lines it cannot read are skipped.
function parseCan(text) {
    var out = {};
    String(text).split("\n").forEach(function (line) {
        var m = /^(Can\w+) s "(\w+)"$/.exec(line.trim());
        if (m)
            out[m[1]] = m[2];
    });
    return out;
}

// The entries to show. An action logind says is impossible is left out; one it has not answered about yet is
// shown, except hibernate, which needs swap set up for it and so shows only once logind says it works.
function entries(can) {
    return ENTRIES.filter(function (e) {
        if (!e.can)
            return true;
        var answer = can[e.can];
        return answer === undefined ? !e.needsYes : possible(answer);
    });
}

// What runs for an entry. Lock is not a command: Power.run hands it to Lock.request() (Gutter's lock screen). Log out ends this login
// session (`sessionId`, from XDG_SESSION_ID), or every session of the user when that is unknown.
function command(id, sessionId) {
    switch (id) {
    case "lock":
        return [];
    case "logout":
        return sessionId ? ["loginctl", "terminate-session", sessionId] : ["loginctl", "terminate-user", ""];
    case "suspend":
    case "hibernate":
    case "reboot":
    case "poweroff":
        return ["systemctl", id];
    }
    return [];
}

// What Power.run does for an entry, as { act, command, log } with `act` one of "lock" (ask Lock.request()), "exec"
// (run `command`), "log" (a dry run: only print `log`, and note the action) or "none" (not an entry). The lock is
// Gutter's own and has no command; in a dry run it only logs, so the menu can be tried without locking. Every dry-run
// line is `gutter: power (dry run): <id>`, with the command after it where there is one.
function route(id, dryRun, sessionId) {
    const prefix = "gutter: power (dry run): " + id;
    if (id === "lock")
        return dryRun ? { act: "log", command: [], log: prefix } : { act: "lock", command: [], log: "" };
    const cmd = command(id, sessionId);
    if (cmd.length === 0)
        return { act: "none", command: [], log: "" };
    return dryRun ? { act: "log", command: cmd, log: prefix + " " + JSON.stringify(cmd) } : { act: "exec", command: cmd, log: "" };
}

// What choosing an entry does, given the id still waiting for its confirmation ("" for none). An entry that ends
// the session asks first: the first choice only starts waiting; choosing the waiting one, or any entry that needs
// no confirmation, runs it. `confirming` is what to wait on afterwards.
function choose(entry, confirming) {
    if (entry.confirm && confirming !== entry.id)
        return { run: false, confirming: entry.id };
    return { run: true, confirming: "" };
}
