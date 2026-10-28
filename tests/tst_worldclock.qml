import QtQuick
import QtTest
import "../lib/worldclock.js" as C

TestCase {
    name: "WorldClock"

    // Review focus 5: zones reach `sh` only as positional arguments, and only when they look like zoneinfo names.
    function test_validZone() {
        verify(C.validZone("UTC"));
        verify(C.validZone("America/New_York"));
        verify(C.validZone("America/Argentina/Buenos_Aires"));
        verify(C.validZone("Etc/GMT+5"));
        verify(!C.validZone("../../etc/passwd"));
        verify(!C.validZone("/etc/localtime"));
        verify(!C.validZone("Europe/London; rm -rf ~"));
        verify(!C.validZone(""));
        verify(!C.validZone(42));
    }

    function test_command() {
        const cmd = C.command(["UTC", "../x"]);
        compare(cmd.slice(0, 2), ["sh", "-c"]);
        compare(cmd.slice(3), ["sh", "UTC", "invalid"]);
    }

    function test_parseOffset() {
        compare(C.parseOffset("+0200"), 120);
        compare(C.parseOffset("-0600\n"), -360);
        compare(C.parseOffset("+0530"), 330);
        compare(C.parseOffset("+0000"), 0);
        compare(C.parseOffset("invalid"), null);
        compare(C.parseOffset(""), null);
    }

    // Review focus 5: an unknown zone yields null for that clock only.
    function test_parseOffsets() {
        compare(C.parseOffsets("+0200\n-0400\ninvalid\n+0000\n", 3), { local: 120, zones: [-240, null, 0] });
        compare(C.parseOffsets("+0200\n", 2), { local: 120, zones: [null, null] });
    }

    function test_timeAtCrossesMidnight() {
        const now = Date.UTC(2026, 9, 14, 15, 42);
        compare(C.timeAt(now, 0), "15:42");
        compare(C.timeAt(now, 540), "00:42");
        compare(C.timeAt(now, -240), "11:42");
        compare(C.timeAt(Date.UTC(2026, 9, 14, 0, 30), -60), "23:30");
        compare(C.timeAt(now, 330), "21:12");
    }

    function test_relative() {
        compare(C.relative(-240, 120), "−6 h");
        compare(C.relative(540, 120), "+7 h");
        compare(C.relative(330, 120), "+3 h 30 m");
        compare(C.relative(120, 120), "0 h");
    }

    // "America" is a directory under zoneinfo; only regular files are zones (else TZ falls back to UTC).
    function test_scriptAcceptsOnlyZoneFiles() {
        verify(C.SCRIPT.indexOf('[ -f "/usr/share/zoneinfo/$z" ]') !== -1);
    }

    // Tile data without the time, so the Calendar's per-second clock does not rebuild the tiles.
    function test_tiles() {
        const clocks = [{ label: "London", tz: "Europe/London" }, { label: "Bad", tz: "Europe/Londn" }];
        compare(C.tiles(clocks, [60, null], 120), [
            { label: "London", offsetMin: 60, relative: "−1 h" },
            { label: "Bad", offsetMin: null, relative: "" }
        ]);
        compare(C.tiles(clocks, [60], null)[0].relative, "");
    }

    // Just after each UTC quarter hour, when zones switch DST.
    function test_msToNextRefresh() {
        const q = 15 * 60 * 1000;
        compare(C.msToNextRefresh(0), q + 2000);
        compare(C.msToNextRefresh(q - 1000), 3000);
        compare(C.msToNextRefresh(10 * q + 60000), q - 60000 + 2000);
    }
}
