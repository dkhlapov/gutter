//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import qs.services

// The launcher service check (scripts/launcher.sh), on the real services/Launcher.qml in dry run, which a Quickshell
// Singleton cannot be in tests/tst_*.qml. `move`, `complete`, `activate` and `choose` do nothing on the session
// screen, `move` wraps and does nothing without rows, `complete` and `activate` do nothing for a selection outside the
// rows, `activate` runs only a command that is ready and asks twice for one that ends the session, `choose` runs no
// command that needs an argument, and a new query or mode starts the selection over. The rows are slash commands (a
// query starting with "/"), so what the machine has installed does not matter, except for one check of an app row.
ShellRoot {
    id: shell

    property var failures: []
    property int checks: 0

    function expect(ok, what) {
        checks++;
        if (!ok)
            failures.push(what);
    }

    // A group of checks; an exception in one (a guard that is gone lets the code run on into undefined) is a failure
    // of that group, not the end of the run.
    function group(name, body) {
        try {
            body();
        } catch (e) {
            checks++;
            failures.push(name + ": threw " + e);
        }
    }

    // A clean start: the launcher mode, nothing typed, nothing selected or waiting, no action recorded.
    function reset() {
        Launcher.mode = "launcher";
        Launcher.query = "";
        Launcher.selected = 0;
        Launcher.confirming = "";
        Launcher.lastDryRun = "";
    }

    // A check that could not run on this machine, said so rather than left out.
    function skip(what, why) {
        console.log("launcher: skip: " + what + ", " + why);
    }

    // The first row of a two-letter query of an installed app's name, which is an app row whose name is more than what
    // was typed; null (and a skip) when there is none.
    function appRow(what) {
        const app = Launcher.apps.find(a => a.name.length > 2 && a.command.length > 0);
        if (!app) {
            skip(what, "no installed app");
            return null;
        }
        reset();
        Launcher.query = app.name.slice(0, 2);
        const row = Launcher.results[0];
        if (!row || row.kind !== "app" || row.app.name === Launcher.query || row.app.command.length === 0) {
            skip(what, "the first row for '" + Launcher.query + "' is not a usable app row");
            return null;
        }
        return row;
    }

    // Types `query` and selects the row with `key` (the command's name, or an app's id).
    function type(query, key) {
        reset();
        Launcher.query = query;
        const at = Launcher.results.findIndex(r => r.key === key);
        expect(at >= 0, "no row " + key + " for '" + query + "'");
        Launcher.selected = Math.max(at, 0);
    }

    function moves() {
        group("move", () => {
            reset();
            Launcher.mode = "session";
            Launcher.query = "/";
            Launcher.selected = 1;
            Launcher.move(1);
            expect(Launcher.selected === 1, "move: the session screen moves the selection");

            reset();
            Launcher.query = "/qqqzzz";
            Launcher.selected = 3;
            expect(Launcher.results.length === 0, "move: '/qqqzzz' has rows");
            Launcher.move(1);
            Launcher.move(-1);
            expect(Launcher.selected === 3, "move: no rows, yet the selection moved");

            reset();
            Launcher.query = "/";
            const n = Launcher.results.length;
            expect(n > 2, "move: '/' lists only " + n + " rows");
            Launcher.move(1);
            expect(Launcher.selected === 1, "move: 1 from the first row does not go to the second");
            Launcher.move(-1);
            Launcher.move(-1);
            expect(Launcher.selected === n - 1, "move: -1 from the first row does not wrap to the last");
            Launcher.move(1);
            expect(Launcher.selected === 0, "move: 1 from the last row does not wrap to the first");
            Launcher.move(n + 1);
            expect(Launcher.selected === 1, "move: n + 1 is not one row on");
            Launcher.move(-(2 * n + 2));
            expect(Launcher.selected === n - 1, "move: -(2n + 2) from the second row is not the last");
        });
    }

    function completes() {
        group("complete", () => {
            reset();
            Launcher.mode = "session";
            Launcher.query = "/lo";
            Launcher.selected = 0;
            Launcher.complete();
            expect(Launcher.query === "/lo", "complete: the session screen fills in the query");

            // Before the first row, on the row past the last, and further on.
            for (const past of [-1, 0, 50]) {
                type("/lo", "lock");
                const out = past < 0 ? past : Launcher.results.length + past;
                Launcher.selected = out;
                Launcher.complete();
                expect(Launcher.query === "/lo", "complete: a selection of " + out + " changes the query");
            }

            type("/lo", "lock");
            Launcher.complete();
            expect(Launcher.query === "/lock", "complete: '/lo' on lock gives '" + Launcher.query + "', not '/lock'");

            type("/timer 10", "timer");
            Launcher.complete();
            expect(Launcher.query === "/timer 10", "complete: '/timer 10' gives '" + Launcher.query + "'");

            type("/tim", "timer");
            Launcher.complete();
            expect(Launcher.query === "/timer ", "complete: '/tim' gives '" + Launcher.query + "', not '/timer '");

            // An app row fills in the app's name.
            const row = appRow("complete: an app row");
            if (row) {
                Launcher.complete();
                expect(Launcher.query === row.app.name, "complete: an app row gives '" + Launcher.query + "', not '" + row.app.name + "'");
            }
        });
    }

    function activates() {
        group("activate", () => {
            reset();
            Launcher.mode = "session";
            Launcher.query = "/mute";
            Launcher.selected = 0;
            Launcher.activate();
            expect(Launcher.lastDryRun === "", "activate: the session screen ran '" + Launcher.lastDryRun + "'");

            for (const past of [-1, 0, 50]) {
                type("/mute", "mute");
                const out = past < 0 ? past : Launcher.results.length + past;
                Launcher.selected = out;
                Launcher.activate();
                expect(Launcher.lastDryRun === "", "activate: a selection of " + out + " ran '" + Launcher.lastDryRun + "'");
            }

            for (const q of ["/timer", "/tim", "/timer abc", "/timer 0"]) {
                type(q, "timer");
                Launcher.activate();
                expect(Launcher.lastDryRun === "", "activate: '" + q + "' is not ready, yet it ran '" + Launcher.lastDryRun + "'");
            }

            for (const [q, key, ran] of [["/mute", "mute", "mute"], ["/lock", "lock", "power:lock"], ["/timer 5", "timer", "timer:5"]]) {
                type(q, key);
                Launcher.activate();
                expect(Launcher.lastDryRun === ran, "activate: '" + q + "' ran '" + Launcher.lastDryRun + "', not '" + ran + "'");
            }

            type("/logout", "logout");
            Launcher.activate();
            expect(Launcher.confirming === "logout" && Launcher.lastDryRun === "", "activate: the first activation of logout waits on '" + Launcher.confirming + "' and ran '" + Launcher.lastDryRun + "'");
            Launcher.activate();
            expect(Launcher.lastDryRun === "power:logout" && Launcher.confirming === "", "activate: the second activation of logout ran '" + Launcher.lastDryRun + "' and waits on '" + Launcher.confirming + "'");

            // Another command that asks twice does not take the first one's confirmation.
            const other = Launcher.commands.find(c => c.confirm && c.name !== "logout");
            if (other) {
                // Typing the other command drops a wait, so logout's is set after (choose() below does it as it
                // happens).
                type("/" + other.name, other.name);
                Launcher.confirming = "logout";
                Launcher.activate();
                expect(Launcher.lastDryRun === "" && Launcher.confirming === other.name, "activate: " + other.name + " ran '" + Launcher.lastDryRun + "' on the confirmation of logout, and waits on '" + Launcher.confirming + "'");
            } else {
                skip("activate: a second command that asks twice", "logind allows only logout, or has not answered");
            }

            // An app row launches the app, and a dry run leaves the history alone.
            const row = appRow("activate: an app row");
            if (row) {
                Launcher.activate();
                expect(Launcher.lastDryRun.startsWith("app:"), "activate: an app row ran '" + Launcher.lastDryRun + "'");
                expect(JSON.stringify(Launcher.usage) === "{}", "activate: a dry run launch changed the history to " + JSON.stringify(Launcher.usage));
            }
        });
    }

    function chooses() {
        group("choose", () => {
            const other = Launcher.commands.find(c => c.confirm && c.name !== "logout");
            reset();
            Launcher.choose("nonesuch");
            expect(Launcher.lastDryRun === "", "choose: an unknown name ran '" + Launcher.lastDryRun + "'");

            Launcher.choose("timer");
            expect(Launcher.lastDryRun === "", "choose: timer, which needs minutes, ran '" + Launcher.lastDryRun + "'");

            Launcher.choose("lock");
            expect(Launcher.lastDryRun === "power:lock", "choose: lock ran '" + Launcher.lastDryRun + "'");

            reset();
            Launcher.choose("logout");
            expect(Launcher.confirming === "logout" && Launcher.lastDryRun === "", "choose: the first choice of logout waits on '" + Launcher.confirming + "' and ran '" + Launcher.lastDryRun + "'");
            Launcher.choose("logout");
            expect(Launcher.lastDryRun === "power:logout" && Launcher.confirming === "", "choose: the second choice of logout ran '" + Launcher.lastDryRun + "'");

            reset();
            Launcher.choose("logout");
            if (other) {
                Launcher.choose(other.name);
                expect(Launcher.lastDryRun === "" && Launcher.confirming === other.name, "choose: " + other.name + " ran '" + Launcher.lastDryRun + "' on the confirmation of logout, and waits on '" + Launcher.confirming + "'");
            } else {
                skip("choose: a second command that asks twice", "logind allows only logout, or has not answered");
            }

            reset();
            Launcher.query = "/x";
            Launcher.choose("session");
            expect(Launcher.mode === "session" && Launcher.query === "", "choose: session leaves mode '" + Launcher.mode + "' and query '" + Launcher.query + "'");
            expect(Launcher.lastDryRun === "", "choose: session ran '" + Launcher.lastDryRun + "'");
        });
    }

    function resets() {
        group("reset", () => {
            reset();
            Launcher.selected = 2;
            Launcher.confirming = "logout";
            Launcher.query = "/a";
            expect(Launcher.selected === 0 && Launcher.confirming === "", "reset: a new query leaves selected " + Launcher.selected + " and confirming '" + Launcher.confirming + "'");

            Launcher.selected = 2;
            Launcher.confirming = "logout";
            Launcher.mode = "session";
            expect(Launcher.selected === 0 && Launcher.confirming === "", "reset: a new mode leaves selected " + Launcher.selected + " and confirming '" + Launcher.confirming + "'");
        });
    }

    // The installed apps load a moment after start, and logind's answer (which commands Power offers) a moment after
    // that; without them after two seconds, the checks that need them are skipped.
    Timer {
        property int ticks: 0

        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (++ticks < 20 && (Launcher.apps.length === 0 || Object.keys(Power.can).length === 0))
                return;
            running = false;
            // Everything below changes the launcher's state and runs commands; only a dry run may.
            if (!Launcher.dryRun) {
                console.log("launcher: FAIL: not a dry run, nothing was checked");
                Qt.quit();
                return;
            }
            shell.moves();
            shell.completes();
            shell.activates();
            shell.chooses();
            shell.resets();
            if (shell.failures.length) {
                for (const f of shell.failures)
                    console.log("launcher: FAIL: " + f);
                console.log("launcher: FAIL");
            } else {
                console.log("launcher: OK (" + shell.checks + " checks)");
            }
            Qt.quit();
        }
    }
}
