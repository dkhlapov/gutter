import QtQuick
import QtTest
import "../lib/launcher.js" as L

TestCase {
    name: "Launcher"

    readonly property real now: 1700000000000
    readonly property real day: 86400000

    function app(id, name, extra) {
        const a = {
            id: id,
            name: name,
            genericName: "",
            comment: "",
            icon: "",
            keywords: [],
            command: [id],
            runInTerminal: false,
            workingDirectory: ""
        };
        for (const k in (extra || {}))
            a[k] = extra[k];
        return a;
    }

    function ids(list) {
        return list.map(a => a.id);
    }

    function test_parse() {
        compare(L.parse("firefox"), {mode: "apps", text: "firefox"});
        compare(L.parse("/lock"), {mode: "command", text: "lock"});
        compare(L.parse("  /timer 10"), {mode: "command", text: "timer 10"});
        compare(L.parse("2023").mode, "apps");
        compare(L.parse("a/b").mode, "apps");
    }

    function test_parse_degenerate() {
        compare(L.parse(""), {mode: "apps", text: ""});
        compare(L.parse("   "), {mode: "apps", text: ""});
        compare(L.parse("/"), {mode: "command", text: ""});
        compare(L.parse("//"), {mode: "command", text: "/"});
        compare(L.parse("/ lock"), {mode: "command", text: "lock"});
        compare(L.parse("x".repeat(500)).mode, "apps");
    }

    function test_fuzzy_order() {
        verify(L.fuzzy("fi", "Firefox") > L.fuzzy("fi", "Profile Editor"));
        verify(L.fuzzy("pe", "Profile Editor") > L.fuzzy("pe", "Spectacle"));
        compare(L.fuzzy("zz", "Firefox"), -1);
        verify(L.fuzzy("FIRE", "firefox") > 0);
        compare(L.fuzzy("", "anything"), 0);
        verify(L.fuzzy("ffx", "Firefox") > 0);
    }

    function test_fuzzy_regex_characters() {
        verify(L.fuzzy("c++", "C++ Tools") > 0);
        verify(L.fuzzy("[", "a[b") > 0);
        verify(L.fuzzy("\\", "a\\b") > 0);
        compare(L.fuzzy("(", "none"), -1);
        compare(L.fuzzy("a".repeat(500), "abc"), -1);
    }

    function test_frecency() {
        compare(L.frecency(undefined, now), 0);
        compare(L.frecency({count: 4, last: now}, now), 4);
        fuzzyCompare(L.frecency({count: 4, last: now - 14 * day}, now), 2, 0.001);
        compare(L.frecency({count: 4, last: now + 5 * day}, now), 4);
    }

    function test_bump() {
        const a = L.bump({}, "a", now);
        compare(a, {a: {count: 1, last: now}});
        const b = L.bump(a, "a", now + 10);
        compare(b.a.count, 2);
        compare(b.a.last, now + 10);
        compare(a.a.count, 1);
        compare(a.a.last, now);
    }

    function test_rank_empty_query() {
        const apps = [app("b", "Beta"), app("c", "Charlie"), app("a", "Alpha"), app("d", "Delta")];
        const usage = {c: {count: 5, last: now}, d: {count: 2, last: now}};
        compare(ids(L.rank(apps, "", usage, now, 10)), ["c", "d", "a", "b"]);
        compare(ids(L.rank(apps, "", usage, now, 2)), ["c", "d"]);
    }

    function test_rank_match_beats_history() {
        const firefox = app("firefox", "Firefox");
        const profile = app("profile", "Profile Editor");
        const usage = {profile: {count: 20, last: now}};
        compare(ids(L.rank([profile, firefox], "fi", usage, now, 10)), ["firefox", "profile"]);

        const one = app("one", "Notes One");
        const two = app("two", "Notes Two");
        const u2 = {two: {count: 3, last: now}};
        // Same score for "notes": more usage first.
        compare(ids(L.rank([one, two], "notes", u2, now, 10)), ["two", "one"]);
    }

    function test_rank_secondary_fields() {
        const firefox = app("firefox", "Firefox", {keywords: ["Web", "Browser"]});
        const tools = app("tools", "Browser Tools");
        const other = app("other", "Calculator");
        compare(ids(L.rank([firefox, other, tools], "browser", {}, now, 10)), ["tools", "firefox"]);

        const gen = app("gen", "Zed", {genericName: "Text Editor"});
        compare(ids(L.rank([gen, other], "editor", {}, now, 10)), ["gen"]);
    }

    function test_parse_usage_rejects_bad_files() {
        compare(L.parseUsage("garbage"), null);
        compare(L.parseUsage("[]"), null);
        compare(L.parseUsage('{"version":2,"apps":{}}'), null);
        compare(L.parseUsage(""), null);

        const mixed = {
            version: 1,
            apps: {
                neg: {count: -1, last: 1},
                str: {count: "x", last: 1},
                nul: {count: null, last: 1},
                badlast: {count: 1, last: "x"},
                good: {count: 3, last: 42}
            }
        };
        compare(L.parseUsage(JSON.stringify(mixed)), {good: {count: 3, last: 42}});

        const big = {};
        const stamp = i => now - (5000 - i) * 1000;
        for (let i = 0; i < 5000; i++)
            big["app" + i] = {count: 1, last: stamp(i)};
        const parsed = L.parseUsage(JSON.stringify({version: 1, apps: big}));
        compare(Object.keys(parsed).length, 2000);
        // The cap keeps the most recently used: app3000..app4999 survive, the older 3 000 go.
        const kept = Object.keys(parsed);
        verify(kept.every(id => parsed[id].last >= stamp(3000)), "an old entry survived the cap");
        verify(parsed.app4999 !== undefined, "newest entry dropped");
        verify(parsed.app3000 !== undefined, "oldest entry inside the cap dropped");
        compare(parsed.app2999, undefined);
        compare(parsed.app0, undefined);
        compare(parsed.app3000, {count: 1, last: stamp(3000)});

        // Same when the file lists the newest first.
        const rev = {};
        for (let i = 4999; i >= 0; i--)
            rev["app" + i] = {count: 1, last: stamp(i)};
        const parsedRev = L.parseUsage(JSON.stringify({version: 1, apps: rev}));
        compare(Object.keys(parsedRev).length, 2000);
        verify(Object.keys(parsedRev).every(id => parsedRev[id].last >= stamp(3000)), "an old entry survived the cap (reversed)");

        const u = {a: {count: 2, last: 5}, b: {count: 1, last: 9}};
        compare(L.parseUsage(L.serializeUsage(u)), u);
    }

    function test_app_command() {
        compare(L.appCommand({command: ["firefox", "--new-window"], runInTerminal: false}, "foot"), ["firefox", "--new-window"]);
        compare(L.appCommand({command: ["htop"], runInTerminal: true}, "foot"), ["foot", "-e", "htop"]);
        compare(L.appCommand({command: ["htop"], runInTerminal: true}, "  "), ["foot", "-e", "htop"]);
        compare(L.appCommand({command: [], runInTerminal: false}, "foot"), []);
        compare(L.appCommand({command: [], runInTerminal: true}, "foot"), []);
    }

    function test_rank_empty_app_list() {
        compare(L.rank([], "", {}, now, 10), []);
        compare(L.rank([], "fire", {}, now, 10), []);
    }

    function test_rank_empty_and_blank_query_list_the_same() {
        const apps = [app("b", "Beta"), app("c", "Charlie"), app("a", "Alpha")];
        const usage = {c: {count: 2, last: now}};
        const base = ids(L.rank(apps, "", usage, now, 10));
        compare(base.length, 3);
        const blanks = ["   ", "\t\n", undefined, null];
        for (let i = 0; i < blanks.length; i++)
            compare(ids(L.rank(apps, blanks[i], usage, now, 10)), base, `blank query #${i}`);
    }

    function test_rank_non_string_query() {
        const apps = [app("a", "Alpha 2"), app("b", "Beta")];
        const queries = [42, 0, true, {}, [], ["al"], NaN];
        for (let i = 0; i < queries.length; i++) {
            const r = L.rank(apps, queries[i], {}, now, 10);
            verify(Array.isArray(r), `query #${i}`);
            verify(r.length <= apps.length, `query #${i}`);
        }
        compare(ids(L.rank(apps, 2, {}, now, 10)), ["a"]);
        // A zero is text, not "nothing typed": it matches no app and does not list them all.
        compare(L.rank(apps, 0, {}, now, 10).length, 0);
    }

    function test_rank_weird_usage() {
        const apps = [app("b", "Beta"), app("a", "Alpha")];
        const odd = [undefined, null, {}, [], "text", 7, {a: null}, {a: {}}, {a: {count: "x", last: "y"}}, {a: {count: NaN, last: now}}, {a: {count: Infinity, last: now}}];
        for (let i = 0; i < odd.length; i++) {
            for (const q of ["", "a"]) {
                const r = L.rank(apps, q, odd[i], now, 10);
                verify(Array.isArray(r), `usage #${i} query "${q}"`);
                compare(r.length, 2, `usage #${i} query "${q}"`);
            }
        }
        // Records that are not usable count for nothing: "b" stays behind "a", as with no history at all.
        const bad = [{count: "x", last: "y"}, {count: "5", last: now}, {count: NaN, last: now}, {count: 5, last: "1"}, {count: 5}, null];
        for (let i = 0; i < bad.length; i++)
            compare(ids(L.rank(apps, "", {b: bad[i]}, now, 10)), ["a", "b"], `bad record #${i}`);
        // The same unusable records on the first app next to a used one: they must not tie with, or outrank, real
        // history.
        const three = [app("a", "Alpha"), app("b", "Beta"), app("c", "Charlie")];
        for (let i = 0; i < bad.length; i++) {
            const usage = {a: bad[i], b: {count: 5, last: now}};
            compare(ids(L.rank(three, "", usage, now, 10)), ["b", "a", "c"], `bad record #${i} beside a used app`);
        }
        // A good record for the same app does move it up, so the loop above can tell the difference.
        compare(ids(L.rank(apps, "", {b: {count: 5, last: now}}, now, 10)), ["b", "a"]);
    }

    function test_rank_limit() {
        const apps = [app("a", "Alpha"), app("b", "Beta"), app("c", "Charlie")];
        compare(L.rank(apps, "", {}, now, 0), []);
        compare(L.rank(apps, "a", {}, now, 0), []);
        compare(L.rank(apps, "", {}, now, 1).length, 1);
        compare(ids(L.rank(apps, "", {}, now, 3)), ["a", "b", "c"]);
        compare(ids(L.rank(apps, "", {}, now, 100)), ["a", "b", "c"]);
        compare(ids(L.rank(apps, "", {}, now, Infinity)), ["a", "b", "c"]);
        for (const limit of [-1, -100, undefined, null, NaN, "2"])
            verify(Array.isArray(L.rank(apps, "", {}, now, limit)), `limit ${String(limit)}`);
        compare(apps.length, 3);
    }

    function test_rank_apps_with_missing_fields() {
        const bare = [{id: "x"}, {name: "Named"}, {}, {id: "k", name: "Kw", keywords: undefined}, {id: "n", name: "Nul", keywords: null, comment: null, genericName: null}];
        for (const q of ["", "n", "named", "zzzz"]) {
            const r = L.rank(bare, q, {}, now, 10);
            verify(Array.isArray(r), `query "${q}"`);
            if (q === "")
                compare(r.length, bare.length, `query "${q}"`);
        }
        // Only the two names rank: null or missing generic name, comment and keywords are not searched as text
        // (bare[4] also matches by id, at half weight).
        compare(L.rank(bare, "n", {}, now, 10), [bare[1], bare[4]]);
        compare(L.rank(bare, "named", {}, now, 10)[0], bare[1]);
        compare(L.rank(bare, "zzzz", {}, now, 10).length, 0);
    }

    function test_proto_ids_rank_like_any_other() {
        const names = ["__proto__", "constructor", "toString", "hasOwnProperty", "prototype", "valueOf"];
        const apps = names.map(n => app(n, "App " + n));
        for (const n of names) {
            const usage = L.bump({}, n, now);
            // Whatever bump did with the name, ranking with it must not throw or lose apps.
            const empty = L.rank(apps, "", usage, now, 10);
            compare(empty.length, names.length, `empty query, usage of ${n}`);
            const typed = L.rank(apps, "app", usage, now, 10);
            compare(typed.length, names.length, `typed query, usage of ${n}`);
            // Skipped: bump never records "__proto__", and the engine ignores a "hasOwnProperty" property. The rest
            // get history.
            if (n !== "__proto__" && n !== "hasOwnProperty") {
                compare(ids(empty)[0], n, `empty query, usage of ${n}`);
                compare(ids(typed)[0], n, `typed query, usage of ${n}`);
            }
        }
        // With no history at all they order by name like any other app.
        compare(ids(L.rank(apps, "", {}, now, 10)), ["__proto__", "constructor", "hasOwnProperty", "prototype", "toString", "valueOf"]);
    }

    function test_proto_query_text() {
        const apps = [app("a", "Alpha"), app("constructor", "Constructor Kit"), app("t", "toString Tool")];
        for (const q of ["__proto__", "constructor", "toString", "hasOwnProperty", "/__proto__"]) {
            const r = L.rank(apps, q, {}, now, 10);
            verify(Array.isArray(r), q);
        }
        compare(ids(L.rank(apps, "constructor", {}, now, 10)), ["constructor"]);
        compare(ids(L.rank(apps, "tostring", {}, now, 10)), ["t"]);
        compare(L.parse("__proto__"), {mode: "apps", text: "__proto__"});
        compare(L.parse("/__proto__"), {mode: "command", text: "__proto__"});
    }

    function test_bump_proto_and_prototype_names() {
        const p = L.bump({}, "__proto__", now);
        compare(Object.keys(p).length, 0);
        compare(p.count, undefined);
        compare(Object.getPrototypeOf(p), Object.prototype);

        for (const id of ["constructor", "toString", "valueOf"]) {
            const u = L.bump(L.bump({}, id, now), id, now + 1);
            compare(Object.keys(u), [id], id);
            compare(u[id], {count: 2, last: now + 1}, id);
            compare(Object.getPrototypeOf(u), Object.prototype, id);
        }
    }

    function test_bump_odd_input() {
        compare(L.bump(undefined, "a", now), {a: {count: 1, last: now}});
        compare(L.bump(null, "a", now), {a: {count: 1, last: now}});
        // A damaged record restarts at one launch instead of becoming NaN.
        compare(L.bump({a: {count: "x", last: 1}}, "a", now), {a: {count: 1, last: now}});
        compare(L.bump({a: null}, "a", now), {a: {count: 1, last: now}});
        // Other entries survive.
        compare(L.bump({b: {count: 4, last: 2}}, "a", now).b, {count: 4, last: 2});
    }

    function test_parse_usage_proto_key() {
        const raw = `{"version":1,"apps":{"__proto__":{"count":5,"last":${now - 2000}},"a":{"count":1,"last":${now - 1000}}}}`;
        const u = L.parseUsage(raw);
        compare(Object.keys(u), ["a"]);
        compare(u.count, undefined);
        compare(u.last, undefined);
        compare(Object.getPrototypeOf(u), Object.prototype);
        const apps = [app("a", "Alpha"), app("b", "Beta"), app("c", "Charlie")];
        // Only "a" has a record: it leads, and "b" and "c" are not given the poisoned count.
        compare(ids(L.rank(apps, "", u, now, 10)), ["a", "b", "c"]);
        compare(ids(L.rank(apps, "", L.bump(u, "c", now), now, 10))[0], "c");

        const only = L.parseUsage(`{"version":1,"apps":{"__proto__":{"count":5,"last":${now}}}}`);
        compare(Object.keys(only).length, 0);
        compare(only.count, undefined);

        const names = L.parseUsage(`{"version":1,"apps":{"constructor":{"count":2,"last":${now - 3000}},"toString":{"count":1,"last":${now - 4000}}}}`);
        compare(names.constructor.count, 2);
        compare(names.constructor.last, now - 3000);
        compare(names.toString.count, 1);
        compare(names.toString.last, now - 4000);
        compare(JSON.stringify(L.parseUsage(L.serializeUsage(names))), JSON.stringify(names));
    }

    function test_app_command_shapes() {
        // A bare string is not split into characters, and an empty first word is no command.
        compare(L.appCommand({command: "htop", runInTerminal: false}, "foot"), []);
        compare(L.appCommand({command: "htop", runInTerminal: true}, "foot"), []);
        compare(L.appCommand({command: [""], runInTerminal: false}, "foot"), []);
        compare(L.appCommand({command: [""], runInTerminal: true}, "foot"), []);
        compare(L.appCommand({command: null, runInTerminal: false}, "foot"), []);
        compare(L.appCommand({command: undefined, runInTerminal: true}, "foot"), []);
        compare(L.appCommand({runInTerminal: false}, "foot"), []);
        // An array-like (a QML list) works like an array.
        compare(L.appCommand({command: {length: 2, 0: "firefox", 1: "--private-window"}, runInTerminal: false}, "foot"), ["firefox", "--private-window"]);
        compare(L.appCommand({command: {length: 1, 0: "htop"}, runInTerminal: true}, "alacritty"), ["alacritty", "-e", "htop"]);
        compare(L.appCommand({command: ["htop"], runInTerminal: true}, null), ["foot", "-e", "htop"]);
    }

    function test_parse_usage_clamps_future_last() {
        const text = JSON.stringify({version: 1, apps: {a: {count: 2, last: now + 400 * day}, b: {count: 1, last: now - day}}});
        const clamped = L.parseUsage(text, now);
        compare(clamped.a.last, now);
        compare(clamped.b.last, now - day);
        // Without a clock the times are kept as they are.
        compare(L.parseUsage(text).a.last, now + 400 * day);
        compare(L.parseUsage(text, undefined).a.last, now + 400 * day);
        compare(L.parseUsage(text, NaN).a.last, now + 400 * day);
    }

    function test_parse_usage_clamped_last_does_not_pin() {
        // A bogus future time must not keep an entry in the kept 2 000 for ever: once clamped (and saved) it ages like
        // the rest, and newer launches push it out.
        const file = JSON.stringify({version: 1, apps: {bogus: {count: 1, last: now + 1000 * day}}});
        const saved = L.parseUsage(file, now);
        compare(saved.bogus.last, now);
        const later = now + day;
        for (let i = 0; i < 2000; i++)
            saved["app" + i] = {count: 1, last: now + 1 + i};
        const parsed = L.parseUsage(L.serializeUsage(saved), later);
        compare(Object.keys(parsed).length, 2000);
        verify(parsed.bogus === undefined);
        verify(parsed.app0 !== undefined);
    }

    function test_count_is_capped() {
        compare(L.MAX_COUNT, 1000);
        const parsed = L.parseUsage(JSON.stringify({version: 1, apps: {a: {count: 1e12, last: now}, b: {count: 999, last: now}}}), now);
        compare(parsed.a.count, 1000);
        compare(parsed.b.count, 999);
        compare(L.parseUsage(JSON.stringify({version: 1, apps: {a: {count: 1e12, last: now}}})).a.count, 1000);
        compare(L.bump({a: {count: 1000, last: 1}}, "a", now).a.count, 1000);
        compare(L.bump({a: {count: 1e12, last: 1}}, "a", now).a.count, 1000);
        compare(L.bump({a: {count: 999, last: 1}}, "a", now).a.count, 1000);
    }

    function test_history_margin() {
        // A prefix match must stay clear of the best a launch history can add to a mid-word match.
        verify(L.fuzzy("fi", "Firefox") - L.fuzzy("fi", "Profile Editor") - L.HISTORY_CAP >= 5);
    }

    function test_rank_secondary_match_gets_less_history() {
        // "fi" is a weak match on the name of the editor and only a comment match on the used app.
        const editor = app("editor", "Profile Editor");
        const wifi = app("wifi", "Network", {comment: "Wi-Fi settings"});
        const usage = {wifi: {count: 50, last: now}};
        compare(ids(L.rank([wifi, editor], "fi", usage, now, 10)), ["editor", "wifi"]);
        // A name match weaker than the editor's is lifted by the same history only when it is in full.
        const swift = app("swift", "Swiftie");
        compare(ids(L.rank([swift, editor], "fi", {}, now, 10)), ["editor", "swift"]);
        compare(ids(L.rank([swift, editor], "fi", {swift: {count: 50, last: now}}, now, 10)), ["swift", "editor"]);
    }
}
