import QtQuick
import QtTest
import "../lib/themeMode.js" as M
import "../lib/sun.js" as Sun

TestCase {
    name: "ThemeMode"

    readonly property var dflt: ({ light: "07:00", dark: "20:00" })
    readonly property var ams: ({ lat: 52.3676, lon: 4.9041 })
    readonly property var tromso: ({ lat: 69.6492, lon: 18.9553 })

    // Local time throughout.
    function at(h, m, dayOffset = 0) { return new Date(2026, 9, 24 + dayOffset, h, m).getTime() }

    function hhmm(ms) {
        const d = new Date(ms)
        return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
    }

    function test_schedule_day_and_wrap() {
        compare(M.schedule(at(12, 0), "07:00", "20:00").mode, "light")
        compare(M.schedule(at(23, 0), "07:00", "20:00").mode, "dark")
        compare(M.schedule(at(2, 0), "22:00", "06:00").mode, "light")       // light window wraps past midnight
        compare(M.schedule(at(12, 0), "08:00", "08:00").mode, "dark")
    }
    function test_schedule_next() {
        compare(M.schedule(at(12, 0), "07:00", "20:00").next, at(20, 0))
        compare(M.schedule(at(21, 0), "07:00", "20:00").next, at(7, 0, +1))
        compare(M.schedule(at(5, 0), "07:00", "20:00").next, at(7, 0))
        compare(M.schedule(at(2, 0), "22:00", "06:00").next, at(6, 0))
        compare(M.schedule(at(23, 0), "22:00", "06:00").next, at(6, 0, +1))
        compare(M.schedule(at(12, 0), "08:00", "08:00").next, null)
        // strictly after now: exactly at the switch time the new mode holds and the next one is a day later
        compare(M.schedule(at(7, 0), "07:00", "20:00").mode, "light")
        compare(M.schedule(at(20, 0), "07:00", "20:00").mode, "dark")
        compare(M.schedule(at(20, 0), "07:00", "20:00").next, at(7, 0, +1))
    }
    function test_override_until_and_expiry() {
        const s = { mode: "schedule", schedule: { light: "07:00", dark: "20:00" } }
        const o = M.flip(at(21, 0), s, null, "dark")
        compare(o.mode, "light"); compare(o.until, at(7, 0, +1))
        compare(M.wanted(at(23, 0), s, null, o).mode, "light")
    }
    function test_clock_jump_expires_override() {
        const s = { mode: "schedule", schedule: { light: "07:00", dark: "20:00" } }
        const o = { mode: "light", until: at(7, 0, +1), setFor: "schedule" }
        const w = M.wanted(at(8, 0, +1), s, null, o)
        compare(w.mode, "light"); compare(w.override, null)                 // expired while asleep; auto says light
        compare(M.wanted(at(21, 0, +1), s, null, o).mode, "dark")
    }
    function test_kept_override_is_returned() {
        const s = { mode: "schedule", schedule: dflt }
        const o = { mode: "light", until: at(7, 0, +1), setFor: "schedule" }
        compare(M.wanted(at(23, 0), s, null, o).override, o)
        compare(M.wanted(at(23, 0), s, null, null).override, null)
    }
    function test_mode_change_clears_override() {
        const o = { mode: "light", until: null, setFor: "dark" }
        compare(M.wanted(at(12, 0), { mode: "schedule", schedule: dflt }, null, o).override, null)
    }
    function test_fixed_override_without_until_stays() {
        const s = { mode: "dark", schedule: dflt }
        const o = M.flip(at(12, 0), s, null, "dark")
        compare(o.mode, "light"); compare(o.setFor, "dark")
        compare(M.wanted(at(3, 0, +5), s, null, o).mode, "light")
    }
    function test_flip_back_clears() { const s = { mode: "light", schedule: dflt }; compare(M.flip(at(12, 0), s, null, "dark"), null) }
    function test_flip_in_fixed_mode_has_no_until() { const o = M.flip(at(12, 0), { mode: "light", schedule: dflt }, null, "light"); compare(o.until, null) }
    function test_auto_fixed() {
        const a = M.auto(at(12, 0), { mode: "dark", schedule: dflt }, ams)
        compare(a.mode, "dark"); compare(a.next, null); compare(a.why, "fixed")
    }
    function test_sun_without_location_uses_schedule() {
        compare(M.sun(at(21, 0), null, "07:00", "20:00").mode, "dark")
        compare(M.sun(at(21, 0), null, "07:00", "20:00").why, "schedule")
    }

    // Amsterdam, 24 and 25 October 2026 (sunrise 06:21Z, sunset 16:26Z), from UTC anchors: the sun's day follows the
    // location, so these hold in any time zone.
    readonly property var ams24: Sun.sunTimes(2026, 10, 24, ams.lat, ams.lon)
    readonly property var ams25: Sun.sunTimes(2026, 10, 25, ams.lat, ams.lon)
    readonly property real amsMidday: Date.UTC(2026, 9, 24, 12, 0)
    function near(ms, iso) {
        verify(Math.abs(ms - Date.parse(iso)) <= 120000, new Date(ms).toISOString() + " vs " + iso)
    }
    // Two instants within two minutes: the shell's next change comes from the altitude, sunTimes' events from NOAA's
    // equations, and they agree only about that closely.
    function close(a, b) {
        verify(Math.abs(a - b) <= 120000, new Date(a).toISOString() + " vs " + new Date(b).toISOString())
    }
    // The anchors themselves, so a drift in sunTimes shows up here and not as a silent shift of every expectation.
    function test_sun_anchors() {
        near(ams24.rise, "2026-10-24T06:21:00Z"); near(ams24.set, "2026-10-24T16:27:00Z")
        near(ams25.rise, "2026-10-25T06:23:00Z")
    }
    function test_sun_midday_is_light_until_sunset() {
        const r = M.sun(amsMidday, ams, "07:00", "20:00")
        compare(r.mode, "light"); close(r.next, ams24.set); compare(r.why, "sunset")
    }
    function test_sun_before_sunrise_is_dark_until_sunrise() {
        const r = M.sun(ams24.rise - 3600000, ams, "07:00", "20:00")
        compare(r.mode, "dark"); close(r.next, ams24.rise); compare(r.why, "sunrise")
    }
    function test_sun_after_sunrise_is_light() {
        const r = M.sun(ams24.rise + 180000, ams, "07:00", "20:00")
        compare(r.mode, "light"); close(r.next, ams24.set)
        compare(M.sun(ams24.rise - 180000, ams, "07:00", "20:00").mode, "dark")
    }
    function test_sun_after_sunset_looks_to_tomorrows_sunrise() {
        const r = M.sun(ams24.set + 3600000, ams, "07:00", "20:00")
        compare(r.mode, "dark"); compare(r.why, "sunrise"); close(r.next, ams25.rise)
    }
    // At the instant of the change the new mode holds, and the next change is a later one; a millisecond earlier the
    // old mode still holds.
    function test_sun_next_is_strictly_after_now() {
        const r = M.sun(amsMidday, ams, "07:00", "20:00")
        const r2 = M.sun(r.next, ams, "07:00", "20:00")
        compare(r2.mode, "dark"); compare(r2.why, "sunrise"); verify(r2.next > r.next)
        compare(M.sun(r.next - 1, ams, "07:00", "20:00").mode, "light")
    }
    // Far from the clock's time zone the sun's day is not the local date: 03:00Z on the 25th is the 24th, 17:00, in
    // Honolulu, where the sun is still up until its sunset (04:00Z), which belongs to the 24th. In UTC+1 the local
    // date alone would take the 25th's sunrise and call it night.
    function test_sun_day_of_the_location_not_the_clocks() {
        const hnl = { lat: 21.3, lon: -157.86 }
        const set = Sun.sunTimes(2026, 10, 24, hnl.lat, hnl.lon).set
        near(set, "2026-10-25T04:00:00Z")
        const r = M.sun(Date.UTC(2026, 9, 25, 3, 0), hnl, "07:00", "20:00")
        compare(r.mode, "light"); compare(r.why, "sunset"); close(r.next, set)
        // And the other way round, in the far east (Auckland, 12:00 on the 25th is 23:00Z on the 24th).
        const akl = { lat: -36.85, lon: 174.76 }
        const r2 = M.sun(Date.UTC(2026, 9, 24, 23, 0), akl, "07:00", "20:00")
        compare(r2.mode, "light")
        close(r2.next, Sun.sunTimes(2026, 10, 25, akl.lat, akl.lon).set)
    }
    // Near the polar boundary one of the two events can be missing: 67.5 degrees north at lon 0 has a sunrise but
    // no sunset on 29 May (the midnight sun starts) and a sunset but no sunrise on 14 July (it ends).
    function test_sun_midnight_sun_starts() {
        const p = { lat: 67.5, lon: 0 }
        const day = Sun.sunTimes(2026, 5, 29, p.lat, p.lon)
        verify(day.rise !== null && day.set === null)
        near(day.rise, "2026-05-29T00:17:00Z")
        const before = M.sun(day.rise - 600000, p, "07:00", "20:00")
        compare(before.mode, "dark"); compare(before.why, "sunrise"); close(before.next, day.rise)
        const after = M.sun(Date.UTC(2026, 4, 29, 12, 0), p, "07:00", "20:00")
        compare(after.mode, "light"); compare(after.why, "polar")
    }
    function test_sun_midnight_sun_ends() {
        const p = { lat: 67.5, lon: 0 }
        const day = Sun.sunTimes(2026, 7, 14, p.lat, p.lon)
        verify(day.rise === null && day.set !== null)
        near(day.set, "2026-07-14T23:41:00Z")
        const noon = M.sun(Date.UTC(2026, 6, 14, 12, 0), p, "07:00", "20:00")
        compare(noon.mode, "light"); compare(noon.why, "sunset"); close(noon.next, day.set)
        const night = M.sun(day.set + 180000, p, "07:00", "20:00")
        compare(night.mode, "dark"); compare(night.why, "sunrise")
    }
    function test_sun_polar_night() {
        const now = new Date(2026, 11, 21, 12, 0).getTime()
        verify(Sun.sunTimes(2026, 12, 21, tromso.lat, tromso.lon).rise === null)
        const r = M.sun(now, tromso, "07:00", "20:00")
        compare(r.mode, "dark"); compare(r.why, "polar"); compare(r.next, new Date(2026, 11, 22).getTime())
    }
    function test_sun_polar_day() {
        const now = new Date(2026, 5, 21, 12, 0).getTime()
        verify(Sun.sunTimes(2026, 6, 21, tromso.lat, tromso.lon).rise === null)
        const r = M.sun(now, tromso, "07:00", "20:00")
        compare(r.mode, "light"); compare(r.why, "polar"); compare(r.next, new Date(2026, 5, 22).getTime())
    }
    function test_auto_sun_uses_location() {
        const s = { mode: "sun", schedule: dflt }
        const now = amsMidday
        compare(M.auto(now, s, ams).why, "sunset")
        compare(M.auto(now, s, null).why, "schedule")
        compare(M.auto(now, { mode: "schedule", schedule: dflt }, ams).why, "schedule")
    }
    function test_flip_in_sun_mode_lasts_until_next_event() {
        const s = { mode: "sun", schedule: dflt }
        const o = M.flip(amsMidday, s, ams, "light")
        compare(o.mode, "dark"); close(o.until, ams24.set); compare(o.setFor, "sun")
    }

    function test_needs_apply_when_nothing_applied() { verify(M.needsApply(null, "light")); verify(!M.needsApply("dark", "dark")) }
    function test_needs_apply_when_mode_differs() { verify(M.needsApply("dark", "light")) }
    // An app failed after theme.json already said dark: retried while that failure stands, and only for its mode.
    function test_needs_apply_retries_a_failed_mode() {
        verify(M.needsApply("dark", "dark", "dark"))
        verify(!M.needsApply("dark", "dark", ""))
        verify(!M.needsApply("dark", "dark", "light"))
        verify(M.needsApply("light", "dark", "light"))
    }

    // `gutter hypr` bookkeeping: what is owed a run, after which events.
    function hyprAfter(events) {
        let s = { pending: false, failed: false }
        for (const e of events)
            s = M.hyprState(s, e)
        return s
    }
    function test_hypr_every_settings_load_is_pending() {
        verify(!hyprAfter([]).pending)
        verify(hyprAfter(["settings"]).pending)
        verify(!hyprAfter(["settings", "start"]).pending)
        // The same colour again (A, then B and back to A during a run) still gets a run: the tool skips no-ops.
        verify(hyprAfter(["settings", "start", "settings"]).pending)
    }
    // A failed run is not owed another until the tick, so a lasting failure runs once a minute, not in a loop.
    function test_hypr_failure_waits_for_the_tick() {
        verify(!hyprAfter(["settings", "start", "failed"]).pending)
        verify(hyprAfter(["settings", "start", "failed", "tick"]).pending)
        verify(!hyprAfter(["settings", "start", "failed", "tick", "start"]).pending)
        verify(!hyprAfter(["settings", "start", "failed", "tick", "start", "failed"]).pending)
    }
    function test_hypr_tick_alone_runs_nothing() {
        verify(!hyprAfter(["tick"]).pending)
        verify(!hyprAfter(["settings", "start", "tick"]).pending)
    }
    // A settings load during a run that then fails is still owed its own run.
    function test_hypr_change_during_a_failed_run() {
        verify(hyprAfter(["settings", "start", "settings", "failed"]).pending)
    }

    function test_tooltip() { compare(M.tooltip(at(21, 0), { mode: "schedule", schedule: dflt }, null, null, "dark"), "Dark until 07:00") }
    function test_tooltip_schedule_light() { compare(M.tooltip(at(12, 0), { mode: "schedule", schedule: dflt }, null, null, "light"), "Light until 20:00") }
    function test_tooltip_fixed() {
        compare(M.tooltip(at(12, 0), { mode: "dark", schedule: dflt }, null, null, "dark"), "Dark (fixed)")
        compare(M.tooltip(at(12, 0), { mode: "schedule", schedule: { light: "08:00", dark: "08:00" } }, null, null, "dark"), "Dark (fixed)")
    }
    function test_tooltip_override() {
        const s = { mode: "schedule", schedule: dflt }
        // Other mode at until: the flip ends there.
        compare(M.tooltip(at(21, 0), s, null, { mode: "dark", until: at(7, 0, +1), setFor: "schedule" }, "dark"), "Dark until 07:00")
        // Same mode at until (light from 07:00 anyway): the next real change, 20:00 tomorrow.
        compare(M.tooltip(at(21, 0), s, null, { mode: "light", until: at(7, 0, +1), setFor: "schedule" }, "light"), "Light until 20:00")
        compare(M.tooltip(at(21, 0), { mode: "dark", schedule: dflt }, null, { mode: "light", until: null, setFor: "dark" }, "light"), "Light (fixed)")
    }
    function test_tooltip_sun() {
        const s = { mode: "sun", schedule: dflt }
        const now = amsMidday
        const a = M.auto(now, s, ams)
        compare(M.tooltip(now, s, ams, null, "light"), "Light until " + hhmm(a.next) + " (sunset)")
        const b = M.auto(ams24.rise - 3600000, s, ams)
        compare(M.tooltip(ams24.rise - 3600000, s, ams, null, "dark"), "Dark until " + hhmm(b.next) + " (sunrise)")
        const o = M.flip(now, s, ams, "light")
        const c = M.auto(o.until, s, ams)
        compare(M.tooltip(now, s, ams, o, "dark"), "Dark until " + hhmm(c.next) + " (sunrise)")
        verify(/^Light until \d\d:\d\d \(sunset\)$/.test(M.tooltip(now, s, ams, null, "light")))
    }
    function test_tooltip_polar() {
        const now = new Date(2026, 11, 21, 12, 0).getTime()
        compare(M.tooltip(now, { mode: "sun", schedule: dflt }, tromso, null, "dark"), "Dark (polar night)")
        compare(M.tooltip(new Date(2026, 5, 21, 12, 0).getTime(), { mode: "sun", schedule: dflt }, tromso, null, "light"), "Light (polar day)")
    }
    // A flip in the polar night or day lasts to midnight; the tooltip still says why the other mode is the automatic one.
    function test_tooltip_polar_override() {
        const s = { mode: "sun", schedule: dflt }
        const night = new Date(2026, 11, 21, 12, 0).getTime()
        const on = M.flip(night, s, tromso, "dark")
        compare(on.mode, "light"); compare(on.until, new Date(2026, 11, 22).getTime())
        compare(M.tooltip(night, s, tromso, on, "light"), "Light until 00:00 (polar night)")
        const day = new Date(2026, 5, 21, 12, 0).getTime()
        const off = M.flip(day, s, tromso, "light")
        compare(M.tooltip(day, s, tromso, off, "dark"), "Dark until 00:00 (polar day)")
    }

    function test_parse_auto() {
        const ok = M.parseAuto('{"version": 1, "location": {"lat": 52.37, "lon": 4.9}, "override": {"mode": "light", "until": 1761368400000, "setFor": "sun"}}')
        compare(ok.error, ""); compare(ok.location, { lat: 52.37, lon: 4.9 })
        compare(ok.override, { mode: "light", until: 1761368400000, setFor: "sun" })
        const fixed = M.parseAuto('{"version": 1, "location": null, "override": {"mode": "dark", "until": null, "setFor": "light"}}')
        compare(fixed.location, null); compare(fixed.override.until, null)
    }
    function test_parse_auto_invalid_is_empty() {
        for (const text of [null, "", "not json", "[]", "null", '{"version": 2, "location": {"lat": 1, "lon": 2}}']) {
            const r = M.parseAuto(text)
            compare(r.location, null); compare(r.override, null)
            verify(text === null ? r.error === "" : r.error !== "", String(text))
        }
    }
    function test_parse_auto_bad_parts_are_dropped() {
        const r = M.parseAuto('{"version": 1, "location": {"lat": "x", "lon": 4}, "override": {"mode": "dusk", "until": null, "setFor": "sun"}}')
        compare(r.location, null); compare(r.override, null)
        compare(M.parseAuto('{"version": 1, "location": {"lat": 91, "lon": 4}, "override": null}').location, null)
        compare(M.parseAuto('{"version": 1, "override": {"mode": "dark", "until": "soon", "setFor": "sun"}}').override, null)
        compare(M.parseAuto('{"version": 1, "override": {"mode": "dark", "until": 5}}').override, null)
    }
    function test_auto_text_round_trips() {
        const o = { mode: "dark", until: 1761368400000, setFor: "schedule" }
        const r = M.parseAuto(M.autoText({ lat: 1.5, lon: -2 }, o))
        compare(r.error, ""); compare(r.location, { lat: 1.5, lon: -2 }); compare(r.override, o)
        compare(M.parseAuto(M.autoText(null, null)).override, null)
        verify(M.autoText(null, null).endsWith("\n"))
    }
    function test_same_location() {
        verify(M.sameLocation(null, null)); verify(M.sameLocation({ lat: 1, lon: 2 }, { lat: 1, lon: 2 }))
        verify(!M.sameLocation(null, { lat: 1, lon: 2 })); verify(!M.sameLocation({ lat: 1, lon: 2 }, { lat: 1, lon: 3 }))
    }
    // Ghent, 24 October 2026, 16:17 CEST (14:17Z): sunset 16:34Z, so it is light, and the next sunrise is the 25th's.
    readonly property var ghent: ({ lat: 51.05, lon: 3.72 })
    readonly property var ghent24: Sun.sunTimes(2026, 10, 24, ghent.lat, ghent.lon)
    readonly property var ghent25: Sun.sunTimes(2026, 10, 25, ghent.lat, ghent.lon)
    readonly property real ghentAfternoon: Date.UTC(2026, 9, 24, 14, 17)
    // R20: a flip to dark at 16:17 in Ghent holds to sunset, where the sun keeps it dark: nothing changes at sunset, so
    // the tooltip names the next sunrise.
    function test_tooltip_flip_names_next_real_change() {
        const s = { mode: "sun", schedule: dflt }
        const now = ghentAfternoon
        verify(now > ghent24.rise && now < ghent24.set)
        const o = M.flip(now, s, ghent, "light")
        compare(o.mode, "dark"); close(o.until, ghent24.set)
        const rise = M.auto(o.until, s, ghent).next
        close(rise, ghent25.rise)
        compare(M.tooltip(now, s, ghent, o, "dark"), "Dark until " + hhmm(rise) + " (sunrise)")
    }
    function test_tooltip_override_ending_in_other_mode_names_until() {
        const s = { mode: "sun", schedule: dflt }
        const now = ghentAfternoon
        // Dark held until just after tomorrow's sunrise, where the sun makes it light: the flip ends at until. The
        // text is as before R20 (a reason only when until is the automatic mode's own next event, here today's sunset).
        const o = { mode: "dark", until: ghent25.rise + 180000, setFor: "sun" }
        compare(M.tooltip(now, s, ghent, o, "dark"), "Dark until " + hhmm(o.until))
        // An until that is not a sun event: the time without a reason.
        const o2 = { mode: "light", until: now + 6 * 3600000, setFor: "sun" }
        compare(M.tooltip(now, s, ghent, o2, "light"), "Light until " + hhmm(now + 6 * 3600000))
    }
    function test_tooltip_schedule_flip_same_mode_at_until() {
        const s = { mode: "schedule", schedule: dflt }
        const o = M.flip(at(12, 0), s, null, "light")                     // dark until 20:00, dark from then anyway
        compare(o.until, at(20, 0))
        compare(M.tooltip(at(12, 0), s, null, o, "dark"), "Dark until 07:00")
    }

    // DST changes, from UTC anchors. Europe/Brussels (scripts/test.sh pins TZ): 29 March 2026 02:00 CET jumps to
    // 03:00 CEST (01:00Z), 25 October 2026 03:00 CEST falls back to 02:00 CET (01:00Z). In any other zone these skip.
    function brussels() {
        if (new Date(Date.UTC(2026, 2, 29, 1, 0)).getHours() !== 3 || new Date(Date.UTC(2026, 9, 25, 1, 0)).getHours() !== 2)
            skip("the machine's timezone is not Europe/Brussels")
    }
    function utc(month, day, h, m) { return Date.UTC(2026, month - 1, day, h, m) }

    // 02:30 does not exist on the spring day: the schedule switches when the gap ends (03:00 CEST), where the
    // minute-of-day clock first reads 02:30 or later, not half an hour later.
    function test_dst_gap_time_is_the_gap_end() {
        brussels()
        compare(M.at(utc(3, 29, 0, 0), "02:30", 0), utc(3, 29, 1, 0))
        compare(M.at(utc(3, 29, 0, 0), "02:00", 0), utc(3, 29, 1, 0))
        compare(M.at(utc(3, 29, 0, 0), "01:59", 0), utc(3, 29, 0, 59))
        compare(M.at(utc(3, 29, 0, 0), "03:00", 0), utc(3, 29, 1, 0))
        compare(M.at(utc(3, 29, 0, 0), "03:01", 0), utc(3, 29, 1, 1))
        compare(M.at(utc(3, 29, 0, 0), "00:00", 1), utc(3, 29, 22, 0))
    }
    function test_schedule_into_a_dst_gap() {
        brussels()
        const light = ["02:30", "20:00"]
        const before = M.schedule(utc(3, 29, 0, 30), light[0], light[1])
        compare(before.mode, "dark"); compare(before.next, utc(3, 29, 1, 0))
        const after = M.schedule(utc(3, 29, 1, 0), light[0], light[1])
        compare(after.mode, "light"); compare(after.next, utc(3, 29, 18, 0))
        // The other way: dark from 02:30, light from 07:00.
        const dark = M.schedule(utc(3, 29, 1, 5), "07:00", "02:30")
        compare(dark.mode, "dark"); compare(dark.next, utc(3, 29, 5, 0))
        // The evening before: the next switch is the gap's end, not a day later.
        compare(M.schedule(utc(3, 28, 21, 0), light[0], light[1]).next, utc(3, 29, 1, 0))
    }
    function test_schedule_with_both_times_in_a_dst_gap() {
        brussels()
        // 02:10 and 02:50 both land on 03:00 CEST; the later name wins, as the clock reading says: dark from 02:50.
        const r = M.schedule(utc(3, 29, 1, 30), "02:10", "02:50")
        compare(r.mode, "dark"); compare(r.next, utc(3, 30, 0, 10))
    }
    // 02:00-03:00 happens twice on the autumn day. A switch inside the repeated hour happens at its first pass only:
    // light from 02:30 stays light for the second 02:10 (a minute-of-day check would go dark, then light again).
    function test_schedule_in_the_repeated_hour() {
        brussels()
        const first = M.schedule(utc(10, 25, 0, 40), "02:30", "20:00")        // 02:40 CEST
        compare(first.mode, "light"); compare(first.next, utc(10, 25, 19, 0))
        const second = M.schedule(utc(10, 25, 1, 10), "02:30", "20:00")       // 02:10 CET, the second pass
        compare(second.mode, "light"); compare(second.next, utc(10, 25, 19, 0))
        compare(M.schedule(utc(10, 25, 0, 20), "02:30", "20:00").mode, "dark")   // 02:20 CEST, before the switch
        compare(M.schedule(utc(10, 25, 0, 20), "02:30", "20:00").next, utc(10, 25, 0, 30))
    }
    // Both times land on the gap's end (03:00 CEST): the later name wins, which here is the mode in force already, so
    // nothing changes there and the next real change is the next day's switch.
    function test_schedule_inside_a_dst_gap_changes_nothing_there() {
        brussels()
        const a = M.schedule(utc(3, 29, 0, 30), "02:00", "03:00")             // 01:30 CET: dark, 02:00 light is the gap
        compare(a.mode, "dark"); compare(a.next, utc(3, 30, 0, 0))
        const b = M.schedule(utc(3, 29, 1, 30), "02:00", "03:00")
        compare(b.mode, "dark"); compare(b.next, utc(3, 30, 0, 0))
        compare(M.schedule(utc(3, 28, 21, 0), "02:00", "03:00").next, utc(3, 30, 0, 0))
        // The other way round: dark 02:00 and light 03:00 collapse to light, and it was light already.
        const c = M.schedule(utc(3, 29, 0, 30), "03:00", "02:00")
        compare(c.mode, "light"); compare(c.next, utc(3, 30, 0, 0))
        compare(M.schedule(utc(3, 29, 1, 30), "03:00", "02:00").next, utc(3, 30, 0, 0))
    }
    function test_schedule_over_a_dst_day_keeps_its_real_length() {
        brussels()
        // 07:00 light on the autumn day is 06:00Z (CET), the evening before 05:00Z (CEST).
        compare(M.schedule(utc(10, 24, 20, 0), "07:00", "20:00").next, utc(10, 25, 6, 0))
        compare(M.schedule(utc(10, 25, 5, 59), "07:00", "20:00").mode, "dark")
        compare(M.schedule(utc(10, 25, 6, 0), "07:00", "20:00").mode, "light")
        compare(M.schedule(utc(3, 28, 20, 0), "07:00", "20:00").next, utc(3, 29, 5, 0))
    }
    // Sun mode follows the sun, whatever the clock does on that day: Ghent on both changes.
    function test_sun_on_the_autumn_dst_day() {
        brussels()
        const s = { mode: "sun", schedule: dflt }
        near(ghent25.rise, "2026-10-25T06:25:00Z"); near(ghent25.set, "2026-10-25T16:32:00Z")
        const night = M.auto(utc(10, 25, 1, 30), s, ghent)
        compare(night.mode, "dark"); close(night.next, ghent25.rise)
        const noon = M.auto(utc(10, 25, 11, 0), s, ghent)
        compare(noon.mode, "light"); close(noon.next, ghent25.set)
        verify(/^Light until 17:3[123] \(sunset\)$/.test(M.tooltip(utc(10, 25, 11, 0), s, ghent, null, "light")))
        verify(/^Dark until 07:2[456] \(sunrise\)$/.test(M.tooltip(utc(10, 25, 1, 30), s, ghent, null, "dark")))
    }
    function test_sun_on_the_spring_dst_day() {
        brussels()
        const s = { mode: "sun", schedule: dflt }
        const day = Sun.sunTimes(2026, 3, 29, ghent.lat, ghent.lon)
        near(day.rise, "2026-03-29T05:28:00Z"); near(day.set, "2026-03-29T18:13:00Z")
        compare(M.auto(utc(3, 29, 0, 30), s, ghent).mode, "dark")
        close(M.auto(utc(3, 29, 0, 30), s, ghent).next, day.rise)
        compare(M.auto(utc(3, 29, 12, 0), s, ghent).mode, "light")
        verify(/^Light until 20:1[123] \(sunset\)$/.test(M.tooltip(utc(3, 29, 12, 0), s, ghent, null, "light")))
    }

    // 23:30 on the 23-hour spring day is 22:30Z, not an hour later; on the 25-hour autumn day also 22:30Z.
    function test_late_evening_time_on_a_dst_day() {
        brussels()
        compare(M.at(utc(3, 29, 0, 0), "23:30", 0), utc(3, 29, 21, 30))
        compare(M.at(utc(3, 29, 0, 0), "23:59", 0), utc(3, 29, 21, 59))
        compare(M.at(utc(10, 25, 0, 0), "23:30", 0), utc(10, 25, 22, 30))
        compare(M.at(utc(10, 25, 0, 0), "00:00", 0), utc(10, 24, 22, 0))
        const r = M.schedule(utc(3, 29, 20, 0), "07:00", "23:30")         // 22:00 CEST
        compare(r.mode, "light"); compare(r.next, utc(3, 29, 21, 30))
        const night = M.schedule(utc(3, 29, 22, 10), "07:00", "23:30")    // 00:10 CEST the 30th
        compare(night.mode, "dark"); compare(night.next, utc(3, 30, 5, 0))
    }

    // The sun's altitude decides the mode, so the events a day lacks near the polar boundary cannot leave it wrong
    // for days. Each case is a place and instant where the sun is up (or down) all through the window shown.
    function sunModeAround(loc, from, to, mode) {
        for (let t = from; t <= to; t += 1800000) {
            const r = M.sun(t, loc, "07:00", "20:00")
            if (r.mode !== mode)
                return new Date(t).toISOString() + " is " + r.mode + ", not " + mode
            if (!(r.next > t))
                return new Date(t).toISOString() + " has next " + r.next
        }
        return ""
    }
    function test_sun_mode_in_the_midnight_sun_near_the_boundary() {
        // 66.5 N: from mid June the sun is up all day and night.
        compare(sunModeAround({ lat: 66.5, lon: 0 }, utc(6, 12, 0, 0), utc(6, 30, 23, 30), "light"), "")
        // 69.6 N from 18 May to 24 July the sun does not set.
        compare(sunModeAround({ lat: 69.6, lon: 0 }, utc(5, 20, 0, 0), utc(7, 20, 0, 0), "light"), "")
    }
    function test_sun_mode_in_the_polar_night_near_the_boundary() {
        compare(sunModeAround({ lat: 69.6, lon: 0 }, utc(12, 1, 0, 0), utc(12, 31, 0, 0), "dark"), "")
        compare(sunModeAround({ lat: 68.5, lon: 0 }, utc(12, 10, 0, 0), utc(12, 31, 12, 0), "dark"), "")
    }
    // sunTimes' events and the altitude agree at mid-latitudes: dark before sunrise and light after, to a few minutes.
    function test_sun_isUp_agrees_with_the_events() {
        for (const loc of [ams, { lat: -33.9, lon: 151.2 }, { lat: 21.3, lon: -157.86 }, { lat: 60.2, lon: 25 }]) {
            for (let month = 1; month <= 12; month++) {
                const e = Sun.sunTimes(2026, month, 15, loc.lat, loc.lon)
                verify(!Sun.isUp(e.rise - 180000, loc.lat, loc.lon) && Sun.isUp(e.rise + 180000, loc.lat, loc.lon), "rise " + month)
                verify(Sun.isUp(e.set - 180000, loc.lat, loc.lon) && !Sun.isUp(e.set + 180000, loc.lat, loc.lon), "set " + month)
            }
        }
    }

    // The first minute after `now` at which the sun's state differs from now's, by a scan of its own.
    function scanChange(now, loc) {
        const up = Sun.isUp(now, loc.lat, loc.lon)
        for (let t = now + 60000; t <= now + 40 * 3600000; t += 60000) {
            if (Sun.isUp(t, loc.lat, loc.lon) !== up)
                return t
        }
        return null
    }
    // next is the first change of the altitude: within a minute of the scan's, and the mode really flips there.
    function checkNext(now, loc) {
        const r = M.sun(now, loc, "07:00", "20:00")
        const e = scanChange(now, loc)
        verify(r.next > e - 60000 && r.next <= e, new Date(r.next).toISOString() + " vs " + new Date(e).toISOString())
        compare(M.sun(r.next, loc, "07:00", "20:00").mode === r.mode, false)
        compare(M.sun(r.next - 1, loc, "07:00", "20:00").mode, r.mode)
        return r
    }
    function weekday(ms) { return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date(ms).getDay()] }
    // A change under a day away is a bare HH:MM; from a day on it names its weekday.
    function test_tooltip_names_the_weekday_from_a_day_away() {
        const s = { mode: "sun", schedule: dflt }
        const now = Date.UTC(2026, 6, 24, 12, 0)
        const next = M.sun(now, tromso, "07:00", "20:00").next
        compare(M.tooltip(now, s, tromso, null, "light"), "Light until " + weekday(next) + " " + hhmm(next) + " (sunset)")
        verify(next - now >= 86400000)
        // The same change seen from 23 h before it is today's or tomorrow's: bare.
        compare(M.tooltip(next - 23 * 3600000, s, tromso, null, "light"), "Light until " + hhmm(next) + " (sunset)")
        // The schedule's next switch, tonight to tomorrow's 07:00, is under a day: bare.
        compare(M.tooltip(at(21, 0), { mode: "schedule", schedule: dflt }, null, null, "dark"), "Dark until 07:00")
    }
    // The last midnight sun at Tromso: no sunrise or sunset event on the 24th, but the sun sets late on the 25th. The
    // light mode must not run a day past that sunset.
    function test_sun_tromso_last_midnight_sun_sunset() {
        const s = { mode: "sun", schedule: dflt }
        const now = Date.UTC(2026, 6, 24, 12, 0)
        const r = checkNext(now, tromso)
        compare(r.mode, "light"); compare(r.why, "sunset")
        near(r.next, "2026-07-25T22:38:00Z")
        // More than a day away (34.6 h): the weekday says which day.
        compare(M.tooltip(now, s, tromso, null, "light"), "Light until " + weekday(r.next) + " " + hhmm(r.next) + " (sunset)")
        const late = checkNext(Date.UTC(2026, 6, 25, 20, 0), tromso)
        compare(late.why, "sunset"); close(late.next, r.next)
        const dark = checkNext(Date.UTC(2026, 6, 25, 22, 50), tromso)
        compare(dark.mode, "dark"); compare(dark.why, "sunrise")
    }
    // Days where the sun dips below the horizon for minutes only: never "polar night" or "polar day" while the
    // altitude changes within the hour.
    function test_sun_tromso_short_nights_and_days_are_not_polar() {
        const s = { mode: "sun", schedule: dflt }
        const night = Date.UTC(2026, 4, 17, 22, 30)
        const r = checkNext(night, tromso)
        compare(r.mode, "dark"); compare(r.why, "sunrise")
        verify(r.next - night < 3600000)
        compare(M.tooltip(night, s, tromso, null, "dark"), "Dark until " + hhmm(r.next) + " (sunrise)")
        const day = Date.UTC(2026, 10, 27, 10, 30)
        const d = checkNext(day, tromso)
        compare(d.mode, "light"); compare(d.why, "sunset")
        verify(d.next - day < 3600000)
        compare(M.tooltip(day, s, tromso, null, "light"), "Light until " + hhmm(d.next) + " (sunset)")
    }
    // 75 N on 5 February the sun grazes the horizon for ten minutes around noon: the mode is the altitude at every
    // minute, with no flash from an event two minutes off.
    function test_sun_grazing_horizon_has_no_flash() {
        const p = { lat: 75, lon: 0 }
        for (let t = Date.UTC(2026, 1, 5, 11, 50); t <= Date.UTC(2026, 1, 5, 12, 10); t += 60000)
            checkNext(t, p)
        const r = checkNext(Date.UTC(2026, 1, 5, 11, 58), p)
        compare(r.mode, "dark"); compare(r.why, "sunrise")
    }
    // A night of under seven minutes (65.727 N, 20 June, sun below the horizon from about 23:58Z): the change is not
    // stepped over, so the next change and the tooltip hold still from minute to minute until it comes.
    function test_sun_short_night_is_found_and_stable() {
        const s = { mode: "sun", schedule: dflt }
        const p = { lat: 65.727, lon: 0 }
        const from = Date.UTC(2026, 5, 20, 21, 0)
        const first = M.sun(from, p, "07:00", "20:00")
        compare(first.mode, "light"); compare(first.why, "sunset")
        near(first.next, "2026-06-20T23:58:00Z")
        verify(!Sun.isUp(first.next + 120000, p.lat, p.lon))
        verify(Sun.isUp(first.next + 6 * 60000 + 36000 + 60000, p.lat, p.lon))
        const text = M.tooltip(from, s, p, null, "light")
        compare(text, "Light until " + hhmm(first.next) + " (sunset)")
        for (let t = from; t < first.next - 60000; t += 60000) {
            compare(M.sun(t, p, "07:00", "20:00").next, first.next, new Date(t).toISOString())
            compare(M.tooltip(t, s, p, null, "light"), text)
            compare(M.flip(t, s, p, "light").until, first.next)
        }
        // In the night itself the sunrise a few minutes on is the next change.
        const dark = M.sun(first.next + 60000, p, "07:00", "20:00")
        compare(dark.mode, "dark"); compare(dark.why, "sunrise")
        verify(dark.next - first.next < 600000)
    }
    // A flip lasts exactly to the automatic mode's next change, whatever that is: even the sunrise of a day of a
    // minute (75.00341 N, 5 February, off noon by the drifting declination).
    function test_flip_until_is_the_next_change() {
        const s = { mode: "sun", schedule: dflt }
        for (const [loc, now] of [[tromso, Date.UTC(2026, 6, 24, 12, 0)], [tromso, Date.UTC(2026, 4, 17, 22, 30)],
                                  [ams, amsMidday], [{ lat: 75, lon: 0 }, Date.UTC(2026, 1, 5, 11, 58)],
                                  [{ lat: 75.00341, lon: 0 }, Date.parse("2026-02-05T09:13:56.859Z")]]) {
            const a = M.auto(now, s, loc)
            const o = M.flip(now, s, loc, a.mode)
            // Found without nextChange: isUp scanned every five seconds, so not even that day is stepped over, its
            // first other step bisected to the ms.
            const up = Sun.isUp(now, loc.lat, loc.lon)
            let lo = now, hi = now + 5000
            while (Sun.isUp(hi, loc.lat, loc.lon) === up && hi < now + 36 * 3600000) { lo = hi; hi += 5000 }
            verify(Sun.isUp(hi, loc.lat, loc.lon) !== up)
            while (hi - lo > 1) {
                const mid = Math.floor((lo + hi) / 2)
                if (Sun.isUp(mid, loc.lat, loc.lon) === up) lo = mid; else hi = mid
            }
            compare(o.until, hi)
            compare(o.mode === a.mode, false)
        }
    }
    // At mid-latitudes the altitude's changes are sunTimes' events to a couple of minutes, in both hemispheres.
    function test_sun_next_agrees_with_the_events_at_mid_latitudes() {
        for (const loc of [ams, { lat: 21.3, lon: -157.86 }]) {
            for (let month = 1; month <= 12; month++) {
                const e = Sun.sunTimes(2026, month, 15, loc.lat, loc.lon)
                const r = M.sun(e.rise - 3600000, loc, "07:00", "20:00")
                compare(r.mode, "dark"); compare(r.why, "sunrise"); close(r.next, e.rise)
                const q = M.sun(e.set - 3600000, loc, "07:00", "20:00")
                compare(q.mode, "light"); compare(q.why, "sunset"); close(q.next, e.set)
            }
        }
    }

    // What the shell decides about running `gutter theme apply` and `gutter hypr`.
    function test_may_start_never_when_inert() {
        for (const apply of [false, true])
            for (const hypr of [false, true])
                verify(!M.mayStart(true, apply, hypr))
    }
    function test_may_start_never_at_once() {
        verify(M.mayStart(false, false, false))
        verify(!M.mayStart(false, true, false))
        verify(!M.mayStart(false, false, true))
        verify(!M.mayStart(false, true, true))
    }
    // The shell's two runners, as a model: a start needs mayStart; the exit of either asks for both again, apply
    // first (evaluate before refreshHypr), as ThemeMode.qml does. What is owed while one runs is run afterwards.
    function runnerModel() {
        return {
            applyRunning: false, hyprRunning: false, applyOwed: false, hypr: { pending: false, failed: false },
            started: [], inert: false,
            evaluate() {
                if (this.applyOwed && M.mayStart(this.inert, this.applyRunning, this.hyprRunning)) {
                    this.applyOwed = false; this.applyRunning = true; this.started.push("apply")
                }
            },
            refreshHypr() {
                if (this.hypr.pending && M.mayStart(this.inert, this.applyRunning, this.hyprRunning)) {
                    this.hypr = M.hyprState(this.hypr, "start"); this.hyprRunning = true; this.started.push("hypr")
                }
            },
            settings() { this.hypr = M.hyprState(this.hypr, "settings"); this.refreshHypr() },
            flip() { this.applyOwed = true; this.evaluate() },
            exit(which) {
                if (which === "apply") this.applyRunning = false; else this.hyprRunning = false
                this.evaluate(); this.refreshHypr()
            }
        }
    }
    function test_runners_a_settings_load_during_an_apply_runs_after_it() {
        const m = runnerModel()
        m.flip()
        m.settings()
        compare(m.started, ["apply"])
        m.exit("apply")
        compare(m.started, ["apply", "hypr"])
        m.exit("hypr")
        compare(m.started, ["apply", "hypr"])
        verify(!m.hypr.pending)
    }
    function test_runners_a_flip_during_hypr_applies_after_it() {
        const m = runnerModel()
        m.settings()
        m.flip()
        compare(m.started, ["hypr"])
        m.exit("hypr")
        compare(m.started, ["hypr", "apply"])
    }
    function test_runners_both_owed_apply_goes_first() {
        const m = runnerModel()
        m.settings(); m.flip(); m.settings()                       // hypr runs; apply and another hypr are owed
        m.exit("hypr")
        compare(m.started, ["hypr", "apply"])
        m.exit("apply")
        compare(m.started, ["hypr", "apply", "hypr"])
    }
    function test_runners_inert_starts_nothing() {
        const m = runnerModel()
        m.inert = true
        m.flip(); m.settings(); m.exit("apply")
        compare(m.started, [])
        verify(m.applyOwed && m.hypr.pending)
    }

    // The ThemeMode.qml guards are structural (a QML singleton is not loaded here); tests/test_themeguard.py
    // checks that every start sits behind them.

    // A failure is logged once and notified once: the tool notifies its own, the shell the rest.
    function test_failure_same_message_again_is_silent() {
        compare(M.failure("boom", "boom", true), { log: false, notify: false })
        compare(M.failure("boom", "boom", false), { log: false, notify: false })
    }
    function test_failure_new_message_is_logged_and_notified_unless_the_tool_did() {
        compare(M.failure("", "boom", true), { log: true, notify: false })
        compare(M.failure("", "cannot run /x/gutter", false), { log: true, notify: true })
    }
    // A different failure of a retry (the tool ran with GUTTER_NO_NOTIFY) is notified by the shell.
    function test_failure_different_message_after_an_earlier_one_is_notified() {
        compare(M.failure("first", "second", false), { log: true, notify: true })
    }
    // Both runners failing with the same message (a tool that cannot start) notify it once.
    function test_failure_the_other_runners_message_is_not_notified_again() {
        compare(M.failure("", "cannot run /x/gutter", false, "cannot run /x/gutter"), { log: true, notify: false })
        compare(M.failure("", "cannot run /x/gutter", false, "other"), { log: true, notify: true })
        compare(M.failure("", "cannot run /x/gutter", false, ""), { log: true, notify: true })
    }

    // The message of a run that exited with a status.
    function test_exit_message_a_retry_that_env_could_not_start() {
        compare(M.exitMessage(127, false, "/x/gutter", "env: no such file", "gutter hypr"), "cannot run /x/gutter")
        compare(M.exitMessage(126, false, "/x/gutter", "", "gutter hypr"), "cannot run /x/gutter")
    }
    // A first run is not through env: 126 and 127 are the tool's own statuses there, as is anything on a retry
    // that is not 126 or 127.
    function test_exit_message_otherwise_is_stderr_or_the_status() {
        compare(M.exitMessage(127, true, "/x/gutter", " boom\n", "gutter hypr"), "boom")
        compare(M.exitMessage(127, true, "/x/gutter", "", "gutter hypr"), "gutter hypr exited with status 127")
        compare(M.exitMessage(1, false, "/x/gutter", "hyprctl reload failed\n", "gutter theme apply dark"), "hyprctl reload failed")
        compare(M.exitMessage(3, false, "/x/gutter", "", "gutter theme apply dark"), "gutter theme apply dark exited with status 3")
    }
}
