import QtQuick
import QtTest
import "../lib/sun.js" as Sun

TestCase {
    name: "Sun"

    function near(ms, iso) {
        verify(Math.abs(ms - Date.parse(iso)) <= 120000, new Date(ms).toISOString() + " vs " + iso)
    }

    function test_amsterdam_june() {
        const s = Sun.sunTimes(2026, 6, 21, 52.3676, 4.9041)
        near(s.rise, "2026-06-21T03:18:00Z")
        near(s.set, "2026-06-21T20:06:00Z")
    }
    function test_amsterdam_december() {
        const s = Sun.sunTimes(2026, 12, 21, 52.3676, 4.9041)
        near(s.rise, "2026-12-21T07:48:00Z")
        near(s.set, "2026-12-21T15:28:00Z")
    }
    function test_quito_equinox() {
        const s = Sun.sunTimes(2026, 3, 20, -0.1807, -78.4678)
        near(s.rise, "2026-03-20T11:17:00Z")
        near(s.set, "2026-03-20T23:24:00Z")
    }
    function test_tromso_polar_night() {
        const s = Sun.sunTimes(2026, 12, 21, 69.6492, 18.9553)
        compare(s.rise, null)
        compare(s.set, null)
        compare(s.dayAllDay, false)
    }
    function test_tromso_midnight_sun() {
        const s = Sun.sunTimes(2026, 6, 21, 69.6492, 18.9553)
        compare(s.rise, null)
        compare(s.set, null)
        compare(s.dayAllDay, true)
    }

    // 67.5 N at lon 0: the midnight sun starts on 29 May with a sunrise and no sunset, and ends on 14 July with a
    // sunset and no sunrise.
    function test_polar_boundary_sunrise_only() {
        const s = Sun.sunTimes(2026, 5, 29, 67.5, 0)
        near(s.rise, "2026-05-29T00:17:00Z")
        compare(s.set, null)
        compare(s.dayAllDay, true)
    }
    function test_polar_boundary_sunset_only() {
        const s = Sun.sunTimes(2026, 7, 14, 67.5, 0)
        compare(s.rise, null)
        near(s.set, "2026-07-14T23:41:00Z")
        compare(s.dayAllDay, true)
    }
    function test_polar_boundary_ordinary_day_before() {
        const s = Sun.sunTimes(2026, 5, 28, 67.5, 0)
        near(s.rise, "2026-05-28T00:32:00Z")
        near(s.set, "2026-05-28T23:36:00Z")
        compare(s.dayAllDay, false)
    }
    function test_sun_times_past_the_end_of_the_month() {
        const a = Sun.sunTimes(2026, 10, 32, 52.3676, 4.9041)
        const b = Sun.sunTimes(2026, 11, 1, 52.3676, 4.9041)
        compare(a.rise, b.rise); compare(a.set, b.set)
    }

    // nextChange: the first millisecond at which the state differs, stepped and bisected.
    function test_next_change_is_the_first_millisecond_of_the_other_state() {
        const ams = { lat: 52.3676, lon: 4.9041 }
        const now = Date.UTC(2026, 5, 21, 12, 0)
        const t = Sun.nextChange(now, ams.lat, ams.lon, 36 * 3600000)
        near(t, "2026-06-21T20:06:00Z")
        verify(!Sun.isUp(t, ams.lat, ams.lon) && Sun.isUp(t - 1, ams.lat, ams.lon))
        const rise = Sun.nextChange(t, ams.lat, ams.lon, 36 * 3600000)
        near(rise, "2026-06-22T03:18:00Z")
        verify(Sun.isUp(rise, ams.lat, ams.lon) && !Sun.isUp(rise - 1, ams.lat, ams.lon))
    }
    function test_next_change_none_in_the_polar_day_and_night() {
        compare(Sun.nextChange(Date.UTC(2026, 5, 21, 12, 0), 69.6492, 18.9553, 36 * 3600000), null)
        compare(Sun.nextChange(Date.UTC(2026, 11, 21, 12, 0), 69.6492, 18.9553, 36 * 3600000), null)
    }
    // A day or night of a few minutes centred on the altitude's extreme, which the drifting declination moves off hour
    // angle 0 or pi (by 30 s at 75 N in February, 2 min at 84.9 N in March, 14 min at 88.9 S at the equinox and 2 h 44
    // min at 89.9 N two days before it): the change is found, and at the time the equation of time puts it (14 min
    // early in February).
    function test_next_change_finds_a_short_day_or_night_off_noon_or_midnight() {
        for (const [lat, lon, now, change, minutes] of [
                [75.00341, 0, "2026-02-05T09:13:56.859Z", "2026-02-05T12:14:16.859Z", 1],
                [84.8978, 0, "2026-03-05T09:12:24.480Z", "2026-03-05T12:12:42.536Z", 3],
                [-88.92991, 0, "2026-03-19T21:18:13.474Z", "2026-03-20T00:18:38.574Z", 5],
                [89.9, 110.718, "2026-03-18T04:19:20.817Z", "2026-03-18T07:19:40.817Z", 3]]) {
            const from = Date.parse(now)
            const t = Sun.nextChange(from, lat, lon, 36 * 3600000)
            verify(t !== null, now)
            verify(Math.abs(t - Date.parse(change)) <= 1000, new Date(t).toISOString() + " vs " + change)
            const state = Sun.isUp(from, lat, lon)
            verify(Sun.isUp(t, lat, lon) !== state && Sun.isUp(t - 1, lat, lon) === state)
            for (let u = from; u < t; u += 10000) // and none earlier, by a scan of its own
                compare(Sun.isUp(u, lat, lon), state, new Date(u).toISOString())
            const back = Sun.nextChange(t, lat, lon, 36 * 3600000)
            verify(Math.abs(back - t - minutes * 60000) <= 30000, (back - t) / 60000 + " min vs " + minutes)
        }
    }
    function test_next_change_stops_at_the_horizon() {
        const now = Date.UTC(2026, 5, 21, 12, 0)
        compare(Sun.nextChange(now, 52.3676, 4.9041, 3600000), null)
    }
}
