.pragma library

var PRESETS = [1, 5, 10, 25];
var MAX_NOTES = 8;
var MAX_TIMER_MS = 24 * 60 * 60 * 1000;

function pad(n) {
    return n < 10 ? "0" + n : String(n);
}

// Timer digits: "4:59", "1:02:03". Rounds up, so a timer shows 0:00 only when it is done.
function clock(ms) {
    const s = Math.max(0, Math.ceil((ms || 0) / 1000));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    return h > 0 ? `${h}:${pad(m)}:${pad(s % 60)}` : `${m}:${pad(s % 60)}`;
}

// Stopwatch digits with tenths: "0:07.3", "1:02:03.4". Rounds down.
function stopwatchClock(ms) {
    const t = Math.max(0, Math.floor((ms || 0) / 100));
    const s = Math.floor(t / 10);
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const body = h > 0 ? `${h}:${pad(m)}:${pad(s % 60)}` : `${m}:${pad(s % 60)}`;
    return `${body}.${t % 10}`;
}

// "5 min", "1 h 30 min", "45 s".
function spoken(ms) {
    const s = Math.round(Math.max(0, ms || 0) / 1000);
    if (s < 60)
        return `${s} s`;
    // Rounded to whole minutes first, so 59 min 30 s reads "1 h", never "60 min".
    const minutes = Math.round(s / 60);
    const h = Math.floor(minutes / 60);
    const m = minutes % 60;
    if (h === 0)
        return `${m} min`;
    return m > 0 ? `${h} h ${m} min` : `${h} h`;
}

// Timer: { state: "idle" | "running" | "paused" | "done", durationMs, endsAt, leftMs }.
// endsAt is set while running; leftMs while paused.
function timerIdle() {
    return { state: "idle", durationMs: 0, endsAt: 0, leftMs: 0 };
}

function timerStart(ms, now) {
    const d = Math.max(0, Math.min(MAX_TIMER_MS, Math.round(ms)));
    if (d === 0)
        return timerIdle();
    return { state: "running", durationMs: d, endsAt: now + d, leftMs: 0 };
}

function timerLeft(t, now) {
    if (t.state === "running")
        return Math.max(0, t.endsAt - now);
    if (t.state === "paused")
        return t.leftMs;
    return 0;
}

// 1 when just started, 0 when done.
function timerFraction(t, now) {
    return t.durationMs > 0 ? timerLeft(t, now) / t.durationMs : 0;
}

function timerPause(t, now) {
    if (t.state !== "running")
        return t;
    return { state: "paused", durationMs: t.durationMs, endsAt: 0, leftMs: timerLeft(t, now) };
}

function timerResume(t, now) {
    if (t.state !== "paused")
        return t;
    return { state: "running", durationMs: t.durationMs, endsAt: now + t.leftMs, leftMs: 0 };
}

function timerToggle(t, now) {
    return t.state === "running" ? timerPause(t, now) : timerResume(t, now);
}

// +1 min while running or paused also lengthens the total, so the ring stays proportional.
function timerAdd(t, ms, now) {
    if (t.state === "running") {
        const left = Math.min(MAX_TIMER_MS, timerLeft(t, now) + ms);
        return { state: "running", durationMs: Math.min(MAX_TIMER_MS, t.durationMs + ms), endsAt: now + left, leftMs: 0 };
    }
    if (t.state === "paused")
        return { state: "paused", durationMs: Math.min(MAX_TIMER_MS, t.durationMs + ms), endsAt: 0, leftMs: Math.min(MAX_TIMER_MS, t.leftMs + ms) };
    return timerStart(ms, now);
}

// A running timer whose end has passed becomes "done"; anything else is returned unchanged.
function timerCheck(t, now) {
    if (t.state === "running" && now >= t.endsAt)
        return { state: "done", durationMs: t.durationMs, endsAt: 0, leftMs: 0 };
    return t;
}

// Stopwatch: { running, startedAt, accumulatedMs, laps: [ms, …] (newest first) }.
function stopwatchIdle() {
    return { running: false, startedAt: 0, accumulatedMs: 0, laps: [] };
}

function stopwatchElapsed(sw, now) {
    return sw.accumulatedMs + (sw.running ? Math.max(0, now - sw.startedAt) : 0);
}

function stopwatchToggle(sw, now) {
    if (sw.running)
        return { running: false, startedAt: 0, accumulatedMs: stopwatchElapsed(sw, now), laps: sw.laps };
    return { running: true, startedAt: now, accumulatedMs: sw.accumulatedMs, laps: sw.laps };
}

// Records the total elapsed time at the moment of the lap.
function stopwatchLap(sw, now) {
    if (!sw.running)
        return sw;
    return Object.assign({}, sw, { laps: [stopwatchElapsed(sw, now)].concat(sw.laps) });
}

function stopwatchActive(sw) {
    return sw.running || sw.accumulatedMs > 0;
}

// Notes: { notes: [{ text }], current }. Always at least one note.
function notesEmpty() {
    return { notes: [{ text: "" }], current: 0 };
}

function clampIndex(i, n) {
    return Math.max(0, Math.min(n - 1, typeof i === "number" && isFinite(i) ? Math.round(i) : 0));
}

// Returns null when the text is not valid JSON, so the caller can keep what it has.
function notesParse(text) {
    let raw;
    try {
        raw = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!raw || typeof raw !== "object" || !Array.isArray(raw.notes))
        return notesEmpty();
    const notes = raw.notes
        .filter(n => n && typeof n === "object" && typeof n.text === "string")
        .slice(0, MAX_NOTES)
        .map(n => ({ text: n.text }));
    if (notes.length === 0)
        return notesEmpty();
    return { notes, current: clampIndex(raw.current, notes.length) };
}

function notesTitle(text, index) {
    const first = (text || "").split("\n").map(l => l.trim()).find(l => l !== "");
    return first ? first.replace(/^#+\s*/, "") || first : `Note ${index + 1}`;
}

function notesSetText(s, index, text) {
    const notes = s.notes.map((n, i) => i === index ? { text } : n);
    return { notes, current: s.current };
}

function notesAdd(s) {
    if (s.notes.length >= MAX_NOTES)
        return s;
    return { notes: s.notes.concat([{ text: "" }]), current: s.notes.length };
}

// Closing the last note clears it instead.
function notesRemove(s, index) {
    if (s.notes.length <= 1)
        return notesEmpty();
    const notes = s.notes.filter((n, i) => i !== index);
    const current = index < s.current || s.current >= notes.length ? s.current - 1 : s.current;
    return { notes, current: clampIndex(current, notes.length) };
}

function notesSelect(s, index) {
    return { notes: s.notes, current: clampIndex(index, s.notes.length) };
}
