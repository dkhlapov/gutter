import QtQuick
import QtTest
import "../lib/commands.js" as C

TestCase {
    name: "Commands"

    readonly property var power: [
        { id: "lock", label: "Lock", icon: "\u{f033e}", confirm: false },
        { id: "logout", label: "Log out", icon: "\u{f0343}", confirm: true },
        { id: "suspend", label: "Suspend", icon: "\u{f04b2}", confirm: false },
        { id: "reboot", label: "Restart", icon: "\u{f0709}", confirm: true },
        { id: "poweroff", label: "Power off", icon: "\u{f0425}", confirm: true }
    ]
    readonly property var sections: ["overview", "music", "calendar"]

    function names(list) {
        return list.map(c => c.name).join(",");
    }
    function matchNames(cmds, text) {
        return C.match(cmds, text).map(m => m.command.name);
    }
    function byName(cmds, name) {
        return cmds.filter(c => c.name === name)[0];
    }

    function test_list_order() {
        const cmds = C.list(sections, power);
        compare(names(cmds), "lock,logout,suspend,reboot,poweroff,session,dark,light,theme,dnd,clear,mute,timer,stopwatch,open overview,open music,open calendar");
        const withHibernate = C.list(sections, [power[0], power[1], power[2], { id: "hibernate", label: "Hibernate", icon: "\u{f0717}", confirm: false }, power[3], power[4]]);
        compare(names(withHibernate).split(",").slice(0, 6).join(","), "lock,logout,suspend,hibernate,reboot,poweroff");
        compare(cmds.filter(c => c.confirm).map(c => c.name).join(","), "logout,reboot,poweroff");
        compare(byName(cmds, "timer").arg, "minutes");
        compare(byName(cmds, "lock").arg, "");
        compare(byName(cmds, "lock").description, "Lock");
        compare(byName(cmds, "lock").glyph, "\u{f033e}");
        compare(byName(cmds, "lock").run.type, "power");
        compare(byName(cmds, "lock").run.value, "lock");
        compare(byName(cmds, "light").run.type, "theme");
        compare(byName(cmds, "light").run.value, "light");
        compare(byName(cmds, "theme").run.value, "toggle");
        compare(byName(cmds, "open music").run.type, "open");
        compare(byName(cmds, "open music").run.value, "music");
        for (const c of cmds) {
            verify(c.description !== "", c.name);
            verify(c.glyph !== "", c.name);
            verify(typeof c.confirm === "boolean", c.name);
        }
    }

    function test_match_empty() {
        const cmds = C.list(sections, power);
        const all = C.match(cmds, "");
        compare(all.map(m => m.command.name).join(","), names(cmds));
        for (const m of all)
            compare(m.ready, m.command.name !== "timer", m.command.name);
    }

    function test_match_names() {
        const cmds = C.list(sections, power);
        const lo = matchNames(cmds, "lo");
        compare(lo.slice(0, 2).join(","), "lock,logout");
        compare(lo.indexOf("clear"), -1);
        compare(matchNames(cmds, "light")[0], "light");
        compare(matchNames(cmds, "open mu")[0], "open music");
        const mu = matchNames(cmds, "mu");
        compare(mu, ["mute", "open music"]);
        compare(matchNames(cmds, "zzz").length, 0);
        compare(matchNames(cmds, "LIGHT")[0], "light");
    }

    function test_timer_argument() {
        const cmds = C.list(sections, power);
        const t = C.match(cmds, "timer 10")[0];
        compare(t.command.name, "timer");
        compare(t.arg, "10");
        verify(t.ready);
        verify(C.match(cmds, "timer 2.5")[0].ready);
        verify(C.match(cmds, "timer 1440")[0].ready);
        verify(C.match(cmds, "TIMER 5")[0].ready);
        for (const bad of ["timer", "timer ", "timer abc", "timer -5", "timer 0", "timer 1e9", "timer 1441", "timer 10 20", "timer Infinity", "timer .5", "timer 5."]) {
            const m = C.match(cmds, bad)[0];
            compare(m.command.name, "timer", bad);
            verify(!m.ready, bad);
        }
        // Only partly typed: a fuzzy match on the name, nothing to run yet.
        const partial = C.match(cmds, "tim")[0];
        compare(partial.command.name, "timer");
        compare(partial.arg, "");
        verify(!partial.ready);
    }

    function test_match_degenerate() {
        const cmds = C.list(sections, power);
        compare(C.match(cmds, "/").length, 0);
        compare(C.match(cmds, "   ").length, cmds.length);
        compare(C.match(cmds, "x".repeat(500)).length, 0);
        compare(C.match(cmds, "[(").length, 0);
        compare(C.match(cmds, "timer " + "9".repeat(500))[0].ready, false);
    }

    function test_usage() {
        const cmds = C.list(sections, power);
        compare(C.usage(byName(cmds, "timer")), "/timer <minutes>");
        compare(C.usage(byName(cmds, "lock")), "/lock");
        compare(C.usage(byName(cmds, "open music")), "/open music");
    }

    function test_partial_name_with_argument() {
        const cmds = C.list(sections, power);
        for (const typed of ["ti 5", "tim 5", "tim   5"]) {
            const m = C.match(cmds, typed);
            compare(m[0].command.name, "timer", typed);
            compare(m[0].arg, "5", typed);
            verify(!m[0].ready, typed);
        }
        // Only the exact name is ready.
        verify(C.match(cmds, "timer 5")[0].ready);
        // Without an argument it stays as it was.
        compare(C.match(cmds, "ti")[0].arg, "");
        // Nothing to list, and no-arg commands never take an argument.
        compare(C.match(cmds, "zz 5").length, 0);
        compare(C.match(cmds, "lo 5").length, 0);
    }
}
