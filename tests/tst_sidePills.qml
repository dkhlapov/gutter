import QtQuick
import QtTest
import "../lib/sidePills.js" as S

TestCase {
    name: "SidePills"

    function test_musicOnlyWhilePlaying() {
        compare(S.music({ playing: false, title: "Song", artist: "Band" }), null);
        compare(S.music({ playing: true, title: "Song", artist: "Band" }), { title: "Song", artist: "Band" });
    }

    // A player that plays without telling what: the pill still shows, with a stand-in title.
    function test_musicWithoutTitle() {
        compare(S.music({ playing: true, title: "", artist: "" }), { title: "Playing", artist: "" });
    }

    function session(status, promptAt) {
        return { status, promptAt: promptAt ?? 0 };
    }

    function test_agentNoneWhenNothingRuns() {
        compare(S.agent([], 1000), null);
        compare(S.agent([session("done"), session("idle")], 1000), null);
    }

    function test_agentWorkingCountsFromItsPrompt() {
        compare(S.agent([session("working", 4000)], 9000), { kind: "working", elapsed: 5000 });
    }

    // Several at work: the one that has been working longest sets the time.
    function test_agentWorkingTakesTheOldestPrompt() {
        compare(S.agent([session("working", 8000), session("working", 3000), session("done")], 9000), { kind: "working", elapsed: 6000 });
    }

    function test_agentWorkingWithoutPromptTime() {
        compare(S.agent([session("working", 0)], 9000), { kind: "working", elapsed: -1 });
    }

    function test_agentWaitingBeatsWorking() {
        compare(S.agent([session("working", 4000), session("waiting", 2000)], 9000), { kind: "waiting", elapsed: -1 });
    }

    function test_agentLabel() {
        compare(S.agentLabel({ kind: "working", elapsed: 125000 }), "2:05");
        compare(S.agentLabel({ kind: "working", elapsed: 3725000 }), "1:02:05");
        compare(S.agentLabel({ kind: "working", elapsed: -1 }), "");
        compare(S.agentLabel({ kind: "waiting", elapsed: -1 }), "waiting");
    }

    readonly property int surface: 1010 + 2 * 9
    readonly property int gap: 8 + 9

    function lay(islandW, left, right) {
        return S.layout(surface, islandW, gap, 9, { left, right });
    }

    // A pill that asks for less than the room keeps its width and sits a gap away from the island.
    function test_layoutBesideTheIsland() {
        const l = lay(300, 200, 150);
        compare(l.leftW, 200);
        compare(l.rightW, 150);
        const islandX = (surface - 300) / 2;
        compare(l.leftX, islandX - gap - 200);
        compare(l.rightX, islandX + 300 + gap);
    }

    function test_layoutAbsentSideTakesNothing() {
        compare(lay(300, 0, 150).leftW, 0);
        compare(lay(300, 200, 0).rightW, 0);
    }

    // Both sides are capped to the same room, so a long title on one side never squeezes the other.
    function test_layoutCapsBothSides() {
        const l = lay(420, 900, 900);
        compare(l.leftW, l.rightW);
        verify(l.leftW <= S.SIDE_MAX_W);
        verify(l.leftW > 0);
    }

    // Nothing is drawn outside the surface, for every island width up to the widest face at rest, and no side
    // pill reaches into the island or its gap.
    function test_layoutStaysInsideTheSurface() {
        for (let w = 100; w <= 420; w += 20) {
            const l = lay(w, 900, 900);
            const islandX = (surface - w) / 2;
            verify(l.leftX >= 9, `left edge at ${w}`);
            verify(l.leftX + l.leftW + gap <= islandX + 1e-9, `left clear of the island at ${w}`);
            verify(l.rightX >= islandX + w + gap - 1e-9, `right clear of the island at ${w}`);
            verify(l.rightX + l.rightW <= surface - 9 + 1e-9, `right edge at ${w}`);
        }
    }

    // An island as wide as the surface (the panel) leaves no room.
    function test_layoutNoRoomWhenOpen() {
        const l = lay(1010, 200, 200);
        compare(l.leftW, 0);
        compare(l.rightW, 0);
    }

    // The pointer is on one box at a time; the island wins if the boxes ever overlap.
    function test_pointerOn() {
        compare(S.pointerOn(false, false, false), "");
        compare(S.pointerOn(true, false, false), "island");
        compare(S.pointerOn(false, true, false), "music");
        compare(S.pointerOn(false, false, true), "agents");
        compare(S.pointerOn(true, false, true), "island");
    }
}
