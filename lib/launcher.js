.pragma library

var MAX_USAGE = 2000;
// A launch count never grows past this, so one app cannot pile up history that fades for months.
var MAX_COUNT = 1000;
var DAY_MS = 86400000;
var HALF_LIFE_DAYS = 14;
// The most a launch history can add to a match score. Kept well below the gap between a prefix match and a mid-word
// match (about 18 for two letters), so typing what you mean beats what you ran most. A match on another field than
// the name gets its history scaled by SECONDARY_WEIGHT too.
var HISTORY_CAP = 10;
var HISTORY_WEIGHT = 8;
// Matches on the generic name, keywords, id and comment count for half of a match on the name.
var SECONDARY_WEIGHT = 0.5;

// "/lock" is a command; anything else searches apps. A bare "/" is a command with no text yet.
function parse(query) {
    const s = String(query === undefined || query === null ? "" : query).trim();
    if (s.charAt(0) === "/")
        return { mode: "command", text: s.slice(1).trim() };
    return { mode: "apps", text: s };
}

function isWordStart(h, i) {
    if (i === 0)
        return true;
    const c = h.charAt(i - 1);
    return c === " " || c === "-" || c === "_" || c === ".";
}

// Greedy left-to-right subsequence match, case-insensitive. -1 when the needle is not a subsequence of the haystack,
// 0 for an empty needle, else a positive score: 10 per matched character, bonuses for the first character, word
// starts and consecutive matches, a small penalty per skipped character. Never a regular expression.
function fuzzy(needle, haystack) {
    const n = String(needle).toLowerCase();
    const h = String(haystack).toLowerCase();
    if (n.length === 0)
        return 0;
    if (n.length > h.length)
        return -1;
    let score = 0;
    let hi = 0;
    let prev = -2;
    for (let ni = 0; ni < n.length; ni++) {
        const c = n.charAt(ni);
        let found = -1;
        for (let i = hi; i < h.length; i++) {
            if (h.charAt(i) === c) {
                found = i;
                break;
            }
        }
        if (found === -1)
            return -1;
        score += 10;
        if (found === 0)
            score += 15;
        else if (isWordStart(h, found))
            score += 8;
        if (found === prev + 1)
            score += 6;
        score -= found - hi;
        prev = found;
        hi = found + 1;
    }
    return Math.max(1, score);
}

function isNum(x) {
    return typeof x === "number" && isFinite(x);
}

// Launches weighted by recency: the count halves every 14 days. A last-used time in the future counts as now.
function frecency(record, now) {
    if (!record || !isNum(record.count) || !isNum(record.last))
        return 0;
    const ageDays = Math.max(0, now - record.last) / DAY_MS;
    return record.count * Math.pow(0.5, ageDays / HALF_LIFE_DAYS);
}

function own(obj, key) {
    return Object.prototype.hasOwnProperty.call(obj, key) ? obj[key] : undefined;
}

// A new usage object with one more launch of `id`; the input is left alone.
function bump(usage, id, now) {
    const out = {};
    for (const k of Object.keys(usage || {}))
        out[k] = usage[k];
    if (id === "__proto__")
        return out;
    const prev = own(out, id);
    out[id] = { count: Math.min(MAX_COUNT, (prev && isNum(prev.count) ? prev.count : 0) + 1), last: now };
    return out;
}

function history(usage, id, now) {
    return Math.min(HISTORY_CAP, HISTORY_WEIGHT * Math.log2(1 + frecency(own(usage || {}, id), now)));
}

function byName(a, b) {
    const x = String(a.name).toLowerCase();
    const y = String(b.name).toLowerCase();
    return x < y ? -1 : x > y ? 1 : 0;
}

// Best match of the query over an app's fields: { score, primary }, the score -1 for no match. `primary` says the
// score came from the name, not from one of the other fields.
function matchScore(q, app) {
    let best = fuzzy(q, app.name || "");
    let primary = true;
    const others = [app.genericName, app.id, app.comment].concat(app.keywords || []);
    for (const f of others) {
        if (!f)
            continue;
        const s = fuzzy(q, f) * SECONDARY_WEIGHT;
        if (s > best) {
            best = s;
            primary = false;
        }
    }
    return { score: best, primary: primary };
}

// Apps for a query, best first, at most `limit`. An empty query lists by frecency, then name.
function rank(apps, query, usage, now, limit) {
    const q = String(query === undefined || query === null ? "" : query).trim();
    const scored = [];
    for (const app of apps) {
        if (q === "") {
            scored.push({ app: app, score: frecency(own(usage || {}, app.id), now) });
            continue;
        }
        const m = matchScore(q, app);
        if (m.score > 0)
            scored.push({ app: app, score: m.score + history(usage, app.id, now) * (m.primary ? 1 : SECONDARY_WEIGHT) });
    }
    scored.sort((a, b) => b.score - a.score || byName(a.app, b.app));
    return scored.slice(0, limit).map(s => s.app);
}

// ---- Persisted state: { version: 1, apps: { id: { count, last } } } ----

// Null for anything that is not a version 1 usage file. Bad records are dropped; the most recent 2 000 are kept.
// A count is always clamped to MAX_COUNT. With `now`, a last-used time after it is clamped to it, before the cut: a
// bogus future time must not pin an entry in the kept 2 000.
function parseUsage(text, now) {
    let raw;
    try {
        raw = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (raw === null || typeof raw !== "object" || raw.version !== 1)
        return null;
    const apps = raw.apps;
    if (apps === null || typeof apps !== "object" || Array.isArray(apps))
        return null;
    const good = [];
    for (const id of Object.keys(apps)) {
        const r = apps[id];
        if (id === "__proto__" || r === null || typeof r !== "object")
            continue;
        if (!isNum(r.count) || r.count < 1 || !isNum(r.last))
            continue;
        good.push({ id: id, count: Math.min(r.count, MAX_COUNT), last: isNum(now) ? Math.min(r.last, now) : r.last });
    }
    good.sort((a, b) => b.last - a.last);
    const out = {};
    for (const g of good.slice(0, MAX_USAGE))
        out[g.id] = { count: g.count, last: g.last };
    return out;
}

function serializeUsage(usage) {
    return JSON.stringify({ version: 1, apps: usage });
}

// The argv to start an app: its own command, or the terminal's `-e` followed by it. An app without a command gives [].
function appCommand(app, terminal) {
    const c = app.command;
    // A string is not a list (it would split into characters), and the program must be a non-empty string.
    const cmd = c && typeof c !== "string" && isNum(c.length) && c.length >= 0 ? Array.from(c) : [];
    if (cmd.length === 0 || typeof cmd[0] !== "string" || cmd[0] === "")
        return [];
    if (!app.runInTerminal)
        return cmd;
    const t = String(terminal === undefined || terminal === null ? "" : terminal).trim();
    return [t === "" ? "foot" : t, "-e"].concat(cmd);
}
