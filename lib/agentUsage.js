.pragma library

// Formatting and plan-limit logic for the Agents tab. The numbers come from scripts/agent-usage.py
// (transcripts, API-price value) and scripts/agent-statusline.sh (Claude Code's rate_limits).

var NEAR_LIMIT = [80, 95]; // % of a plan window that raises the "near a limit" pill, once each per window

function grouped(n) {
    let s = String(n), out = "";
    while (s.length > 3) {
        out = "," + s.slice(-3) + out;
        s = s.slice(0, -3);
    }
    return s + out;
}

function money(v) {
    const n = Number(v) || 0;
    if (n >= 10000)
        return `$${(n / 1000).toFixed(1)}K`;
    if (n >= 1000)
        return `$${grouped(Math.round(n))}`;
    return `$${n.toFixed(2)}`;
}

function tokens(v) {
    const n = Number(v) || 0;
    if (n >= 1e9)
        return `${+(n / 1e9).toFixed(1)}B`;
    if (n >= 1e6)
        return `${n >= 1e7 ? Math.round(n / 1e6) : +(n / 1e6).toFixed(1)}M`;
    if (n >= 1e3)
        return `${Math.round(n / 1e3)}K`;
    return String(Math.round(n));
}

// "2h 36m", "36m", "3d 4h"; seconds.
function duration(sec) {
    const s = Math.max(0, Math.round(sec));
    const m = Math.floor(s / 60);
    const h = Math.floor(m / 60);
    if (h >= 24)
        return `${Math.floor(h / 24)}d ${h % 24}h`;
    if (h > 0)
        return `${h}h ${m % 60}m`;
    return `${Math.max(1, m)}m`;
}

// "4:08", "1:02:03"; ms.
function clock(ms) {
    const s = Math.max(0, Math.floor(ms / 1000));
    const h = Math.floor(s / 3600);
    const m = Math.floor(s / 60) % 60;
    const ss = String(s % 60).padStart(2, "0");
    return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
}

// One plan window from the bridge file: { pct (0-100), resetsIn (s), renewed }. Once its reset has passed
// the last reading is of the previous window and the new one's use is not known until Claude Code reports
// again, so it is { pct: null, renewed: true }, never 0. null when Claude Code never reported the window.
function window_(raw, nowSec) {
    if (!raw || typeof raw.used_percentage !== "number")
        return null;
    const at = Number(raw.resets_at) || 0;
    if (at > 0 && at <= nowSec)
        return { pct: null, resetsIn: -1, renewed: true };
    return { pct: Math.max(0, Math.min(100, raw.used_percentage)), resetsIn: at > 0 ? at - nowSec : -1, renewed: false };
}

// `week` and the weekly limit of one model (`model`, with its name; the usage endpoint reports it, the
// status line does not) are windows as above.
function limits(file, nowMs) {
    const rl = file?.rate_limits ?? null;
    const now = nowMs / 1000;
    const model = window_(rl?.seven_day_model, now);
    if (model)
        model.name = String(rl.seven_day_model.name ?? "");
    return { session: window_(rl?.five_hour, now), week: window_(rl?.seven_day, now), model: model, seenAt: file?.t ?? 0 };
}

// The newer of two limits files (the status-line bridge's and the usage endpoint's), by the time each was
// written; either may be missing.
function newest(a, b) {
    if (!a || !(a.t > 0))
        return b && b.t > 0 ? b : (a ?? b ?? null);
    return b && b.t > a.t ? b : a;
}

var FETCH_EVERY = 180000; // ms between usage requests
var FETCH_MAX = 1800000; // longest wait after failures

// Wait before the next usage request: the usual interval, doubling per failure in a row up to FETCH_MAX, and at
// least as long as the server's Retry-After (s) when it sent one.
function fetchDelay(failures, retryAfter) {
    const backoff = Math.min(FETCH_MAX, FETCH_EVERY * Math.pow(2, Math.max(0, Math.min(failures, 10))));
    return Math.min(FETCH_MAX, Math.max(backoff, (Number(retryAfter) || 0) * 1000));
}

// How far through its window a limit is (0-1), for the pace mark: use left of it is on track.
function pace(w, windowSec) {
    if (!w || w.renewed || !(w.resetsIn > 0))
        return -1;
    return Math.max(0, Math.min(1, 1 - w.resetsIn / windowSec));
}

// The threshold a window just crossed going from `prev` to `pct`, or 0.
function crossed(prev, pct) {
    let hit = 0;
    for (const t of NEAR_LIMIT)
        if (prev < t && pct >= t)
            hit = t;
    return hit;
}

// Near-limit alerts for one limits reading. `seen` maps a window key (name + reset time) to the highest %
// already alerted on; `wins` is [{ key, pct }]. A key missing from `seen` is seeded from its pct on the
// first reading after start-up (no alert for a window already under way), and from 0 later (a new window).
// Returns { seen, hits }: `seen` holds only `wins`' keys, `hits[i]` is the threshold `wins[i]` crossed or 0.
function limitAlerts(seen, wins, first) {
    const next = {};
    const hits = wins.map(w => {
        const prev = seen?.[w.key] ?? (first ? w.pct : 0);
        next[w.key] = Math.max(prev, w.pct);
        return crossed(prev, w.pct);
    });
    return { seen: next, hits: hits };
}

// 0 (nothing) to 4 (busiest day) for the heatmap.
function heatLevel(v, max) {
    if (!(v > 0) || !(max > 0))
        return 0;
    return Math.max(1, Math.min(4, Math.ceil(4 * v / max)));
}

function trendLabels(period) {
    if (period === "today")
        return ["00", "12", "23"];
    if (period === "week")
        return ["7 days ago", "", "Today"];
    return ["30 days ago", "15", "Today"];
}

function periodLabel(period) {
    return { today: "Today", week: "7 days", month: "30 days" }[period] ?? "Today";
}

// Why the plan limits are not there and what to do, from the usage script's last failure (`reason`: "unavailable"
// when there is no usable login, "network", "schema", an HTTP status, or "" before any run or after a good one):
// { title, hint }.
function limitsEmpty(reason) {
    switch (String(reason ?? "")) {
    case "unavailable":
    case "401":
    case "403":
        return { title: "No usable Claude login", hint: "Run claude in a terminal and sign in. Limits then load within a few minutes (Pro and Max plans only)." };
    case "network":
        return { title: "Can't reach Anthropic", hint: "Limits load by themselves once you are back online." };
    case "write":
        return { title: "Can't save limits", hint: "Gutter could not write its state file. Check that its state folder is writable." };
    case "429":
        return { title: "Anthropic is rate-limiting requests", hint: "Limits load again shortly." };
    case "schema":
        return { title: "Limits reply not recognised", hint: "Anthropic changed its usage reply. Update Gutter, or use Claude Code's status line." };
    default:
        return { title: "No plan limits yet", hint: "They load from your Claude login within a few minutes (Pro and Max plans only)." };
    }
}

// The row label of a window: the model's weekly limit is named for the week it belongs to, since the model's
// bare name says nothing.
function windowLabel(index, modelName) {
    return index === 0 ? "Session" : index === 1 ? "Week" : modelName ? `Week · ${modelName} model` : "Week · one model";
}
