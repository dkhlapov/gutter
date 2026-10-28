.pragma library
.import "sun.js" as Sun

// Which mode the desktop should be in: from the sun, a schedule, a fixed setting or a manual flip. Pure: `now`
// is epoch ms and every time is local, via JS Date. Days are always stepped with `new Date(y, m, d + n, ...)`,
// never by adding 86400000, so a DST day keeps its real length.

function minutes(hhmm) {
    var p = String(hhmm).split(":");
    return Number(p[0]) * 60 + Number(p[1]);
}

function clockMinutes(t) {
    var d = new Date(t);
    return d.getHours() * 60 + d.getMinutes();
}

// A number that orders local days: the same for every instant of one calendar day.
function dayKey(t) {
    var d = new Date(t);
    return d.getFullYear() * 10000 + d.getMonth() * 100 + d.getDate();
}

// The first instant of the local day `offset` days after now's. A midnight that does not exist (DST that starts
// at 00:00) is not that instant: the days are found from noon, which always exists, and the instant is walked
// to from half a day before it.
function dayStart(now, offset) {
    var d = new Date(now);
    var noon = new Date(d.getFullYear(), d.getMonth(), d.getDate() + offset, 12).getTime();
    var key = dayKey(noon);
    var t = noon - 12 * 3600000;
    while (dayKey(t) < key)
        t += 60000;
    while (dayKey(t - 60000) === key)
        t -= 60000;
    return t;
}

// The instant of the clock time hhmm on the local day `offset` days after now's: the first minute of that day the
// clock reads hhmm or later. A time inside a DST gap (02:30 where the clocks jump from 02:00 to 03:00) is the
// instant the gap ends, not what `new Date(y, m, d, 2, 30)` makes of it (an hour on or back, as the engine
// pleases); a time that happens twice is its first pass.
function at(now, hhmm, offset) {
    var m = minutes(hhmm);
    var start = dayStart(now, offset);
    var end = dayStart(now, offset + 1);
    // Start m minutes after the day's start and walk off the length of any DST change on the way (a day is 23 or
    // 25 hours long there, so the start can already be past the day's end).
    var t = start + m * 60000;
    while (t < end && clockMinutes(t) < m)
        t += 60000;
    while (t - 60000 >= start && (t - 60000 >= end || clockMinutes(t - 60000) >= m))
        t -= 60000;
    return t;
}

function nextMidnight(now) {
    return dayStart(now, 1);
}

// Light from lightHHMM to darkHHMM, wrapping past midnight. Equal times mean a fixed dark mode. The mode is the
// one the latest switch up to now set, so the clock going back or jumping forward at a DST change cannot switch
// it twice or skip a switch. The next change is the first switch after now that changes the mode: switches on one
// instant (both inside one DST gap) collapse to the later one, which may be no change at all.
function schedule(now, lightHHMM, darkHHMM) {
    var l = minutes(lightHHMM);
    var k = minutes(darkHHMM);
    if (l === k)
        return { mode: "dark", next: null };
    // Yesterday's to the day after tomorrow's switches (a gap day's can change nothing) in the order the clock names
    // them: at a tie the later one wins.
    var pair = l < k ? [["light", lightHHMM], ["dark", darkHHMM]] : [["dark", darkHHMM], ["light", lightHHMM]];
    var switches = [];
    for (var off = -1; off <= 2; off++) {
        switches.push({ t: at(now, pair[0][1], off), mode: pair[0][0], i: switches.length });
        switches.push({ t: at(now, pair[1][1], off), mode: pair[1][0], i: switches.length });
    }
    switches.sort(function (a, b) { return a.t - b.t || a.i - b.i; });
    var mode = "dark";
    var next = null;
    var i = 0;
    while (i < switches.length) {
        var j = i;
        while (j + 1 < switches.length && switches[j + 1].t === switches[i].t)
            j++;
        var after = switches[j].mode;
        if (switches[i].t <= now) {
            mode = after;
        } else if (after !== mode) {
            next = switches[i].t;
            break;
        }
        i = j + 1;
    }
    return { mode: mode, next: next };
}

// Light while the sun is up; the schedule without a location. Mode and next change both come from the sun's
// altitude (Sun.isUp), so they cannot disagree near the polar boundary, where a day's sunrise or sunset events can
// be missing or graze the horizon. With no change within a day and a half (the sun stays up or down) the next
// midnight.
function sun(now, loc, lightHHMM, darkHHMM) {
    if (!loc) {
        var s = schedule(now, lightHHMM, darkHHMM);
        return { mode: s.mode, next: s.next, why: "schedule" };
    }
    var light = Sun.isUp(now, loc.lat, loc.lon);
    var mode = light ? "light" : "dark";
    var next = Sun.nextChange(now, loc.lat, loc.lon, 36 * 3600000);
    if (next === null)
        return { mode: mode, next: nextMidnight(now), why: "polar" };
    return { mode: mode, next: next, why: light ? "sunset" : "sunrise" };
}

// settings = { mode, schedule: { light, dark } }
function auto(now, settings, loc) {
    if (settings.mode === "light" || settings.mode === "dark")
        return { mode: settings.mode, next: null, why: "fixed" };
    if (settings.mode === "schedule") {
        var s = schedule(now, settings.schedule.light, settings.schedule.dark);
        return { mode: s.mode, next: s.next, why: "schedule" };
    }
    return sun(now, loc, settings.schedule.light, settings.schedule.dark);
}

// Override shape { mode, until: ms|null, setFor }. It wins while it has not expired and theme.mode is still
// what it was at the flip; otherwise the returned override is null and the automatic mode applies.
function wanted(now, settings, loc, override) {
    if (override && (override.until === null || override.until > now) && override.setFor === settings.mode)
        return { mode: override.mode, override: override };
    return { mode: auto(now, settings, loc).mode, override: null };
}

// The override that shows the other mode, or null when that is the automatic mode (flipping back clears).
function flip(now, settings, loc, currentMode) {
    var other = currentMode === "light" ? "dark" : "light";
    var a = auto(now, settings, loc);
    if (other === a.mode)
        return null;
    return { mode: other, until: a.next, setFor: settings.mode };
}

// failedMode is the mode of the last apply when it failed, else "": theme.json is written before the apps, so a run
// that failed in an app already shows the wanted mode and is retried only through it.
function needsApply(appliedMode, wantedMode, failedMode) {
    return appliedMode === null || appliedMode !== wantedMode || failedMode === wantedMode;
}

// Whether `gutter theme apply` or `gutter hypr` may be started now. Never in the smoke/gallery instance (inert),
// which must leave the real desktop alone, and never while either one runs: two at once could write an older mode
// last. What is owed meanwhile stays owed: both runners' exits ask again.
function mayStart(inert, applyRunning, hyprRunning) {
    return !inert && !applyRunning && !hyprRunning;
}

// What to do with a failure message of a run, given the last one logged: { log, notify }. The same message again
// (a lasting failure retried every minute) does neither. A new one is logged and notified, unless the tool
// notified it itself (toolNotified: it was not started with GUTTER_NO_NOTIFY and got as far as failing) or the
// other runner's last failure is the same message (otherMessage: a tool that cannot start fails both runners at
// once and says so once). If the apply recovers and then fails again with the message hypr is still failing with,
// it is only logged.
function failure(lastMessage, message, toolNotified, otherMessage) {
    if (message === lastMessage)
        return { log: false, notify: false };
    return { log: true, notify: !toolNotified && message !== otherMessage };
}

// The failure message of a run that exited with `code`: the tool could not be started, else its stderr, else the
// bare status of `what` (the command's name). A retry runs through `env`, which exits 126 or 127 when it cannot
// start the tool: the same failure as the "cannot run" of the run before, so it is worded the same.
function exitMessage(code, toolNotifies, tool, stderr, what) {
    if (!toolNotifies && (code === 126 || code === 127))
        return "cannot run " + tool;
    return String(stderr).trim() || what + " exited with status " + code;
}

// `gutter hypr` bookkeeping, { pending, failed }: pending is a settings load not yet written to Hyprland, failed a
// run that failed. Returns the state after "settings" (a settings load or reload), "start" (a run started), "failed"
// (it failed) or "tick". A failure is owed another run only at the next tick, so a lasting one runs once a minute.
function hyprState(state, event) {
    switch (event) {
    case "settings":
        return { pending: true, failed: state.failed };
    case "start":
        return { pending: false, failed: false };
    case "failed":
        return { pending: state.pending, failed: true };
    case "tick":
        return { pending: state.pending || state.failed, failed: false };
    }
    return state;
}

function pad(n) {
    return n < 10 ? "0" + n : String(n);
}

function clock(ms) {
    var d = new Date(ms);
    return pad(d.getHours()) + ":" + pad(d.getMinutes());
}

var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

// The clock time of ms as seen from now: with its weekday when it is a day or more away, where a bare HH:MM
// would read as today's or tomorrow's (a sun that stays up nearly two days).
function clockFrom(now, ms) {
    return ms - now >= 86400000 ? WEEKDAYS[new Date(ms).getDay()] + " " + clock(ms) : clock(ms);
}

// "Dark until 07:12 (sunrise)", "Light until 20:00", "Dark (fixed)"; a change a day or more away has its weekday,
// "Light until Sun 00:38 (sunset)".
function tooltip(now, settings, loc, override, mode) {
    var name = mode === "light" ? "Light" : "Dark";
    var a = auto(now, settings, loc);
    var until = override ? override.until : a.next;
    if (until === null || until === undefined)
        return name + " (fixed)";
    if (override) {
        // An override that ends where the automatic mode is the same anyway (a flip to dark held to sunset) changes
        // nothing at until: name the automatic mode's next change from there instead.
        var after = auto(until, settings, loc);
        if (after.mode === override.mode)
            return tooltip(until, settings, loc, null, mode);
    }
    // The automatic mode is a sun that stays up or down; an override held to the next midnight says so too.
    var polar = a.why === "polar" ? (a.mode === "light" ? " (polar day)" : " (polar night)") : "";
    if (!override && polar)
        return name + polar;
    var text = name + " until " + clockFrom(now, until);
    if ((a.why === "sunrise" || a.why === "sunset") && a.next === until)
        text += " (" + a.why + ")";
    else if (override && polar && a.next === until)
        text += polar;
    return text;
}

function isLocation(loc) {
    return loc !== null && typeof loc === "object"
        && typeof loc.lat === "number" && isFinite(loc.lat) && Math.abs(loc.lat) <= 90
        && typeof loc.lon === "number" && isFinite(loc.lon) && Math.abs(loc.lon) <= 180;
}

function isOverride(o) {
    return o !== null && typeof o === "object"
        && (o.mode === "light" || o.mode === "dark")
        && (o.until === null || (typeof o.until === "number" && isFinite(o.until)))
        && typeof o.setFor === "string";
}

// theme-auto.json ({ version: 1, location, override }) as { location, override, error }. A missing file (null)
// or an invalid one is empty; an invalid location or override alone is dropped. error is "" when nothing was
// wrong with the file as a whole.
function parseAuto(text) {
    var empty = { location: null, override: null, error: "" };
    if (text === null || text === undefined)
        return empty;
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        empty.error = "not valid JSON";
        return empty;
    }
    if (data === null || typeof data !== "object" || Array.isArray(data) || data.version !== 1) {
        empty.error = "not a version 1 file";
        return empty;
    }
    return {
        location: isLocation(data.location) ? { lat: data.location.lat, lon: data.location.lon } : null,
        override: isOverride(data.override)
            ? { mode: data.override.mode, until: data.override.until, setFor: data.override.setFor }
            : null,
        error: ""
    };
}

function autoText(location, override) {
    return JSON.stringify({ version: 1, location: location, override: override }, null, 2) + "\n";
}

function sameLocation(a, b) {
    return a === b || (a !== null && b !== null && a.lat === b.lat && a.lon === b.lon);
}
