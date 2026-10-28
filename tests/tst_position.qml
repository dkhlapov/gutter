import QtQuick
import QtTest
import "../lib/position.js" as P

TestCase {
    name: "Position"

    function test_anchorFromTakesTheMidpoint() {
        compare(P.anchorFrom(12.5, 1000, 1040), { seconds: 12.5, atMs: 1020 });
    }

    function test_positionAtExtrapolatesWhilePlaying() {
        const a = { seconds: 10, atMs: 5000 };
        compare(P.positionAt(a, 5000, true, 0), 10);
        compare(P.positionAt(a, 7500, true, 0), 12.5);
    }

    function test_positionAtHoldsWhilePaused() {
        compare(P.positionAt({ seconds: 10, atMs: 5000 }, 99000, false, 0), 10);
    }

    function test_positionAtNeverGoesBackwardsOrPastTheLength() {
        const a = { seconds: 10, atMs: 5000 };
        compare(P.positionAt(a, 4000, true, 0), 10);
        compare(P.positionAt(a, 50000, true, 30), 30);
        compare(P.positionAt(a, 50000, true, 0), 55);
    }

    function test_positionAtAfterTrackChangeStartsFromZeroNotTheOldTrack() {
        // A new track is anchored at 0 when it starts; the old track's position does not carry over.
        compare(P.positionAt({ seconds: 0, atMs: 1000 }, 4000, true, 200), 3);
    }

    function test_parseBusctl() {
        compare(P.parseBusctl("x 59279759\n"), 59.279759);
        compare(P.parseBusctl("x 0"), 0);
        compare(P.parseBusctl("x -5"), null);
        compare(P.parseBusctl("Failed to get property Position"), null);
        compare(P.parseBusctl(""), null);
        compare(P.parseBusctl(undefined), null);
    }
}
