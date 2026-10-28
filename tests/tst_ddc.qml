import QtQuick
import QtTest
import "../lib/ddc.js" as Ddc

TestCase {
    name: "Ddc"

    readonly property string detect: "Display 1\n   I2C bus:          /dev/i2c-9\n   DRM connector:    card1-DP-1\n   drm_connector_id: 449\n   Monitor:          AOC:Q27G4:2S6S6HA007872\n\nDisplay 2\n   I2C bus:          /dev/i2c-10\n   DRM connector:    card1-DP-2\n   drm_connector_id: 459\n   Monitor:          PHL:27M2N5500:UK02510044376\n\nInvalid display\n   I2C bus:          /dev/i2c-4\n"

    function test_parseDetect() {
        compare(Ddc.parseDetect(detect), [{ bus: "9", connector: "DP-1" }, { bus: "10", connector: "DP-2" }]);
        compare(Ddc.parseDetect(""), []);
    }

    function test_parseLevels() {
        compare(Ddc.parseLevels("9 VCP 10 C 50 100\n10 VCP 10 C 100 100\n"), { "9": 0.5, "10": 1 });
        compare(Ddc.parseLevels("9 VCP 10 ERR\ngarbage\n"), {});
    }

    function test_readCommand() {
        compare(Ddc.readCommand(["9", "10"]), "ddcutil -b 9 getvcp 10 --brief | sed 's/^/9 /'; ddcutil -b 10 getvcp 10 --brief | sed 's/^/10 /'");
        compare(Ddc.readCommand(["9; rm -rf ~"]), "");
    }

    function test_step() {
        compare(Ddc.step(0.5, 0.05), 0.55);
        compare(Ddc.step(0.98, 0.05), 1);
        compare(Ddc.step(0.02, -0.05), 0);
    }

    // Review focus 5: one ddcutil write per monitor at a time; the latest value wins.
    function test_serialWriterLatestWins() {
        let r = Ddc.request({}, "DP-2", 0.55);
        compare(r.start, 0.55);
        r = Ddc.request(r.state, "DP-2", 0.6);
        compare(r.start, null);
        r = Ddc.request(r.state, "DP-2", 0.65);
        compare(r.start, null);
        r = Ddc.finished(r.state, "DP-2");
        compare(r.start, 0.65);
        r = Ddc.finished(r.state, "DP-2");
        compare(r.start, null);
        compare(Ddc.request(r.state, "DP-2", 0.7).start, 0.7);
    }

    function test_serialWriterMonitorsIndependent() {
        let r = Ddc.request({}, "DP-1", 0.5);
        r = Ddc.request(r.state, "DP-2", 0.4);
        compare(r.start, 0.4);
    }

    // Review focus 4: a re-read must not overwrite a value that is still being written.
    function test_mergeReadKeepsValuesBeingWritten() {
        let w = Ddc.request({}, "DP-2", 0.8).state;
        compare(Ddc.mergeRead({ "DP-1": 0.5, "DP-2": 0.8 }, { "DP-1": 0.3, "DP-2": 0.4 }, w), { "DP-1": 0.3, "DP-2": 0.8 });
        w = Ddc.request(w, "DP-2", 0.9).state; // queued behind the running write
        compare(Ddc.mergeRead({ "DP-2": 0.9 }, { "DP-2": 0.4 }, w), { "DP-2": 0.9 });
        w = Ddc.finished(w, "DP-2").state; // 0.9 now running
        w = Ddc.finished(w, "DP-2").state; // idle
        compare(Ddc.mergeRead({ "DP-2": 0.9 }, { "DP-2": 0.4 }, w), { "DP-2": 0.4 });
    }

    function test_mergeReadKeepsUnreadMonitors() {
        compare(Ddc.mergeRead({ "DP-1": 0.5 }, {}, {}), { "DP-1": 0.5 });
        compare(Ddc.mergeRead({}, { "DP-1": 0.7 }, {}), { "DP-1": 0.7 });
    }

    // Read started, then a write ran and finished before the read returned: the read is older than the write.
    function test_mergeReadSkipsMonitorsWrittenDuringRead() {
        compare(Ddc.mergeRead({ "DP-1": 0.5, "DP-2": 0.9 }, { "DP-1": 0.3, "DP-2": 0.4 }, {}, { "DP-2": true }), { "DP-1": 0.3, "DP-2": 0.9 });
    }
}
