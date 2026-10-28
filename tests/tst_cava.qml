import QtQuick
import QtTest
import "../lib/cava.js" as C

TestCase {
    name: "Cava"

    function test_parseFrame() {
        compare(C.parseFrame("0;500;1000;", 3), [0, 0.5, 1]);
        // Without the trailing delimiter too.
        compare(C.parseFrame("0;500;1000", 3), [0, 0.5, 1]);
    }

    function test_parseFrameBadInput() {
        compare(C.parseFrame("", 3), [0, 0, 0]);
        compare(C.parseFrame(undefined, 3), [0, 0, 0]);
        compare(C.parseFrame("a;b", 3), [0, 0, 0]);
        // A short frame is a torn read, not a frame.
        compare(C.parseFrame("500;500", 3), [0, 0, 0]);
        compare(C.parseFrame("500;x;500;", 3), [0, 0, 0]);
    }

    function test_parseFrameClamps() {
        compare(C.parseFrame("2000;0;0", 3), [1, 0, 0]);
        compare(C.parseFrame("-5;0;0", 3), [0, 0, 0]);
    }

    function test_parseFrameLongerThanBars() {
        compare(C.parseFrame("1000;1000;1000;1000;", 2), [1, 1]);
    }

    function test_config() {
        const c = C.config(24, 30);
        verify(c.indexOf("bars = 24") >= 0);
        verify(c.indexOf("framerate = 30") >= 0);
        verify(c.indexOf("method = pipewire") >= 0);
        verify(c.indexOf("source = auto") >= 0);
        verify(c.indexOf("[output]") >= 0);
        verify(c.indexOf("method = raw") >= 0);
        verify(c.indexOf("data_format = ascii") >= 0);
        verify(c.indexOf("ascii_max_range = 1000") >= 0);
        verify(c.indexOf("bar_delimiter = 59") >= 0);
        verify(c.indexOf("frame_delimiter = 10") >= 0);
    }
}
