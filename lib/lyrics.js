.pragma library

// Synced lyrics from lrclib.net: the LRC parser, the request URL, the on-disk cache's names and how an answer
// is turned into lines. Pure functions; services/Lyrics.qml does the request and the file access.
// Times are seconds, as in Mpris.

const LINE = /^\s*((?:\[\d+:\d{2}(?:[.:]\d+)?\])+)(.*)$/;
const OFFSET = /^\s*\[offset:\s*([+-]?\d+)\s*\]\s*$/i;
// Enhanced LRC puts a stamp before each word; only the line's own stamps count.
const WORD_STAMP = /<\d+:\d{2}(?:[.:]\d+)?>/g;

// `text` is an LRC file. A line with several stamps becomes several entries, `[offset:ms]` shifts every time
// by that many milliseconds EARLIER (LRC convention: a positive offset is subtracted, so [offset:500] makes a
// stamp of 10 s read 9.5 s), other tags ([ar:], [ti:] ...) and lines without a stamp are ignored, and a stamp
// with no text is kept (an instrumental gap). Sorted by time; equal times keep file order.
function parseLrc(text) {
    const out = [];
    let offset = 0;
    for (const raw of String(text ?? "").split(/\r?\n/)) {
        const o = OFFSET.exec(raw);
        if (o) {
            offset = Number(o[1]) / 1000;
            continue;
        }
        const m = LINE.exec(raw);
        if (!m)
            continue;
        const line = m[2].replace(WORD_STAMP, "").trim();
        const stamp = /\[(\d+):(\d{2})(?:[.:](\d+))?\]/g;
        let s;
        while ((s = stamp.exec(m[1])) !== null) {
            const frac = s[3] ? Number("0." + s[3]) : 0;
            out.push({ time: Number(s[1]) * 60 + Number(s[2]) + frac, text: line, order: out.length });
        }
    }
    out.sort((a, b) => a.time - b.time || a.order - b.order);
    return out.map(e => ({ time: e.time - offset, text: e.text }));
}

// Index of the last line that has started by `seconds` (time <= seconds), -1 before the first. No lookahead:
// the highlighted line is the one being sung at the position it is given.
function indexForTime(lines, seconds) {
    if (!lines)
        return -1;
    let lo = 0;
    let hi = lines.length;
    while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (lines[mid].time <= seconds)
            lo = mid + 1;
        else
            hi = mid;
    }
    return lo - 1;
}

// lrclib's exact-match lookup. The album and the duration (whole seconds) are left out when unknown (a length of
// 0 means the player does not report one).
function url(artist, title, album, length) {
    const q = [
        "artist_name=" + encodeURIComponent(artist ?? ""),
        "track_name=" + encodeURIComponent(title ?? "")
    ];
    if (album)
        q.push("album_name=" + encodeURIComponent(album));
    if (length > 0)
        q.push("duration=" + Math.round(length));
    return "https://lrclib.net/api/get?" + q.join("&");
}

// lrclib's fuzzy search, the fallback when the exact lookup finds nothing: title and artist only.
function searchUrl(artist, title) {
    return "https://lrclib.net/api/search?track_name=" + encodeURIComponent(title ?? "")
        + "&artist_name=" + encodeURIComponent(artist ?? "");
}

// The best of an lrclib search answer (a JSON array): among the entries with synced lyrics, the one whose duration
// is closest to `length` seconds, none of them more than 10 s off; with no known length (0) the first. null when
// nothing qualifies or the text is not an array.
function pickSearchResult(jsonText, length) {
    let list;
    try {
        list = JSON.parse(jsonText);
    } catch (e) {
        return null;
    }
    if (!Array.isArray(list))
        return null;
    const known = length > 0;
    let best = null;
    let bestDiff = Infinity;
    for (const r of list) {
        if (!r || typeof r !== "object" || r.instrumental === true
            || typeof r.syncedLyrics !== "string" || r.syncedLyrics.trim() === "")
            continue;
        if (!known)
            return r;
        if (typeof r.duration !== "number")
            continue;
        const diff = Math.abs(r.duration - length);
        if (diff <= 10 && diff < bestDiff) {
            best = r;
            bestDiff = diff;
        }
    }
    return best;
}

// The synced lyrics of an lrclib answer; [] for an instrumental, an answer with plain lyrics only, and
// anything that is not an lrclib JSON object.
function parseResponse(jsonText) {
    let json;
    try {
        json = JSON.parse(jsonText);
    } catch (e) {
        return [];
    }
    if (!json || typeof json !== "object" || json.instrumental === true)
        return [];
    return typeof json.syncedLyrics === "string" ? parseLrc(json.syncedLyrics) : [];
}

// A file name for a track's cached answer: lower-case, no slash, the same for the same track (the length in
// whole seconds), different for different ones. Percent-encoding keeps any script distinct; "%" becomes "="
// (never produced by the encoding itself). A long name is cut and ends in a hash of the whole.
function cacheName(artist, title, album, length) {
    const key = [artist, title, album, Math.round(length) || 0].map(s => String(s ?? "").toLowerCase()).join("|");
    const name = encodeURIComponent(key).toLowerCase().replace(/%/g, "=");
    if (name.length <= 150)
        return name;
    let h = 5381;
    for (let i = 0; i < key.length; i++)
        h = ((h * 33) ^ key.charCodeAt(i)) >>> 0;
    return name.slice(0, 150) + "-" + h.toString(16);
}

// What to do with an answer to url(): the lines to show and the text to cache (null: do not cache). A 200 is
// cached as received, but only when it is JSON (a captive portal's page must not stick); a 404 is a miss,
// cached as {}; anything else (no network, timeout, 5xx, 429) is not an answer, so it is retried next time.
function settle(status, text) {
    if (status === 404)
        return { lines: [], cache: "{}" };
    if (status !== 200)
        return { lines: [], cache: null };
    try {
        JSON.parse(text);
    } catch (e) {
        return { lines: [], cache: null };
    }
    return { lines: parseResponse(text), cache: text };
}

// Whether the answer to url() calls for the fuzzy search: a 404, or an answer that is not an instrumental and has
// no synced lyrics. Failures (no network, 5xx) do not: the whole lookup is retried next time instead.
function wantsSearch(status, text) {
    if (status === 404)
        return true;
    if (status !== 200)
        return false;
    let json;
    try {
        json = JSON.parse(text);
    } catch (e) {
        return false;
    }
    if (!json || typeof json !== "object" || json.instrumental === true)
        return false;
    return parseResponse(text).length === 0;
}

// What to do with an answer to searchUrl(), as settle(): the chosen entry is cached as an /api/get answer
// would be; no match is a miss ({}); a failed or non-JSON answer is not cached.
function settleSearch(status, text, length) {
    if (status !== 200)
        return { lines: [], cache: null };
    try {
        JSON.parse(text);
    } catch (e) {
        return { lines: [], cache: null };
    }
    const r = pickSearchResult(text, length);
    if (!r)
        return { lines: [], cache: "{}" };
    const cache = JSON.stringify({ syncedLyrics: r.syncedLyrics });
    return { lines: parseResponse(cache), cache };
}

// The lines of a cached answer; null when the file does not hold JSON (then the request is made).
function fromCache(text) {
    try {
        JSON.parse(text);
    } catch (e) {
        return null;
    }
    return parseResponse(text);
}
