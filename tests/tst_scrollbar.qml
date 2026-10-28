import QtQuick
import QtTest
import "../lib/scrollbar.js" as S

TestCase {
    name: "Scrollbar"

    function test_neededOnlyWhenContentOverflows() {
        verify(!S.needed(300, 300));
        verify(!S.needed(300, 200));
        verify(!S.needed(0, 500));
        verify(S.needed(300, 301));
    }

    function test_thumbIsTheVisibleShareOfTheTrack() {
        compare(S.thumb(100, 400, 0, 200, 20), { length: 50, offset: 0 });
        // Halfway through the 300 px of scroll range: half of the 150 px the thumb can move.
        compare(S.thumb(100, 400, 150, 200, 20), { length: 50, offset: 75 });
        compare(S.thumb(100, 400, 300, 200, 20), { length: 50, offset: 150 });
    }

    function test_thumbHasAMinimumLength() {
        compare(S.thumb(100, 100000, 0, 200, 24).length, 24);
    }

    function test_nothingToScrollFillsTheTrack() {
        compare(S.thumb(100, 100, 0, 200, 20), { length: 200, offset: 0 });
    }

    function test_overshootStaysInsideTheTrack() {
        compare(S.thumb(100, 400, -40, 200, 20).offset, 0);
        compare(S.thumb(100, 400, 340, 200, 20).offset, 150);
    }

    function test_posAtInvertsThumb() {
        for (const pos of [0, 37, 150, 299, 300]) {
            const t = S.thumb(100, 400, pos, 200, 20);
            fuzzyCompare(S.posAt(100, 400, t.offset, 200, 20), pos, 1e-9);
        }
        compare(S.posAt(100, 400, -10, 200, 20), 0);
        compare(S.posAt(100, 400, 999, 200, 20), 300);
        compare(S.posAt(100, 100, 50, 200, 20), 0);
    }
}
