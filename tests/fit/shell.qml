//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import qs.components
import qs.launcher
import qs.pill
import qs.services
import qs.settings
import qs.theme
import "pill/sections/notifications"
import "lib/pillState.js" as PillState

// The fit check (scripts/fit.sh): the collapsed pill, sized and animated the way pill/Pill.qml does it, steps
// through every face with long content. After every frame drawn, each visible item that paints must lie inside
// the ink box: the label tab may cover the outline, everything else stays inside it. The notification bubble
// under the pill gets the same check against its own outline, with the tail's height kept clear on top. The
// launcher box and the session screen, at several window scales, get the same check against their own ink box
// (see the steps from "launcher" on). A notification card of the history is checked in its own window: nothing
// outside its box, the app name whole or cut short for the age as the step expects, the age following the name
// directly and staying clear of the dismiss button.
ShellRoot {
    id: shell

    readonly property string longProject: "/home/user/Projects/gutter/.claude/worktrees/a-feature-branch-with-a-much-longer-name"
    property var failures: []
    property int frames: 0
    property int step: -1
    property string stepName: ""
    // With a bubble step: the tallest the bubble may be (0 for no limit); a taller one has stacked its buttons.
    property real bubbleMaxH: 0
    // Which window is shown: the pill's or the launcher's, and the launcher's scale (the window's `ui`).
    property string surface: "pill"
    property real ui: 1
    // False until the launcher's boxes have stopped changing size (the list's height eases) for longer than an
    // animation takes, counted from the step's start or the last change.
    property bool launcherStill: true
    property string lastLauncherSize: ""
    property real launcherMovedAt: 0
    // How many frames of this launcher step were walked with the box at rest; a step needs at least one.
    property int restWalks: 0
    // How many frames of this card step were checked; a step needs at least one.
    property int cardWalks: 0
    // What the card on show is checked for: the app name it must show whole, "long" for a name that gives way to
    // the age, or "" for no card.
    property string cardExpect: ""

    // Each step sets a face and its content; the next one starts once the box has settled.
    readonly property var steps: [
        {
            name: "hidden",
            run: () => stage.set({ hidden: true })
        },
        {
            name: "idle (fullscreen left)",
            run: () => {
                track("Song", "Band", "Album");
                stage.set({});
            }
        },
        {
            name: "track pop, short track",
            run: () => {
                track("Song", "Band", "Album");
                stage.set({ id: "track" });
            }
        },
        {
            name: "track pop, longer track",
            run: () => track("A Considerably Longer Track Title Than Any Pill Should Hold", "An Artist With A Long Name", "And An Album Name Too")
        },
        {
            name: "volume",
            run: () => stage.set({ id: "volume" })
        },
        {
            name: "brightness",
            run: () => stage.set({ id: "brightness" })
        },
        {
            name: "keys, layout",
            run: () => {
                KbLayout.layout = "English (US)";
                stage.set({ id: "kbLayout" });
            }
        },
        {
            name: "keys, long layout name",
            run: () => KbLayout.layout = "A Keyboard Layout With An Unreasonably Long Descriptive Name (and variant, no dead keys)"
        },
        {
            name: "keys, caps lock on",
            run: () => {
                LockKeys.locks = { caps: true, num: false };
                stage.set({ id: "capsLock" });
            }
        },
        {
            name: "keys, num lock off",
            run: () => stage.set({ id: "numLock" })
        },
        {
            name: "agent limit",
            run: () => {
                AgentUsage.alert = {
                    window: "Session",
                    pct: 95,
                    resetsIn: 3 * 3600000 + 20 * 60000
                };
                stage.set({ id: "agentLimit" });
            }
        },
        {
            name: "timer",
            run: () => stage.set({ id: "timer" })
        },
        {
            name: "stopwatch",
            run: () => stage.set({ id: "stopwatch" })
        },
        {
            name: "idle before the pop",
            run: () => stage.set({})
        },
        {
            name: "track pop straight from idle",
            run: () => stage.set({ id: "track" })
        },
        {
            name: "hidden over the pop",
            run: () => stage.set({ id: "track", hidden: true })
        },
        {
            name: "track pop (fullscreen left)",
            run: () => stage.set({ id: "track" })
        },
        {
            name: "idle again",
            run: () => stage.set({})
        },
        {
            name: "bubble, short",
            run: () => {
                note({});
                stage.set({ bubble: true });
            }
        },
        {
            name: "bubble, long summary and body",
            run: () => note({
                    appName: longProject,
                    summary: "A summary that goes on and on, much longer than a bubble can ever hold in one line of text",
                    body: "A body of many words that has to be cut at three lines, however much the app sends. ".repeat(24)
                })
        },
        {
            name: "bubble, three actions, Reply and +3",
            run: () => note({
                    summary: "Anna Kowalski",
                    body: "Are we still on for tonight?",
                    actions: [action("mark", "Mark as read"), action("mute", "Mute"), action("archive", "Archive"), action("fourth", "Never shown")],
                    canReply: true
                }, 3)
        },
        {
            name: "bubble, short text, three buttons in one row",
            run: () => {
                note({
                    summary: "Hi",
                    body: "",
                    actions: [action("a", "One"), action("b", "Two")],
                    canReply: true
                });
                bubbleMaxH = 150;
            }
        },
        {
            name: "bubble, critical with an action",
            run: () => note({
                    appName: "Battery",
                    summary: "Battery critically low",
                    body: "Plug in the charger.",
                    urgency: 2,
                    actions: [action("ok", "OK")]
                })
        },
        {
            name: "bubble, odd content",
            run: () => note({
                    appName: "A".repeat(150),
                    summary: "",
                    body: "z".repeat(2000),
                    icon: "/nonexistent/icon.png",
                    image: "/nonexistent/image.png",
                    actions: [action("a", "A button with a very long label that goes on and on"), action("b", ""), action("c", "Third"), action("d", "Fourth")],
                    canReply: true
                }, 100)
        },
        {
            name: "bubble, record gone while it folds",
            run: () => {
                Notifications.current = null;
                Notifications.queue = [];
            }
        },
        {
            name: "bubble gone",
            run: () => stage.set({})
        }
    ].concat(cardSteps(), launcherSteps())

    function track(title, artist, album) {
        Media.title = title;
        Media.artist = artist;
        Media.album = album;
    }

    // The bubble's record (a service record's fields) and, with `waiting`, that many in the queue.
    function note(over, waiting) {
        bubbleMaxH = 0;
        Notifications.current = Object.assign({
            id: 1,
            serverId: 1,
            appName: "Discord",
            icon: "",
            desktopEntry: "",
            summary: "Anna",
            body: "hey are you around later",
            urgency: 1,
            image: "",
            actions: [],
            hasDefault: false,
            canReply: false,
            replyPlaceholder: "",
            timeoutMs: 6000,
            transient: false,
            resident: false,
            at: 0,
            count: 1,
            read: false,
            live: true
        }, over);
        Notifications.queue = [1].concat(Array.from({ length: waiting ?? 0 }, (_, i) => i + 2));
    }

    function action(identifier, text) {
        return { identifier, text };
    }

    function agent(cwd, tool, pct) {
        Agents.now = Date.now();
        Agents.items = [
            {
                status: "working",
                cwd,
                tool,
                promptAt: Agents.now - 433000
            }
        ];
        AgentUsage.limits = {
            session: {
                pct
            }
        };
    }

    // The notifications section's rows: a card with a short app name must show it whole (the layout rounds the
    // name's width to a pixel), and one with a very long name keeps the age, in its row, whole. `cardExpect` is
    // what the frames of the step are checked for (see checkCard).
    function cardSteps() {
        // The card's `now` is 1000000: the record is 3 minutes old.
        const row = app => {
            note({ appName: app, at: 1000000 - 180000 });
            Notifications.history = [Notifications.current];
            Notifications.current = null;
            Notifications.queue = [];
        };
        return [
            {
                name: "card, a short app name",
                run: () => {
                    surface = "card";
                    cardExpect = "DISCORD";
                    row("Discord");
                }
            },
            {
                name: "card, an app name with a fraction of a pixel",
                run: () => {
                    cardExpect = "TELEGRAM";
                    row("Telegram");
                }
            },
            {
                name: "card, 150-character app name",
                run: () => {
                    cardExpect = "long";
                    row("A".repeat(150));
                }
            },
            {
                name: "card gone",
                run: () => {
                    surface = "pill";
                    cardExpect = "";
                    Notifications.history = [];
                }
            }
        ];
    }

    // The launcher's steps, at each scale: the box with long and short rows, a command with a long argument, a
    // waiting command, no match, a full list and lists longer than the box shows (scrolled); then the session
    // screen, resting and with a tile waiting. The scroll bar is walked only while it is shown (about 900 ms after
    // a scroll), which the long-list steps reach.
    function launcherSteps() {
        const out = [];
        const words = "Long Application Name With Many Words In It ".repeat(4).slice(0, 120);
        const wide = "W".repeat(120);
        // n rows, long and short titles and subtitles alternating.
        const appRows = n => Array.from({ length: n }, (_, i) => appRow(i % 2 ? wide : "App " + i, i % 3 ? words : ""));
        const digits = "1234567890".repeat(6);
        // More rows than the list shows at once, so it scrolls and the rows past its edge are clipped away.
        const longList = appRows(Settings.launcher.maxRows + 5);
        const set = (u, o) => {
            surface = "launcher";
            ui = u;
            // The session tiles come from Power's entries: five unless the step asks for hibernate too, whatever
            // logind says here.
            if (o.mode === "session")
                Power.can = o.can ?? { CanSuspend: "yes", CanHibernate: "no", CanReboot: "yes", CanPowerOff: "yes" };
            launcher(o);
        };
        for (const u of [1, 1.5, 2]) {
            const tag = `launcher ui ${u}: `;
            const rows = [appRow("Firefox", "Web Browser"), appRow("Files", ""), appRow(wide, words), appRow("Short", words), appRow(words, wide)];
            out.push({
                name: tag + "apps, short and long rows",
                run: () => set(u, { query: "f", results: rows })
            });
            out.push({
                name: tag + "apps, long row selected",
                run: () => set(u, { query: "f", results: rows, selected: 2 })
            });
            out.push({
                name: tag + "apps, second long row selected",
                run: () => set(u, { query: "f", results: rows, selected: 4 })
            });
            out.push({
                name: tag + "a full list",
                run: () => set(u, { query: "a", results: appRows(8), selected: 7 })
            });
            out.push({
                name: tag + "a list longer than the box shows",
                run: () => set(u, { query: "a", results: longList })
            });
            out.push({
                name: tag + "a list longer than the box shows, a late row selected",
                run: () => set(u, { query: "a", results: longList, selected: Settings.launcher.maxRows + 1 })
            });
            out.push({
                name: tag + "a list longer than the box shows, last row selected",
                run: () => set(u, { query: "a", results: longList, selected: longList.length - 1 })
            });
            out.push({
                name: tag + "long query",
                run: () => set(u, { query: "q".repeat(200), results: [appRow("Firefox", "Web Browser")] })
            });
            out.push({
                name: tag + "command, long argument",
                run: () => set(u, {
                    query: "/timer " + digits,
                    parsed: { mode: "command", text: "timer " + digits },
                    results: [commandRow("timer", "/timer", "Start a countdown", true, digits)]
                })
            });
            out.push({
                name: tag + "command, long argument, not ready",
                run: () => set(u, {
                    query: "/timer " + digits,
                    parsed: { mode: "command", text: "timer " + digits },
                    results: [commandRow("timer", "/timer <minutes>", "Start a countdown", false, digits)]
                })
            });
            out.push({
                name: tag + "commands, one waiting",
                run: () => set(u, {
                    query: "/",
                    parsed: { mode: "command", text: "" },
                    results: [commandRow("logout", "/logout", "Log out", true, ""), commandRow("poweroff", "/poweroff", words, true, ""), commandRow("timer", "/timer <minutes>", "Start a countdown", false, "")],
                    confirming: "logout"
                })
            });
            out.push({
                name: tag + "command waiting, long subtitle",
                run: () => set(u, {
                    query: "/",
                    parsed: { mode: "command", text: "" },
                    results: [commandRow("poweroff", "/poweroff", words, true, ""), commandRow("logout", "/logout", "Log out", true, "")],
                    selected: 0,
                    confirming: "poweroff"
                })
            });
            out.push({
                name: tag + "no match",
                run: () => set(u, { query: "zzzz", results: [] })
            });
            out.push({
                name: tag + "no match, command",
                run: () => set(u, { query: "/zzzz", parsed: { mode: "command", text: "zzzz" }, results: [] })
            });
            out.push({
                name: tag + "empty",
                run: () => set(u, { query: "", results: [] })
            });
            out.push({
                name: tag + "session",
                run: () => set(u, { mode: "session" })
            });
            out.push({
                name: tag + "session, a tile waiting (strip)",
                run: () => set(u, { mode: "session", confirming: "poweroff" })
            });
            out.push({
                name: tag + "session, first tile waiting (strip)",
                run: () => set(u, { mode: "session", confirming: "logout" })
            });
            out.push({
                name: tag + "session, six tiles, one waiting",
                run: () => {
                    set(u, { mode: "session", confirming: "reboot", can: { CanSuspend: "yes", CanHibernate: "yes", CanReboot: "yes", CanPowerOff: "yes" } });
                }
            });
        }
        out.push({
            name: "launcher gone",
            run: () => {
                surface = "pill";
                ui = 1;
                launcher({});
            }
        });
        return out;
    }

    function appRow(title, subtitle) {
        return { kind: "app", key: title, title, subtitle, iconName: "", app: { id: title, name: title } };
    }

    function commandRow(name, title, subtitle, ready, arg) {
        return {
            kind: "command",
            key: name,
            title,
            subtitle,
            glyph: "\u{f0425}",
            ready,
            command: { name, arg: name === "timer" ? "minutes" : "", confirm: name !== "timer" ? name : "" },
            arg
        };
    }

    // The launcher service's state for a step.
    function launcher(o) {
        Launcher.mode = o.mode ?? "launcher";
        Launcher.query = o.query ?? "";
        Launcher.parsed = o.parsed ?? { mode: "apps", text: o.query ?? "" };
        Launcher.results = o.results ?? [];
        Launcher.selected = o.selected ?? 0;
        Launcher.confirming = o.confirming ?? "";
    }

    function next() {
        step += 1;
        if (step >= steps.length) {
            for (const f of failures)
                console.log("fit: " + f);
            console.log(failures.length === 0 ? `fit: OK (${steps.length} steps, ${frames} frames checked)` : `fit: FAIL (${failures.length} failures)`);
            Qt.quit();
            return;
        }
        stepName = steps[step].name;
        steps[step].run();
        // After run(), which sets the surface: a launcher step starts moving, a pill step has nothing of it.
        launcherMovedAt = Date.now();
        launcherStill = surface !== "launcher";
        restWalks = 0;
        cardWalks = 0;
        settle.waited = 0;
        settle.restart();
    }

    // Painting items: text, rectangles (fill or outline) and the leaves (images, shaders, glyphs).
    function paints(item) {
        if (item.contentWidth !== undefined && item.elide !== undefined)
            return true;
        if (item.border !== undefined && item.color !== undefined)
            return true;
        for (const c of item.children)
            if (c.visible)
                return false;
        return true;
    }

    // What a Text paints: its own box, or, when unelided text is wider or taller, the text itself, placed by
    // its alignment.
    function textRect(t) {
        let x = 0;
        let w = t.width;
        if (t.elide === Text.ElideNone && t.contentWidth > t.width) {
            w = t.contentWidth;
            x = t.horizontalAlignment === Text.AlignRight ? t.width - w : t.horizontalAlignment === Text.AlignHCenter ? (t.width - w) / 2 : 0;
        }
        let y = 0;
        let h = Math.max(t.height, t.contentHeight);
        if (t.contentHeight > t.height)
            y = t.verticalAlignment === Text.AlignBottom ? t.height - h : t.verticalAlignment === Text.AlignVCenter ? (t.height - h) / 2 : 0;
        return Qt.rect(x, y, w, h);
    }

    function isFlickable(item) {
        return item.contentItem !== undefined && item.contentY !== undefined;
    }

    // A row of a clipping list wholly outside its viewport is not drawn: it is skipped with its content. A row
    // partly inside, and anything a shown row places outside the viewport, is still checked.
    function scrolledAway(item) {
        const v = item.parent ? item.parent.parent : null;
        if (!v || !v.clip || !isFlickable(v) || item.parent !== v.contentItem)
            return false;
        const r = item.mapToItem(v, 0, 0, item.width, item.height);
        return r.y + r.height <= 0 || r.y >= v.height || r.x + r.width <= 0 || r.x >= v.width;
    }

    // A text field (a TextInput: it has an echo mode, and no elide because it clips instead).
    function isInput(item) {
        return item.echoMode !== undefined && item.contentWidth !== undefined && item.elide === undefined;
    }

    // A field clips its own text on purpose, but only if it does; and it must not run under a sibling that paints
    // (the "cmd" tag).
    function checkInput(item, f) {
        // An unclipped field scrolls its text, so the spill is mostly to its left: the rect is approximate.
        if (!item.clip && item.contentWidth > item.width + 0.5)
            fail(item, item.mapToItem(f, 0, 0, item.contentWidth, item.height), "text overflows", f);
        const mine = item.mapToItem(f, 0, 0, item.width, item.height);
        for (const s of item.parent.children) {
            if (s === item || !s.visible || s.width <= 0 || s.height <= 0 || !paints(s))
                continue;
            const both = intersect(mine, s.mapToItem(f, 0, 0, s.width, s.height));
            if (both.width > 0.5 && both.height > 0.5)
                fail(item, mine, "runs under a sibling", f);
        }
    }

    function intersect(a, b) {
        const x = Math.max(a.x, b.x);
        const y = Math.max(a.y, b.y);
        return Qt.rect(x, y, Math.min(a.x + a.width, b.x + b.width) - x, Math.min(a.y + a.height, b.y + b.height) - y);
    }

    // Walks the content of `frame` (the pill's box unless given); `inTab` widens the allowed area to the whole
    // box, outline included; `top` is room kept clear above the content (a bubble's tail).
    function walk(item, inTab, frame, top) {
        const f = frame ?? box;
        const t0 = top ?? 0;
        if (!item.visible || item.opacity === 0 || scrolledAway(item))
            return;
        const tab = inTab || item.text !== undefined && item.halftone !== undefined;
        if (item.width > 0 && item.height > 0 && paints(item)) {
            const own = item.contentWidth !== undefined && item.elide !== undefined ? textRect(item) : Qt.rect(0, 0, item.width, item.height);
            const whole = item.mapToItem(f, own.x, own.y, own.width, own.height);
            let r = whole;
            for (let a = item; a && a !== f; a = a.parent)
                if (a.clip)
                    r = intersect(r, a.mapToItem(f, 0, 0, a.width, a.height));
            // Clipping is for the animation only: a face at rest fits its box without being cut.
            if (shell.atRest() && (r.width < whole.width - 0.5 || r.height < whole.height - 0.5))
                fail(item, whole, "cut off", f);
            if (isInput(item))
                checkInput(item, f);
            if (r.width > 0 && r.height > 0) {
                const ink = tab ? 0 : Theme.inkWidth;
                const e = 0.5;
                if (r.x < ink - e || r.y < t0 + ink - e || r.x + r.width > f.width - ink + e || r.y + r.height > f.height - ink + e)
                    fail(item, r, "outside", f);
            }
        }
        for (const c of item.children)
            walk(c, tab, f, t0);
    }

    // The first item under `item` whose text is `text` (or, with `prefix`, starts with it).
    function findText(item, text, prefix) {
        if (typeof item.text === "string" && item.contentWidth !== undefined && (prefix ? item.text.startsWith(text) : item.text === text))
            return item;
        for (const c of item.children) {
            const found = findText(c, text, prefix);
            if (found)
                return found;
        }
        return null;
    }

    // The first item under `item` with the object name `name`.
    function findNamed(item, name) {
        if (item.objectName === name)
            return item;
        for (const c of item.children) {
            const found = findNamed(c, name);
            if (found)
                return found;
        }
        return null;
    }

    // The card's header: the app name is shown whole, except the long one, which has to be cut short to leave the
    // age room; the age (" · 3 min") follows the name and ends before the dismiss button.
    function checkCard() {
        const long = cardExpect === "long";
        const app = long ? findText(ncard, "AAAA", true) : findText(ncard, cardExpect, false);
        const age = findText(ncard, " · ", true);
        const dismiss = findNamed(ncard, "dismissButton");
        if (!app || !age || !dismiss) {
            fail(ncard, Qt.rect(0, 0, ncard.width, ncard.height), "has no app name, age or dismiss button", ncard);
            return;
        }
        if (!long && app.truncated)
            fail(app, Qt.rect(0, 0, app.width, app.height), "cut short", ncard);
        if (long && !app.truncated)
            fail(app, Qt.rect(0, 0, app.width, app.height), "not cut short for the age", ncard);
        // The row's gap is taken back when the age follows, so the age starts where the name ends.
        const appEnd = app.mapToItem(ncard, app.width, 0).x;
        const ageStart = age.mapToItem(ncard, 0, 0).x;
        if (Math.abs(ageStart - appEnd) > 0.5)
            fail(age, age.mapToItem(ncard, 0, 0, age.width, age.height), "does not follow the app name directly", ncard);
        const end = age.mapToItem(ncard, age.width, 0).x;
        // The age ends before the dismiss button's left edge, wherever the layout puts it.
        if (end > dismiss.mapToItem(ncard, 0, 0).x + 0.5)
            fail(age, age.mapToItem(ncard, 0, 0, age.width, age.height), "runs into the dismiss button", ncard);
    }

    // The view the launcher window shows, and whether it has kept its size for longer than an animation takes.
    function launcherView() {
        return Launcher.mode === "session" ? sbox : lbox;
    }

    function updateLauncherStill() {
        const view = launcherView();
        const size = `${view.width}x${view.height}`;
        if (size !== lastLauncherSize)
            launcherMovedAt = Date.now();
        lastLauncherSize = size;
        launcherStill = Date.now() - launcherMovedAt > Theme.animMs + 100;
    }

    function atRest() {
        return stage.drawW === stage.target.w && stage.drawH === stage.target.h && launcherStill;
    }

    function fail(item, r, how, frame) {
        const f = frame ?? box;
        const name = String(item).replace(/\(0x[0-9a-f]+.*$/, "").replace(/_QMLTYPE_\d+/, "");
        const what = item.text !== undefined && typeof item.text === "string" ? ` "${item.text.slice(0, 24)}"` : "";
        const when = atRest() ? "at rest" : "animating";
        const msg = `${name}${what} at ${r.x.toFixed(1)},${r.y.toFixed(1)} ${r.width.toFixed(1)}x${r.height.toFixed(1)} ${how}, box ${f.width.toFixed(1)}x${f.height.toFixed(1)}`;
        // One line per item, step and phase: the frames of one animation repeat the same overflow.
        const key = `${stepName} (${when}): ${name}${what}`;
        if (!failures.some(f => f.startsWith(key)))
            failures = failures.concat([`${key} | ${msg}`]);
    }

    Component.onCompleted: {
        start.start();
    }

    Timer {
        id: start

        interval: 500
        onTriggered: shell.next()
    }

    Timer {
        id: settle

        property int waited: 0

        interval: 50
        repeat: true
        onTriggered: {
            waited += interval;
            if (shell.surface === "launcher") {
                shell.updateLauncherStill();
                // A static scene draws no more frames, so once the box has settled a frame is forced for the
                // at-rest walk (the blinking cursor must not be what provides it).
                if (shell.launcherStill && shell.restWalks === 0)
                    kick.color = kick.color.toString() === "#808080" ? "#818181" : "#808080";
            }
            const done = shell.atRest() && (shell.surface !== "launcher" || shell.restWalks > 0) && (shell.surface !== "card" || shell.cardWalks > 0);
            if ((done && waited >= Theme.animMs + 150) || waited > 3000) {
                stop();
                if (shell.surface === "launcher" && shell.restWalks === 0) {
                    // The at-rest check cannot run at all: report it and end here rather than time out.
                    shell.failures = shell.failures.concat([`${shell.stepName}: no frame was checked with the box at rest`]);
                    shell.step = shell.steps.length - 1;
                } else if (shell.surface === "card" && shell.cardWalks === 0) {
                    // A card window that never draws ends the wait here, at the 3 s bound, as a failure.
                    shell.failures = shell.failures.concat([`${shell.stepName}: no card frame was checked`]);
                    shell.step = shell.steps.length - 1;
                }
                shell.next();
            }
        }
    }

    // The launcher's window: its box or the session screen, as the launcher window shows them (one at a time, by
    // Launcher.mode), at the scale in `ui`. The ink box is the caption box less its tab's headroom; the tab may cover
    // the outline. A box still growing or shrinking (the list's height eases) is not checked for being cut off.
    FloatingWindow {
        id: lwin

        visible: shell.surface === "launcher"
        implicitWidth: 1300
        implicitHeight: 1000
        color: "#808080"

        Connections {
            target: lhost.Window.window

            function onFrameSwapped() {
                if (shell.step < 0 || shell.surface !== "launcher")
                    return;
                const view = shell.launcherView();
                shell.updateLauncherStill();
                shell.frames += 1;
                for (const c of view.children) {
                    // The InkBox draws the outline and the shadow; its content is what is checked, inside its ink.
                    if (c.shadow !== undefined)
                        shell.walk(c.children[c.children.length - 1], false, view, view.headroom);
                    else
                        shell.walk(c, false, view, 0);
                }
                if (shell.atRest())
                    shell.restWalks += 1;
            }
        }

        Item {
            id: lhost

            anchors.fill: parent

            // Repainted by the settle timer to draw a frame of an otherwise static scene; not part of the check.
            Rectangle {
                id: kick

                x: parent.width - 4
                y: parent.height - 4
                width: 2
                height: 2
                color: "#808080"
            }

            LauncherMetrics {
                id: sizes

                ui: shell.ui
            }

            LauncherBox {
                id: lbox

                x: (parent.width - width) / 2
                y: 40
                metrics: sizes
                visible: Launcher.mode === "launcher"
            }

            SessionScreen {
                id: sbox

                x: (parent.width - width) / 2
                y: 40
                metrics: sizes
                visible: Launcher.mode === "session"
            }
        }
    }

    // A notification card, framed by an ink-wide margin: the card's own line under the row would touch the edge.
    FloatingWindow {
        id: cwin

        visible: shell.surface === "card"
        implicitWidth: 500
        implicitHeight: 300
        color: "#808080"

        Connections {
            target: chost.Window.window

            function onFrameSwapped() {
                if (shell.step < 0 || shell.cardExpect === "")
                    return;
                shell.frames += 1;
                shell.walk(ncard, false, chost, 0);
                shell.checkCard();
                shell.cardWalks += 1;
            }
        }

        Item {
            id: chost

            x: 20
            y: 20
            width: 420
            height: ncard.height + 2 * Theme.inkWidth

            NotificationCard {
                id: ncard

                x: Theme.inkWidth
                y: Theme.inkWidth
                width: parent.width - 2 * Theme.inkWidth
                rid: 1
                now: 1000000
            }
        }
    }

    FloatingWindow {
        id: win

        visible: shell.surface === "pill"
        implicitWidth: 1100
        implicitHeight: 360
        color: "#808080"

        Connections {
            target: stage.Window.window

            function onFrameSwapped() {
                if (shell.step < 0 || !box.visible)
                    return;
                shell.frames += 1;
                // The box's own outline and shadow are not content.
                shell.walk(collapsed, false);
                if (bubble.visible) {
                    // The canvas that draws the outline and the shadow, and the click area over the whole balloon,
                    // are not content.
                    for (const c of bubble.children)
                        if (c.getContext === undefined && c !== bubble.clickArea)
                            shell.walk(c, false, bubble, bubble.tailHeight);
                    if (shell.bubbleMaxH > 0 && bubble.height > shell.bubbleMaxH)
                        shell.fail(bubble, Qt.rect(0, 0, bubble.width, bubble.height), "too tall (buttons stacked?)", bubble);
                    // The click area and the hover belong to the balloon, not to the padded content in it: else the
                    // padding ring and the tail ignore clicks, and `inside` gets the wrong coordinates.
                    const area = bubble.clickArea;
                    if (area.parent !== bubble || Math.abs(area.width - bubble.width) > 0.5 || Math.abs(area.height - bubble.height) > 0.5)
                        shell.fail(area, Qt.rect(area.x, area.y, area.width, area.height), "click area is not the whole bubble", bubble);
                    if (bubble.hoverArea.parent !== bubble)
                        shell.fail(bubble, Qt.rect(0, 0, bubble.width, bubble.height), "hover handler is not on the bubble", bubble);
                    // The widest a bubble gets: the icon, a 320 px text column and the padding, with some room.
                    if (bubble.width > 410)
                        shell.fail(bubble, Qt.rect(0, 0, bubble.width, bubble.height), "too wide", bubble);
                }
            }
        }

        // pill/Pill.qml's sizing, for a face given by `set`.
        Item {
            id: stage

            property bool hidden: false
            property string activityId: ""
            property bool bubbleOn: false
            readonly property var view: ({
                    mode: hidden ? "hidden" : activityId !== "" ? "activity" : "idle"
                })
            readonly property var target: PillState.size(view, collapsed.restWidth + 2 * Theme.inkWidth, {
                w: collapsed.activityWidth + 2 * Theme.inkWidth,
                id: view.mode === "activity" ? activityId : ""
            }, Theme.pillHeight)
            property real drawW: target.w
            property real drawH: target.h

            function set(o) {
                hidden = o.hidden ?? false;
                activityId = o.id ?? "";
                bubbleOn = o.bubble ?? false;
            }

            anchors.fill: parent

            Behavior on drawW {
                Anim {}
            }
            Behavior on drawH {
                Anim {}
            }

            InkBox {
                id: box

                x: (parent.width - width) / 2
                y: 40
                width: stage.drawW
                height: stage.drawH
                visible: stage.drawH > 0

                Collapsed {
                    id: collapsed

                    activity: stage.view.mode === "activity"
                    activityId: stage.activityId
                    boxWidth: box.width
                    boxHeight: box.height
                }
            }

            Bubble {
                id: bubble

                x: box.x
                y: box.y + box.height + Theme.gap
                visible: stage.bubbleOn
                activityId: "notification"
            }
        }
    }
}
