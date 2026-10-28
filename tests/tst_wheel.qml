import QtQuick
import QtTest
import "../lib/wheel.js" as W

TestCase {
    name: "Wheel"

    function test_wholeNotch() {
        compare(W.accumulate(0, 120), { rest: 0, steps: 1 });
        compare(W.accumulate(0, -240), { rest: 0, steps: -2 });
    }

    // Review focus 3: hi-res wheels send fractions of a notch.
    function test_fractionsAccumulate() {
        let r = { rest: 0, steps: 0 };
        const steps = [];
        for (let i = 0; i < 8; i++) {
            r = W.accumulate(r.rest, 15);
            steps.push(r.steps);
        }
        compare(steps, [0, 0, 0, 0, 0, 0, 0, 1]);
        compare(r.rest, 0);
        compare(W.accumulate(90, 45), { rest: 15, steps: 1 });
    }

    // Review focus 3: reversing mid-gesture drops the old remainder instead of jumping.
    function test_reversalDropsRest() {
        compare(W.accumulate(100, -30), { rest: -30, steps: 0 });
        compare(W.accumulate(-100, 30), { rest: 30, steps: 0 });
    }

    function test_zeroDelta() {
        compare(W.accumulate(40, 0), { rest: 40, steps: 0 });
    }

    function test_verticalIsTheYDelta() {
        compare(W.vertical({ x: 0, y: 120 }), 120);
        compare(W.vertical({ x: 0, y: -120 }), -120);
    }

    function test_diagonalCountsWhileYIsAtLeastAsBigAsX() {
        compare(W.vertical({ x: 30, y: 120 }), 120);
        compare(W.vertical({ x: -60, y: -60 }), -60);
        compare(W.vertical({ x: 120, y: 30 }), 0);
    }

    function test_horizontalIsNoVerticalStep() {
        compare(W.vertical({ x: 120, y: 0 }), 0);
        compare(W.vertical({ x: -120, y: 0 }), 0);
        compare(W.vertical({ x: 0, y: 0 }), 0);
    }
}
