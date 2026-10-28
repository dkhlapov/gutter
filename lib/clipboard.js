.pragma library

var MAX_UNPINNED = 50;
var MAX_TEXT = 100000;
var PREVIEW_CHARS = 200;

var seq = 0;
var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

function decodeBase64(s) {
    const bytes = [];
    let acc = 0;
    let bits = 0;
    for (let i = 0; i < s.length; i++) {
        const v = B64.indexOf(s[i]);
        if (v === -1)
            continue;
        acc = (acc << 6) | v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            bytes.push((acc >> bits) & 0xff);
            acc &= (1 << bits) - 1;
        }
    }
    return bytes;
}

// UTF-8 bytes to a string; invalid or cut-off sequences become U+FFFD.
function utf8(bytes) {
    let out = "";
    let i = 0;
    while (i < bytes.length) {
        const b = bytes[i];
        let need = 0;
        let cp = 0;
        let min = 0;
        if (b < 0x80) {
            out += String.fromCharCode(b);
            i++;
            continue;
        } else if (b >= 0xc2 && b <= 0xdf) {
            need = 1;
            cp = b & 0x1f;
            min = 0x80;
        } else if (b >= 0xe0 && b <= 0xef) {
            need = 2;
            cp = b & 0x0f;
            min = 0x800;
        } else if (b >= 0xf0 && b <= 0xf4) {
            need = 3;
            cp = b & 0x07;
            min = 0x10000;
        } else {
            out += "�";
            i++;
            continue;
        }
        let ok = true;
        let j = 1;
        for (; j <= need; j++) {
            const c = bytes[i + j];
            if (c === undefined || (c & 0xc0) !== 0x80) {
                ok = false;
                break;
            }
            cp = (cp << 6) | (c & 0x3f);
        }
        if (!ok || cp < min || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) {
            out += "�";
            i += ok ? need + 1 : j;
            continue;
        }
        if (cp >= 0x10000) {
            const v = cp - 0x10000;
            out += String.fromCharCode(0xd800 + (v >> 10), 0xdc00 + (v & 0x3ff));
        } else {
            out += String.fromCharCode(cp);
        }
        i += need + 1;
    }
    return out;
}

// One line from scripts/clipboard-watch.sh: "t <base64 of the text>" or "i <path of a png>".
function parseLine(line) {
    const m = /^([ti]) (\S.*)$/.exec((line || "").replace(/\r?\n$/, ""));
    if (!m)
        return null;
    if (m[1] === "i")
        return { kind: "image", path: m[2] };
    const text = utf8(decodeBase64(m[2])).slice(0, MAX_TEXT);
    return text.trim() === "" ? null : { kind: "text", text };
}

function key(item) {
    return item.kind === "image" ? "i:" + item.path : "t:" + item.text;
}

// Newest first. Copying something already in the list moves it to the top (keeping a pin);
// the oldest unpinned items beyond `max` fall off and are returned in `evicted`.
function add(items, entry, now, max) {
    const limit = max || MAX_UNPINNED;
    const k = key(entry);
    const old = items.find(i => key(i) === k);
    const item = Object.assign({}, entry, { id: old ? old.id : `${now}-${seq++}`, t: now, pinned: old ? old.pinned : false });
    const rest = items.filter(i => key(i) !== k);
    const pinned = rest.filter(i => i.pinned);
    const loose = rest.filter(i => !i.pinned);
    const kept = item.pinned ? loose : [item].concat(loose);
    const keptLoose = kept.slice(0, limit);
    const evicted = kept.slice(limit);
    const list = item.pinned ? [item].concat(pinned) : pinned;
    return { items: pinnedFirst(list.concat(keptLoose)), evicted };
}

// Pinned items stay in front, each group newest first.
function pinnedFirst(items) {
    const byTime = (a, b) => b.t - a.t;
    return items.filter(i => i.pinned).sort(byTime).concat(items.filter(i => !i.pinned).sort(byTime));
}

function togglePin(items, id) {
    return pinnedFirst(items.map(i => i.id === id ? Object.assign({}, i, { pinned: !i.pinned }) : i));
}

function remove(items, id) {
    const gone = items.find(i => i.id === id);
    return { items: items.filter(i => i.id !== id), evicted: gone ? [gone] : [] };
}

// Drops everything unpinned.
function clear(items) {
    return { items: items.filter(i => i.pinned), evicted: items.filter(i => !i.pinned) };
}

// Substring match on text (case-insensitive); images match only an empty query.
function filter(items, query) {
    const q = (query || "").trim().toLowerCase();
    if (q === "")
        return items;
    return items.filter(i => i.kind === "text" && i.text.toLowerCase().indexOf(q) !== -1);
}

// "link", "colour" or "text" ("image" for pictures).
function type(item) {
    if (item.kind === "image")
        return "image";
    const t = item.text.trim();
    if (/^(https?|ftp):\/\/\S+$/i.test(t) || /^www\.\S+\.\S+$/i.test(t))
        return "link";
    if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(t))
        return "colour";
    return "text";
}

function colour(item) {
    return type(item) === "colour" ? item.text.trim() : "";
}

// Single-line preview: whitespace collapsed, cut with an ellipsis.
function preview(text, max) {
    const limit = max || PREVIEW_CHARS;
    const flat = (text || "").replace(/\s+/g, " ").trim();
    return flat.length > limit ? flat.slice(0, limit - 1).replace(/\s+$/, "") + "…" : flat;
}

function lineCount(text) {
    return (text || "").split("\n").length;
}

// "now", "5 min", "2 h", "3 d".
function age(t, now) {
    const s = Math.max(0, Math.round((now - t) / 1000));
    if (s < 45)
        return "now";
    if (s < 3600)
        return `${Math.max(1, Math.round(s / 60))} min`;
    if (s < 86400)
        return `${Math.round(s / 3600)} h`;
    return `${Math.round(s / 86400)} d`;
}

// "128 chars", "3 lines · 240 chars".
function meta(item) {
    if (item.kind === "image")
        return "Image";
    const n = item.text.length;
    const lines = lineCount(item.text);
    const chars = `${n} char${n === 1 ? "" : "s"}`;
    return lines > 1 ? `${lines} lines · ${chars}` : chars;
}

// Saved form: pinned and loose items alike, ids kept so the list keeps its identity across restarts.
function serialize(items) {
    return { version: 1, items: items.map(i => i.kind === "image" ? { id: i.id, kind: "image", path: i.path, t: i.t, pinned: i.pinned } : { id: i.id, kind: "text", text: i.text, t: i.t, pinned: i.pinned }) };
}

// Returns null when the text is not valid JSON, so the caller keeps what it has.
function parse(text) {
    let raw;
    try {
        raw = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!raw || typeof raw !== "object" || !Array.isArray(raw.items))
        return [];
    const seen = {};
    const out = [];
    for (const i of raw.items) {
        if (!i || typeof i !== "object" || typeof i.t !== "number" || typeof i.id !== "string")
            continue;
        const entry = i.kind === "image" && typeof i.path === "string" ? { kind: "image", path: i.path } : i.kind === "text" && typeof i.text === "string" && i.text !== "" ? { kind: "text", text: i.text } : null;
        if (!entry || seen[key(entry)])
            continue;
        seen[key(entry)] = true;
        out.push(Object.assign({ id: i.id, t: i.t, pinned: i.pinned === true }, entry));
    }
    return pinnedFirst(out);
}
