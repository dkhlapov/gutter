import QtQuick
import QtTest
import "../lib/themeMode.js" as M

// Zones whose DST changes at midnight, where the local midnight does not exist (or happens twice). Atlantic/Azores,
// 2026: on 29 March the clocks jump from 00:00 (-01) to 01:00 (+00), so the day starts at 01:00Z; on 25 October
// 01:00Z (+00, 01:00) falls back to 00:00 (-01), so 00:00-00:59 happens twice. scripts/test.sh runs this file once
// with TZ=Atlantic/Azores; in any other zone it skips.
TestCase {
    name: "ThemeModeAzores"

    function azores() {
        if (new Date(Date.UTC(2026, 2, 29, 0, 30)).getHours() !== 23 || new Date(Date.UTC(2026, 2, 29, 1, 0)).getHours() !== 1
                || new Date(Date.UTC(2026, 9, 25, 1, 0)).getHours() !== 0)
            skip("the machine's timezone is not Atlantic/Azores")
    }
    function utc(month, day, h, m) { return Date.UTC(2026, month - 1, day, h, m) }

    // 23:30 on the eve is 00:30Z; a midnight that does not exist must not pull the day's end an hour early.
    function test_eve_of_a_midnight_gap() {
        azores()
        compare(M.at(utc(3, 28, 12, 0), "23:30", 0), utc(3, 29, 0, 30))
        compare(M.at(utc(3, 28, 12, 0), "23:59", 0), utc(3, 29, 0, 59))
        compare(M.at(utc(3, 28, 12, 0), "00:00", 0), utc(3, 28, 1, 0))
        compare(M.at(utc(3, 28, 12, 0), "00:00", 1), utc(3, 29, 1, 0))
        compare(M.nextMidnight(utc(3, 28, 12, 0)), utc(3, 29, 1, 0))
    }
    // The gap day starts at 01:00: 00:00 to 00:59 do not exist and mean the gap's end.
    function test_gap_day_times() {
        azores()
        const now = utc(3, 29, 12, 0)
        for (const hhmm of ["00:00", "00:01", "00:30", "00:59", "01:00"])
            compare(M.at(now, hhmm, 0), utc(3, 29, 1, 0), hhmm)
        compare(M.at(now, "01:01", 0), utc(3, 29, 1, 1))
        compare(M.at(now, "01:30", 0), utc(3, 29, 1, 30))
        compare(M.at(now, "01:59", 0), utc(3, 29, 1, 59))
        compare(M.at(now, "02:00", 0), utc(3, 29, 2, 0))
        compare(M.at(now, "23:30", 0), utc(3, 29, 23, 30))
        compare(M.nextMidnight(now), utc(3, 30, 0, 0))
    }
    // Light from 07:00, dark from 23:30, across the gap.
    function test_schedule_across_a_midnight_gap() {
        azores()
        const eve = M.schedule(utc(3, 28, 23, 0), "07:00", "23:30")
        compare(eve.mode, "light"); compare(eve.next, utc(3, 29, 0, 30))
        const night = M.schedule(utc(3, 29, 0, 45), "07:00", "23:30")      // 23:45 on the eve
        compare(night.mode, "dark"); compare(night.next, utc(3, 29, 7, 0))
        const early = M.schedule(utc(3, 29, 1, 10), "07:00", "23:30")      // 01:10, the first minutes of the day
        compare(early.mode, "dark"); compare(early.next, utc(3, 29, 7, 0))
        const evening = M.schedule(utc(3, 29, 22, 0), "07:00", "23:30")
        compare(evening.mode, "light"); compare(evening.next, utc(3, 29, 23, 30))
    }
    // The autumn day starts at 00:00Z and 00:00-00:59 happens twice: a time in it is its first pass.
    function test_repeated_midnight_hour() {
        azores()
        const now = utc(10, 25, 12, 0)
        compare(M.at(now, "00:00", 0), utc(10, 25, 0, 0))
        compare(M.at(now, "00:30", 0), utc(10, 25, 0, 30))
        compare(M.at(now, "01:00", 0), utc(10, 25, 2, 0))
        compare(M.at(now, "23:30", 0), utc(10, 26, 0, 30))
        compare(M.nextMidnight(now), utc(10, 26, 1, 0))
        compare(M.nextMidnight(utc(10, 24, 12, 0)), utc(10, 25, 0, 0))
    }
}
