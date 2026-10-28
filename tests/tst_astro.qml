import QtQuick
import QtTest
import "../lib/astro.js" as A

TestCase {
    name: "Astro"

    readonly property real dayStart: new Date(2026, 9, 14).getTime()

    function at(h, m) {
        return dayStart + (h * 60 + m) * 60000;
    }

    function today() {
        return { sunrise: { ms: at(7, 41), text: "07:41" }, sunset: { ms: at(18, 22), text: "18:22" } };
    }

    function tomorrow() {
        return { sunrise: { ms: at(24 + 7, 43), text: "07:43" } };
    }

    function test_moonPhaseKnownDates() {
        const n = A.moonPhase(new Date(Date.UTC(2024, 3, 8, 18, 21)));
        compare(n.name, "New moon");
        verify(n.illumination <= 1);
        const q = A.moonPhase(new Date(Date.UTC(2024, 3, 15, 19, 13)));
        compare(q.name, "First quarter");
        verify(q.illumination >= 40 && q.illumination <= 60);
        const f = A.moonPhase(new Date(Date.UTC(2024, 3, 23, 23, 49)));
        compare(f.name, "Full moon");
        verify(f.illumination >= 99);
    }

    // Dates before the reference new moon must wrap, not go negative.
    function test_moonPhaseBeforeReference() {
        compare(A.moonPhase(new Date(Date.UTC(1999, 11, 22, 17, 31))).name, "Full moon");
    }

    function test_span() {
        compare(A.span(40 * 60000), "40 m");
        compare(A.span(2 * 3600000), "2 h");
        compare(A.span((10 * 60 + 41) * 60000), "10 h 41 m");
        compare(A.span(-5000), "0 m");
    }

    function test_daylightAfterSunrise() {
        const d = A.daylight(at(17, 42), dayStart, today(), tomorrow());
        compare(d.caption, "10 h 41 m · sets in 40 m");
        compare(d.next, { label: "Sunset", text: "18:22" });
        compare(Math.round(d.rise * 1000), 320);
        compare(Math.round(d.set * 1000), 765);
    }

    function test_daylightBeforeSunrise() {
        const d = A.daylight(at(6, 0), dayStart, today(), tomorrow());
        compare(d.caption, "10 h 41 m · rises in 1 h 41 m");
        compare(d.next, { label: "Sunrise", text: "07:41" });
    }

    function test_daylightAfterSunsetUsesTomorrow() {
        const d = A.daylight(at(20, 0), dayStart, today(), tomorrow());
        compare(d.caption, "10 h 41 m · rises in 11 h 43 m");
        compare(d.next, { label: "Sunrise", text: "07:43" });
    }

    function test_daylightAfterSunsetWithoutTomorrow() {
        const d = A.daylight(at(20, 0), dayStart, today(), null);
        compare(d.caption, "10 h 41 m");
        compare(d.next, null);
    }

    // Review focus 2: no weather yet → track and now dot only.
    function test_daylightWithoutSunData() {
        const d = A.daylight(at(12, 0), dayStart, null, null);
        compare(d.rise, null);
        compare(d.set, null);
        compare(d.caption, "");
        compare(d.next, null);
        compare(Math.round(d.now * 1000), 500);
        compare(A.daylight(at(12, 0), dayStart, { sunrise: null, sunset: null }, null).rise, null);
    }
}
