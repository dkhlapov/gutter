import QtQuick
import QtTest
import "../lib/agents.js" as A

TestCase {
    name: "Agents"

    function ev(t, e, extra) {
        return Object.assign({ t, e, id: "s1", cwd: "/home/d/Projects/island" }, extra || {});
    }

    function test_parseSkipsBrokenLines() {
        const text = '{"t":1,"e":"Stop","id":"a"}\n{"t":2,"e":"Sto\n\n{"t":"x","e":"Stop","id":"b"}\n{"e":"Stop","id":"c","t":3}\n';
        compare(A.parseLines(text).map(e => e.id), ["a", "c"]);
        compare(A.parseLines("").length, 0);
    }

    function test_project() {
        compare(A.project("/home/d/Projects/island"), "island");
        compare(A.project("/home/d/Projects/island/"), "island");
        compare(A.project(""), "~");
    }

    function test_lifecycle() {
        let s = A.reduce([ev(1000, "SessionStart")], 1000);
        compare(s.s1.status, "idle");
        s = A.reduce([ev(1000, "SessionStart"), ev(2000, "UserPromptSubmit", { prompt: "Fix\n  the   bug" })], 2000);
        compare(s.s1.status, "working");
        compare(s.s1.prompt, "Fix the bug");
        compare(s.s1.promptAt, 2000);
        s = A.reduce([ev(2000, "UserPromptSubmit", { prompt: "x" }), ev(3000, "PreToolUse", { tool: "Bash" })], 3000);
        compare(s.s1.tool, "Bash");
        s = A.reduce([ev(2000, "UserPromptSubmit", { prompt: "x" }), ev(3000, "PreToolUse", { tool: "Bash" }), ev(9000, "Stop")], 9000);
        compare(s.s1.status, "done");
        compare(s.s1.doneAt, 9000);
        compare(s.s1.tool, "");
        // The prompt stays for the card after the task finishes.
        compare(s.s1.prompt, "x");
    }

    function test_permissionPromptWaitsThenResumes() {
        const base = [ev(1, "UserPromptSubmit", { prompt: "x" }), ev(2, "PreToolUse", { tool: "Bash" }), ev(3, "Notification", { msg: "Claude needs your permission to use Bash" })];
        let s = A.reduce(base, 3);
        compare(s.s1.status, "waiting");
        compare(s.s1.message, "Claude needs your permission to use Bash");
        s = A.reduce(base.concat([ev(4, "PostToolUse", { tool: "Bash" })]), 4);
        compare(s.s1.status, "working");
        compare(s.s1.message, "");
    }

    // Claude Code's "waiting for your input" after 60 s idle is not a mid-task question.
    function test_idleNotificationAfterDoneIgnored() {
        const s = A.reduce([ev(1, "UserPromptSubmit", { prompt: "x" }), ev(2, "Stop"), ev(60002, "Notification", { msg: "Claude is waiting for your input" })], 60002);
        compare(s.s1.status, "done");
        compare(A.reduce([ev(1, "SessionStart"), ev(2, "Notification", { msg: "waiting" })], 2).s1.status, "idle");
    }

    function test_sessionEndRemoves() {
        compare(Object.keys(A.reduce([ev(1, "UserPromptSubmit", { prompt: "x" }), ev(2, "SessionEnd")], 2)).length, 0);
    }

    function test_finishedSessionStaysAfterEnd() {
        const events = [ev(1, "UserPromptSubmit", { prompt: "x" }), ev(2, "Stop"), ev(3, "SessionEnd")];
        compare(A.reduce(events, 3).s1.status, "done");
        compare(Object.keys(A.reduce(events, 3 + A.ENDED_MS + 1)).length, 0);
    }

    function test_sessionSeenMidTaskCountsFromFirstEvent() {
        const s = A.reduce([ev(5000, "PostToolUse"), ev(6000, "PreToolUse", { tool: "Bash" })], 6000).s1;
        compare(s.promptAt, 6000);
        compare(A.statusText(s, 66000), "Bash · 1 min");
        compare(A.statusText({ status: "working", tool: "Bash", promptAt: 0 }, 66000), "Bash");
    }

    function test_envelopePromptShowsInnerText() {
        const s = A.reduce([ev(1, "UserPromptSubmit", { prompt: '<relay from="coordinator" session="x">\n  <note>Check the hooks</note>\n</relay>' })], 1);
        compare(s.s1.prompt, "Check the hooks");
        compare(A.reduce([ev(1, "UserPromptSubmit", { prompt: '<relay from="coordinator" current-ti' })], 1).s1.prompt, "Automated prompt");
        compare(A.reduce([ev(1, "UserPromptSubmit", { prompt: "fix <b> tags" })], 1).s1.prompt, "fix <b> tags");
    }

    function test_interruptedTurnGoesIdle() {
        const evs = [ev(0, "UserPromptSubmit", { prompt: "x" }), ev(1000, "PostToolUse", { tool: "Bash" })];
        compare(A.reduce(evs, 1000 + A.QUIET_MS)[evs[0].id].status, "working");
        const s = A.reduce(evs, 1001 + A.QUIET_MS)[evs[0].id];
        compare(s.status, "idle");
        compare(s.tool, "");
        // Waiting on the user is not a stall.
        const w = [ev(0, "UserPromptSubmit", { prompt: "x" }), ev(1000, "Notification", { msg: "allow?" })];
        compare(A.reduce(w, 1001 + A.QUIET_MS)[w[0].id].status, "waiting");
    }

    function test_staleSessionsDropped() {
        compare(Object.keys(A.reduce([ev(0, "UserPromptSubmit", { prompt: "x" })], A.STALE_MS + 1)).length, 0);
        compare(Object.keys(A.reduce([ev(0, "UserPromptSubmit", { prompt: "x" })], A.STALE_MS)).length, 1);
    }

    function test_listOrdersNeedsYouFirst() {
        const events = [
            Object.assign(ev(1, "UserPromptSubmit", { prompt: "a" }), { id: "done" }),
            Object.assign(ev(2, "Stop"), { id: "done" }),
            Object.assign(ev(3, "UserPromptSubmit", { prompt: "b" }), { id: "work" }),
            Object.assign(ev(4, "SessionStart"), { id: "idle" }),
            Object.assign(ev(5, "UserPromptSubmit", { prompt: "c" }), { id: "ask" }),
            Object.assign(ev(6, "Notification", { msg: "?" }), { id: "ask" }),
            Object.assign(ev(7, "UserPromptSubmit", { prompt: "d" }), { id: "work2" })
        ];
        const items = A.list(A.reduce(events, 7));
        compare(items.map(s => s.id), ["ask", "work2", "work", "done", "idle"]);
        compare(A.counts(items), { working: 2, waiting: 1, done: 1, idle: 1, total: 5 });
    }

    function test_finishedSince() {
        const events = [ev(1, "Stop"), ev(5, "UserPromptSubmit"), ev(9, "Stop")];
        compare(A.finishedSince(events, 1).map(e => e.t), [9]);
        compare(A.finishedSince(events, 9).length, 0);
    }

    function test_finishedSinceTook() {
        const events = [ev(1000, "UserPromptSubmit", { prompt: "Long one" }), ev(41000, "PreToolUse", { tool: "Edit" }), ev(61000, "Stop")];
        const f = A.finishedSince(events, 0);
        compare(f.length, 1);
        compare(f[0].took, 60000);
        compare(f[0].prompt, "Long one");
        compare(f[0].cwd, "/home/d/Projects/island");
    }

    function test_finishedSinceEndedSessionKeepsOthers() {
        // A long task in s1 finishes, then a quick claude -p in s2 stops and exits in the same batch.
        const events = [
            ev(1000, "UserPromptSubmit", { prompt: "Long" }),
            ev(50000, "UserPromptSubmit", { id: "s2", cwd: "/tmp/p", prompt: "Quick" }),
            ev(61000, "Stop"),
            ev(62000, "Stop", { id: "s2", cwd: "/tmp/p" }),
            ev(62001, "SessionEnd", { id: "s2", cwd: "/tmp/p" })
        ];
        const f = A.finishedSince(events, 0);
        compare(f.map(e => e.id), ["s1", "s2"]);
        compare(f.filter(e => e.took >= A.DONE_MIN_MS).map(e => e.id), ["s1"]);
        // An ended claude -p run that took long still counts as finished.
        const p = A.finishedSince([ev(1000, "UserPromptSubmit", { prompt: "p" }), ev(40000, "Stop"), ev(40001, "SessionEnd")], 0);
        compare(p.length, 1);
        compare(p[0].took, 39000);
    }

    function test_finishedSinceUnknownSession() {
        // A Stop whose prompt was trimmed from the log: no prompt, no duration.
        const f = A.finishedSince([ev(5, "Stop")], 0);
        compare(f[0].took, 0);
        compare(f[0].prompt, "");
    }

    function test_statusText() {
        const now = 10 * 60000;
        compare(A.statusText({ status: "working", tool: "Edit", promptAt: now - 125000 }, now), "Edit · 2 min");
        compare(A.statusText({ status: "working", tool: "", promptAt: now - 5000 }, now), "Thinking · 5 s");
        compare(A.statusText({ status: "waiting", message: "" }, now), "Needs your input");
        compare(A.statusText({ status: "done", doneAt: now - 30000 }, now), "Finished just now");
        compare(A.statusText({ status: "done", doneAt: now - 3 * 3600000 }, now), "Finished 3 h ago");
        compare(A.statusText({ status: "idle" }, now), "Ready");
    }

    function test_longPromptCut() {
        const s = A.reduce([ev(1, "UserPromptSubmit", { prompt: "x".repeat(400) })], 1);
        compare(s.s1.prompt.length, 160);
        verify(s.s1.prompt.endsWith("…"));
    }
}
