import QtQuick
import QtTest
import "../lib/volume.js" as V

TestCase {
    name: "Volume"

    function test_firstReadIsNotAChange() {
        const r = V.update(V.createTracker(), 42, 0.5, false);
        compare(r.changed, false);
        compare(r.tracker.volume, 0.5);
    }

    function test_volumeChangeOnSameSink() {
        const t = V.update(V.createTracker(), 42, 0.5, false).tracker;
        compare(V.update(t, 42, 0.55, false).changed, true);
    }

    function test_muteChangeOnSameSink() {
        const t = V.update(V.createTracker(), 42, 0.5, false).tracker;
        compare(V.update(t, 42, 0.5, true).changed, true);
    }

    function test_sinkSwitchIsNotAChange() {
        const t = V.update(V.createTracker(), 42, 0.5, false).tracker;
        compare(V.update(t, 43, 0.9, false).changed, false);
    }

    function test_subPercentNoiseIgnored() {
        const t = V.update(V.createTracker(), 42, 0.5, false).tracker;
        compare(V.update(t, 42, 0.5001, false).changed, false);
    }

    function test_stepClampsAndRounds() {
        compare(V.step(0.5, 1), 0.55);
        compare(V.step(0.98, 1), 1);
        compare(V.step(0.02, -1), 0);
        compare(V.step(0.5, -2), 0.4);
    }

    function test_icon() {
        compare(V.icon(0.7, false), "volume_up");
        compare(V.icon(0.3, false), "volume_down");
        compare(V.icon(0, false), "volume_mute");
        compare(V.icon(0.7, true), "volume_off");
    }

    // Off-grid volumes (set elsewhere) snap to the 5 % grid in the direction of travel.
    function test_stepSnapsToGrid() {
        compare(V.step(0.52, 1), 0.55);
        compare(V.step(0.52, -1), 0.5);
        compare(V.step(0.57, 2), 0.65);
        compare(V.step(0.5, 0), 0.5);
        compare(V.step(0.03, -1), 0);
    }
}
