.pragma library

var SYNODIC_DAYS = 29.530588853;
var REFERENCE_NEW_MOON = Date.UTC(2000, 0, 6, 18, 14);
var PHASES = ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous", "Full moon", "Waning gibbous", "Last quarter", "Waning crescent"];

function moonPhase(date) {
    const days = (date.getTime() - REFERENCE_NEW_MOON) / 86400000;
    const fraction = (((days % SYNODIC_DAYS) + SYNODIC_DAYS) % SYNODIC_DAYS) / SYNODIC_DAYS;
    return {
        name: PHASES[Math.round(fraction * 8) % 8],
        illumination: Math.round((1 - Math.cos(2 * Math.PI * fraction)) / 2 * 100)
    };
}

function span(ms) {
    const minutes = Math.max(0, Math.round(ms / 60000));
    const h = Math.floor(minutes / 60);
    const m = minutes % 60;
    if (h === 0)
        return `${m} m`;
    return m === 0 ? `${h} h` : `${h} h ${m} m`;
}

function fraction(ms, dayStartMs) {
    return Math.max(0, Math.min(1, (ms - dayStartMs) / 86400000));
}

// Midnight-to-midnight daylight track plus the "sets in / rises in" caption and the next sun event.
function daylight(nowMs, dayStartMs, today, tomorrow) {
    const out = { now: fraction(nowMs, dayStartMs), rise: null, set: null, caption: "", next: null };
    const rise = today ? today.sunrise : null;
    const set = today ? today.sunset : null;
    if (!rise || !set)
        return out;
    out.rise = fraction(rise.ms, dayStartMs);
    out.set = fraction(set.ms, dayStartMs);
    const length = span(set.ms - rise.ms);
    const nextRise = tomorrow ? tomorrow.sunrise : null;
    if (nowMs < rise.ms) {
        out.caption = `${length} · rises in ${span(rise.ms - nowMs)}`;
        out.next = { label: "Sunrise", text: rise.text };
    } else if (nowMs < set.ms) {
        out.caption = `${length} · sets in ${span(set.ms - nowMs)}`;
        out.next = { label: "Sunset", text: set.text };
    } else if (nextRise) {
        out.caption = `${length} · rises in ${span(nextRise.ms - nowMs)}`;
        out.next = { label: "Sunrise", text: nextRise.text };
    } else {
        out.caption = length;
    }
    return out;
}
