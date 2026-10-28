//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import qs.pill
import qs.services
import qs.theme

// The side-pill check (scripts/sides.sh): the real pill (pill/Pill.qml) with the music pill on its left and the Claude
// pill on its right, in turn with none, the left, the right and both, a long title, the island wider (a volume
// HUD, a track pop) and the panel open. After every frame drawn the island must be centred on the surface (the
// pills never move it), each pill must lie inside the surface and clear of the island by more than its shadow, the
// two pills must not meet, and nothing in a pill may be drawn outside its outline. Hovered, the island peeks (grows
// a little) and must still be centred, clear of the pills and inside the surface, and the pills must not move for it;
// a pill under the pointer peeks the same, and nothing else moves for that. The input item of a pill that
// is gone must be empty, so the window's mask covers only what shows.
ShellRoot {
    id: shell

    readonly property string longTitle: "A Considerably Longer Track Title Than Any Side Pill Should Ever Hold In One Line"
    readonly property real tolerance: 0.5
    property var failures: []
    property int frames: 0
    property int step: -1
    property string stepName: ""
    // What the step should end with: whether each pill shows (or is meant to).
    property bool wantLeft: false
    property bool wantRight: false
    // Where the pills stood (left edge in the window) at the last step that was not a hover, and the island's width then.
    property var restLeft: null
    property var restRight: null
    property real restIsland: 0
    property real restMusic: 0
    property real restClaude: 0
    // Whether the step only hovers or unhovers the island of the one before: its pills stay where they were.
    property bool wantSame: false
    property string wantPeek: ""
    property string prevPeek: ""

    readonly property var steps: [
        {
            name: "none",
            run: () => set({}),
            left: false,
            right: false
        },
        {
            name: "left only",
            run: () => set({ music: true }),
            left: true,
            right: false
        },
        {
            name: "right only, working",
            run: () => set({ agent: "working" }),
            left: false,
            right: true
        },
        {
            name: "right only, waiting",
            run: () => set({ agent: "waiting" }),
            left: false,
            right: true
        },
        {
            name: "both",
            run: () => set({ music: true, agent: "working" }),
            left: true,
            right: true
        },
        {
            name: "both, long title and artist",
            run: () => set({ music: true, long: true, agent: "working" }),
            left: true,
            right: true
        },
        {
            name: "left only, long title",
            run: () => set({ music: true, long: true }),
            left: true,
            right: false
        },
        {
            name: "both, an hour of work",
            run: () => set({ music: true, agent: "working", worked: 3725000 }),
            left: true,
            right: true
        },
        {
            name: "both, volume HUD on the island",
            run: () => {
                set({ music: true, long: true, agent: "working" });
                Activities.show("volume", 100, 0, "");
            },
            left: true,
            right: true
        },
        {
            name: "both, track pop on the island",
            run: () => {
                Activities.hide("volume");
                Activities.show("track", 50, 0, "music");
            },
            left: true,
            right: true
        },
        {
            name: "both, back to rest",
            run: () => Activities.hide("track"),
            left: true,
            right: true
        },
        {
            name: "both, island hovered",
            run: () => hoverOn("island"),
            left: true,
            right: true,
            same: true,
            peek: "island"
        },
        {
            name: "both, island unhovered",
            run: () => hoverOn(""),
            left: true,
            right: true,
            same: true,
            peek: ""
        },
        {
            name: "both, music pill hovered",
            run: () => hoverOn("music"),
            left: true,
            right: true,
            same: true,
            peek: "music"
        },
        {
            name: "both, Claude pill hovered",
            run: () => hoverOn("agents"),
            left: true,
            right: true,
            same: true,
            peek: "agents"
        },
        {
            name: "both, nothing hovered",
            run: () => hoverOn(""),
            left: true,
            right: true,
            same: true,
            peek: ""
        },
        {
            name: "both, long title, hovered, volume HUD",
            run: () => {
                Activities.show("volume", 100, 0, "");
                hoverOn("island");
            },
            left: true,
            right: true,
            peek: "island"
        },
        {
            name: "both, long title, hovered, back to rest",
            run: () => Activities.hide("volume"),
            left: true,
            right: true,
            peek: "island"
        },
        {
            name: "both, unhovered again",
            run: () => hoverOn(""),
            left: true,
            right: true
        },
        {
            name: "panel open",
            run: () => PillControl.openOn(pill.screenName, "calendar"),
            left: false,
            right: false
        },
        {
            name: "panel closed again",
            run: () => PillControl.close(),
            left: true,
            right: true
        },
        {
            name: "none again",
            run: () => set({}),
            left: false,
            right: false
        },
        {
            name: "left only, hovered",
            run: () => {
                set({ music: true });
                hoverOn("island");
            },
            left: true,
            right: false,
            peek: "island"
        },
        {
            name: "none, hovered",
            run: () => set({ hover: true }),
            left: false,
            right: false,
            peek: "island"
        },
        {
            name: "none, unhovered",
            run: () => set({}),
            left: false,
            right: false
        }
    ]

    // The pointer on the island ("island"), a pill ("music", "agents") or nothing (""), as the pill's hover would say.
    function hoverOn(where) {
        pill.pointerOn = where;
        pill.hovered = where !== "";
    }

    // The services' state for a step: `music`, `long` (title and artist), `agent` ("working" or "waiting") and
    // `worked` (ms the agent has worked), `hover` (the island is hovered).
    function set(o) {
        hoverOn(o.hover ? "island" : "");
        Media.playing = o.music ?? false;
        Media.title = o.long ? longTitle : "Song";
        Media.artist = o.long ? "An Artist With A Rather Long Name Too" : "Band";
        Agents.now = Date.now();
        Agents.items = o.agent ? [
            {
                status: o.agent,
                cwd: "/home/d/p",
                tool: "Bash",
                promptAt: Agents.now - (o.worked ?? 433000)
            }
        ] : [];
    }

    // Every failure once, however many frames it lasts.
    function fail(message) {
        const line = `${stepName}: ${message}`;
        if (failures.indexOf(line) === -1)
            failures.push(line);
    }

    // The first item under `item` (itself included) that `matches`.
    function find(item, matches) {
        if (matches(item))
            return item;
        for (const child of item.children) {
            const found = find(child, matches);
            if (found)
                return found;
        }
        return null;
    }

    // A pill's content (its own outline, shadow and keyline are not content): the item with a `model` and `active`.
    function content(input) {
        return find(input, i => i.model !== undefined && i.active !== undefined);
    }

    // A box as { l, r } across the window; null while it has no width.
    function span(item, shadow) {
        const w = item.width - (shadow ? Theme.shadowOffset : 0);
        if (w <= 0)
            return null;
        const left = item.mapToItem(null, 0, 0).x;
        return { l: left, r: left + w };
    }

    // Every painting item under `item` that is shown must lie inside `box` (window coordinates).
    function inside(item, box, name) {
        if (!item.visible || item.opacity === 0)
            return;
        if (item.width > 0 && item.height > 0 && ((item.contentWidth !== undefined && item.elide !== undefined) || (item.border !== undefined && item.color !== undefined))) {
            const p = item.mapToItem(null, 0, 0);
            if (p.x < box.l - tolerance || p.x + item.width > box.r + tolerance)
                fail(`${name}: ${item.toString()} spans ${p.x.toFixed(1)}..${(p.x + item.width).toFixed(1)} outside ${box.l.toFixed(1)}..${box.r.toFixed(1)}`);
        }
        for (const c of item.children)
            inside(c, box, name);
    }

    function checkFrame() {
        const ink = Theme.inkWidth;
        const edge = Theme.shadowOffset + Theme.shadowKeyline;
        // The clearance kept for a fully peeked island: the pills never move for a hover.
        const gap = Theme.gap / 2 + edge;
        const island = span(pill.inputItem, true);
        const surface = { l: pill.mapToItem(null, 0, 0).x, r: pill.mapToItem(null, pill.width, 0).x };
        const centre = (surface.l + surface.r) / 2;
        if (island) {
            const off = (island.l + island.r) / 2 - centre;
            if (Math.abs(off) > tolerance)
                fail(`island is ${off.toFixed(2)} px off the surface's centre`);
        }
        const left = span(pill.musicInput, true);
        const right = span(pill.claudeInput, true);
        if (left && island) {
            if (left.r + gap > island.l + tolerance)
                fail(`music pill ends ${left.r.toFixed(1)}, too close to the island at ${island.l.toFixed(1)}`);
            if (left.l < surface.l + edge - tolerance)
                fail(`music pill starts at ${left.l.toFixed(1)}, outside the surface (${(surface.l + edge).toFixed(1)})`);
        }
        if (right && island) {
            if (right.l < island.r + gap - tolerance)
                fail(`Claude pill starts ${right.l.toFixed(1)}, too close to the island ending ${island.r.toFixed(1)}`);
            if (right.r + Theme.shadowOffset > surface.r - edge + Theme.shadowOffset + tolerance)
                fail(`Claude pill ends at ${right.r.toFixed(1)}, outside the surface (${(surface.r - edge).toFixed(1)})`);
        }
        if (wantSame) {
            // A pill that peeks grows by half the peek on each side, so its left edge moves that far; no other pill moves.
            // (Also while it is still unpeeking from the step before.)
            const half = wantPeek === "music" || prevPeek === "music" ? 16 : 0;
            const halfClaude = wantPeek === "agents" || prevPeek === "agents" ? 16 : 0;
            if (left && restLeft !== null && Math.abs(left.l - restLeft) > half + tolerance)
                fail(`music pill moved from ${restLeft.toFixed(1)} to ${left.l.toFixed(1)} for the hover`);
            if (right && restRight !== null && Math.abs(right.l - restRight) > halfClaude + tolerance)
                fail(`Claude pill moved from ${restRight.toFixed(1)} to ${right.l.toFixed(1)} for the hover`);
        }
        if (left && right && left.r + Theme.shadowOffset > right.l)
            fail("the side pills meet");
        // A pill folding away for the panel is cut off at its outline by its box, which is narrower each frame.
        if (!pill.sidesAllowed)
            return;
        if (left)
            inside(content(pill.musicInput), { l: left.l + ink, r: left.r - ink }, "music pill");
        if (right)
            inside(content(pill.claudeInput), { l: right.l + ink, r: right.r - ink }, "Claude pill");
    }

    // Once the pills have settled: each one shows or is gone, as the step says.
    function checkSettled() {
        const shown = (item, name, want) => {
            const has = item.width > 0;
            if (has !== want)
                fail(`${name} ${has ? "shows" : "is gone"}, expected ${want ? "it to show" : "it gone"}`);
            if (!has && item.height !== 0)
                fail(`${name} is gone but its input item is ${item.height} px high`);
        };
        shown(pill.musicInput, "music pill", wantLeft);
        shown(pill.claudeInput, "Claude pill", wantRight);
        const island = span(pill.inputItem, true);
        const peeked = pill.drawW - pill.baseW;
        const wantIsland = wantPeek === "island";
        if (Math.abs(peeked - (wantIsland ? 32 : 0)) > tolerance)
            fail(`the island has peeked by ${peeked.toFixed(1)} px, expected ${wantIsland ? 32 : 0}`);
        if (Math.abs(pill.drawH - pill.baseH - (wantIsland ? 6 : 0)) > tolerance)
            fail(`the island is ${(pill.drawH - pill.baseH).toFixed(1)} px taller than its face for the peek, expected ${wantIsland ? 6 : 0}`);
        if (wantSame && Math.abs(island.r - island.l - restIsland - (wantIsland ? 32 : 0)) > tolerance)
            fail(`the island is ${(island.r - island.l).toFixed(1)} px wide, expected ${restIsland + (wantIsland ? 32 : 0)}`);
        // A pill peeks by the same as the island, in width and in height, only while the pointer is on it.
        const l = span(pill.musicInput, true);
        const r = span(pill.claudeInput, true);
        if (wantSame) {
            if (l && Math.abs(l.r - l.l - restMusic - (wantPeek === "music" ? 32 : 0)) > tolerance)
                fail(`the music pill is ${(l.r - l.l).toFixed(1)} px wide, expected ${restMusic + (wantPeek === "music" ? 32 : 0)}`);
            if (r && Math.abs(r.r - r.l - restClaude - (wantPeek === "agents" ? 32 : 0)) > tolerance)
                fail(`the Claude pill is ${(r.r - r.l).toFixed(1)} px wide, expected ${restClaude + (wantPeek === "agents" ? 32 : 0)}`);
            const tall = (box, peek) => Math.abs(box.height - Theme.shadowOffset - (Theme.pillTop + Theme.pillHeight / 2) - (Theme.pillHeight + (wantPeek === peek ? 6 : 0)) / 2) > tolerance;
            if (l && tall(pill.musicInput, "music"))
                fail(`the music pill's input item is ${pill.musicInput.height.toFixed(1)} px high for the peek`);
            if (r && tall(pill.claudeInput, "agents"))
                fail(`the Claude pill's input item is ${pill.claudeInput.height.toFixed(1)} px high for the peek`);
        }
        if (!wantSame) {
            restLeft = l ? l.l : null;
            restRight = r ? r.l : null;
            restMusic = l ? l.r - l.l : 0;
            restClaude = r ? r.r - r.l : 0;
            restIsland = island.r - island.l - peeked;
        }
        console.log(`sides: ${stepName}: island ${pill.inputItem.width - Theme.shadowOffset} px, music ${Math.max(0, pill.musicInput.width - Theme.shadowOffset)} px, Claude ${Math.max(0, pill.claudeInput.width - Theme.shadowOffset)} px`);
    }

    function next() {
        step += 1;
        if (step >= steps.length) {
            for (const f of failures)
                console.log("sides: FAIL: " + f);
            console.log(failures.length === 0 ? `sides: OK (${steps.length} steps, ${frames} frames checked)` : `sides: FAIL (${failures.length} problems)`);
            Qt.quit();
            return;
        }
        stepName = steps[step].name;
        wantLeft = steps[step].left;
        wantRight = steps[step].right;
        wantSame = steps[step].same ?? false;
        prevPeek = wantPeek;
        wantPeek = steps[step].peek ?? "";
        steps[step].run();
        settle.restart();
    }

    FloatingWindow {
        id: win

        implicitWidth: 1100
        implicitHeight: 520
        color: "#808080"

        Connections {
            target: pill.Window.window

            function onFrameSwapped() {
                if (shell.step < 0)
                    return;
                shell.frames += 1;
                shell.checkFrame();
            }
        }

        Pill {
            id: pill

            x: (parent.width - width) / 2
            width: implicitWidth
            height: implicitHeight
            screenName: "sides"
            screen: Quickshell.screens[0]
        }
    }

    // Time for every box to settle (an animation is Theme.animMs, a pill's reveal and the island's size each one).
    Timer {
        id: settle

        interval: 5 * Theme.animMs

        onTriggered: {
            shell.checkSettled();
            shell.next();
        }
    }

    Timer {
        interval: 800
        running: true
        onTriggered: shell.next()
    }
}
