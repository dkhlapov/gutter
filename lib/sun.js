.pragma library

// The sun from the NOAA general solar position equations (as in the NOAA solar calculator spreadsheet). Pure: no
// clock and no locale. The shell uses isUp and nextChange (the sun's altitude). sunTimes, cosHourAngle and ITERATIONS
// are the NOAA sunrise and sunset reference only the tests compare that altitude logic against; the shell does not
// use them.

var RAD = Math.PI / 180;
var DAY_MS = 86400000;
// Sun centre at 90.833 degrees zenith: refraction plus the solar radius.
var ZENITH = 90.833;
var ITERATIONS = 3;

// Solar declination (radians) and equation of time (minutes) at the epoch ms t.
function position(t) {
    var T = (t / DAY_MS + 2440587.5 - 2451545) / 36525;
    var L0 = (280.46646 + T * (36000.76983 + T * 0.0003032)) % 360;
    var M = (357.52911 + T * (35999.05029 - 0.0001537 * T)) * RAD;
    var e = 0.016708634 - T * (0.000042037 + 0.0000001267 * T);
    var C = Math.sin(M) * (1.914602 - T * (0.004817 + 0.000014 * T))
        + Math.sin(2 * M) * (0.019993 - 0.000101 * T)
        + Math.sin(3 * M) * 0.000289;
    var omega = (125.04 - 1934.136 * T) * RAD;
    var lambda = (L0 + C - 0.00569 - 0.00478 * Math.sin(omega)) * RAD;
    var eps0 = 23 + (26 + (21.448 - T * (46.815 + T * (0.00059 - T * 0.001813))) / 60) / 60;
    var eps = (eps0 + 0.00256 * Math.cos(omega)) * RAD;
    var y = Math.tan(eps / 2) * Math.tan(eps / 2);
    var l0 = L0 * RAD;
    var eq = 4 / RAD * (y * Math.sin(2 * l0) - 2 * e * Math.sin(M)
        + 4 * e * y * Math.sin(M) * Math.cos(2 * l0)
        - 0.5 * y * y * Math.sin(4 * l0) - 1.25 * e * e * Math.sin(2 * M));
    return { decl: Math.asin(Math.sin(eps) * Math.sin(lambda)), eq: eq };
}

// cos of the hour angle of the horizon crossing at the position p.
function cosHourAngle(p, lat) {
    var phi = lat * RAD;
    return Math.cos(ZENITH * RAD) / (Math.cos(phi) * Math.cos(p.decl)) - Math.tan(phi) * Math.tan(p.decl);
}

// The NOAA event helper: sunrise and sunset for the solar date (month 1-12) around that date's solar noon at lon
// (degrees east), as epoch ms. The shell's mode does not come from it but from isUp (see nextChange). { rise, set,
// dayAllDay }: each is null when the sun does not cross the horizon on that side, which near the polar boundary can
// happen to one of them alone; dayAllDay is true when the missing event is a sun that stays up and false for one
// that stays down (with both missing, polar day and polar night). Each side is judged on its own: at the boundary
// a day's near-midnight sunrise or sunset can exist when the one at noon's side does not.
function sunTimes(year, month, day, lat, lon) {
    var midnight = Date.UTC(year, month - 1, day);
    var noon = midnight + (720 - 4 * lon) * 60000;
    var times = [];
    var missing = null; // dayAllDay of an event that does not exist
    for (var k = 0; k < 2; k++) {
        var sign = k === 0 ? -1 : 1; // rise before noon, set after
        var t = noon + sign * 6 * 3600000;
        var found = true;
        for (var i = 0; i < ITERATIONS; i++) {
            var p = position(t);
            var ci = cosHourAngle(p, lat);
            if (ci > 1 || ci < -1) {
                // This side alone has no event (the declination moves between sunrise and sunset).
                missing = ci < -1;
                found = false;
                break;
            }
            var h = Math.acos(ci) / RAD;
            t = midnight + (720 - 4 * lon + sign * 4 * h - p.eq) * 60000;
        }
        times.push(found ? Math.round(t) : null);
    }
    return { rise: times[0], set: times[1], dayAllDay: missing === null ? false : missing };
}

// Whether the sun centre is above the horizon (by the sunrise zenith) at the epoch ms t. Unlike sunTimes it has
// no missing cases, so it decides the mode even where the events of a day or two are incomplete.
function isUp(t, lat, lon) {
    return sinAltitude(t, lat, lon) > Math.cos(ZENITH * RAD);
}

// sin of the sun centre's geometric altitude at the epoch ms t.
function sinAltitude(t, lat, lon) {
    var p = position(t);
    var phi = lat * RAD;
    var utcMin = (t % DAY_MS) / 60000;
    var H = ((utcMin + p.eq + 4 * lon) / 4 - 180) * RAD;
    return Math.sin(phi) * Math.sin(p.decl) + Math.cos(phi) * Math.cos(p.decl) * Math.cos(H);
}

var STEP_MS = 600000;

var HALF_DAY_MS = DAY_MS / 2;
// Ternary steps that narrow a half-day window to under a millisecond: 43200000 * (2/3)^44 < 1.
var EXTREME_ITERATIONS = 44;

// The epoch ms of every highest and lowest point of the sun's altitude in (from, to]. Each is searched for in the
// half day centred on that day's hour angle 0 (the highest) or pi (the lowest), so the windows tile the time line.
// The extremes sit off hour angle 0 and pi because the declination drifts meanwhile (seconds at the polar circles,
// up to hours within a degree of the pole), but each window holds one extreme of its kind and none of the other at
// any latitude, so the search finds it, to within a fraction of a second (within seconds near the latitude where the
// highest and lowest merge): so close to it the altitude is flat to the last bits of a double. Where the drift
// outruns the turning sun (within about 0.1 degrees of a pole) the altitude has no extreme and the window's edge comes
// back, a harmless extra sample. Between two extremes the altitude rises or falls steadily, so it crosses the
// horizon at most once there.
function solarExtremes(from, to, lat, lon) {
    var out = [];
    for (var n = Math.floor(from / DAY_MS) - 1; n <= Math.floor(to / DAY_MS) + 1; n++) {
        for (var half = 0; half < 2; half++) {
            var t = n * DAY_MS + (half * 720 - 4 * lon) * 60000;
            for (var i = 0; i < 2; i++) // the equation of time is a few minutes, so two passes settle it
                t = n * DAY_MS + (half * 720 - 4 * lon - position(t).eq) * 60000;
            var lo = t - HALF_DAY_MS / 2, hi = t + HALF_DAY_MS / 2;
            if (hi <= from || lo > to)
                continue;
            var highest = half === 1;
            for (var j = 0; j < EXTREME_ITERATIONS; j++) {
                var a = lo + (hi - lo) / 3, b = hi - (hi - lo) / 3;
                if ((sinAltitude(a, lat, lon) < sinAltitude(b, lat, lon)) === highest)
                    lo = a;
                else
                    hi = b;
            }
            t = Math.round((lo + hi) / 2);
            if (t > from && t <= to)
                out.push(t);
        }
    }
    return out;
}

// The first epoch ms after `now` (within horizonMs) at which isUp differs from isUp(now), or null when the sun
// stays up or down that long. isUp is sampled every ten minutes and at each of the altitude's extremes; between two
// samples no extreme falls inside, so the altitude is monotone there and crosses the horizon at most once, and no
// change falls between samples unseen: not even a day or night of a minute near the polar boundary, which is centred
// on an extreme (only one shorter than the extreme's error could be: a fraction of a second, within seconds near the
// latitude where the extremes merge). The first sample that differs is bisected to the millisecond: at the returned
// instant the state has already changed.
function nextChange(now, lat, lon, horizonMs) {
    var state = isUp(now, lat, lon);
    var end = now + horizonMs;
    var samples = solarExtremes(now, end, lat, lon);
    for (var t = now + STEP_MS; t <= end; t += STEP_MS)
        samples.push(t);
    samples.sort(function (a, b) { return a - b; });
    var lo = now;
    for (var k = 0; k < samples.length; k++) {
        if (isUp(samples[k], lat, lon) !== state) {
            var hi = samples[k];
            while (hi - lo > 1) {
                var mid = Math.floor((lo + hi) / 2);
                if (isUp(mid, lat, lon) === state)
                    lo = mid;
                else
                    hi = mid;
            }
            return hi;
        }
        lo = samples[k];
    }
    return null;
}
