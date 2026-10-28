.pragma library

var MAX_ITEMS = 30;

var KINDS = {
    image: ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif", "heic", "tif", "tiff", "ico"],
    video: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "flv"],
    audio: ["mp3", "flac", "ogg", "opus", "wav", "m4a", "aac"],
    pdf: ["pdf", "epub", "djvu"],
    archive: ["zip", "tar", "gz", "xz", "zst", "bz2", "7z", "rar", "iso"],
    code: ["js", "ts", "qml", "py", "rs", "go", "c", "cpp", "h", "java", "sh", "json", "yaml", "yml", "toml", "html", "css", "lua", "nix"],
    text: ["txt", "md", "log", "csv", "rtf", "odt", "doc", "docx", "xls", "xlsx", "ods", "ppt", "pptx", "odp"]
};

var ICONS = {
    folder: "folder",
    image: "image",
    video: "movie",
    audio: "music_note",
    pdf: "picture_as_pdf",
    archive: "folder_zip",
    code: "code",
    text: "description",
    file: "draft"
};

// Absolute path of a dropped file:// URL, or null for anything else (web links, relative paths, names
// holding a tab or newline, which the stat output could not tell apart).
function pathFromUrl(url) {
    let s = String(url).trim();
    if (s.indexOf("file://") !== 0)
        return null;
    s = s.slice(7);
    if (s.indexOf("localhost/") === 0)
        s = s.slice(9);
    if (s.charAt(0) !== "/")
        return null;
    try {
        s = decodeURIComponent(s);
    } catch (e) {
        return null;
    }
    if (/[\t\n\r]/.test(s))
        return null;
    return s.length > 1 ? s.replace(/\/+$/, "") : null;
}

// Accepts an array or a newline separated text/uri-list; skips comments and duplicates.
function pathsFromUrls(urls) {
    const list = typeof urls === "string" ? urls.split(/\r?\n/) : Array.from(urls || []);
    const out = [];
    for (const u of list) {
        if (String(u).charAt(0) === "#")
            continue;
        const p = pathFromUrl(u);
        if (p !== null && out.indexOf(p) === -1)
            out.push(p);
    }
    return out;
}

function fileUrl(path) {
    return "file://" + path.split("/").map(encodeURIComponent).join("/");
}

// What a drag out carries: one URL per line, CRLF terminated (RFC 2483).
function uriList(paths) {
    return paths.map(p => fileUrl(p) + "\r\n").join("");
}

function baseName(path) {
    const i = path.lastIndexOf("/");
    return i === -1 ? path : path.slice(i + 1);
}

function dirName(path) {
    const i = path.lastIndexOf("/");
    return i <= 0 ? "/" : path.slice(0, i);
}

function extension(path) {
    const name = baseName(path);
    const i = name.lastIndexOf(".");
    return i <= 0 ? "" : name.slice(i + 1).toLowerCase();
}

function kind(path, isDir) {
    if (isDir)
        return "folder";
    const ext = extension(path);
    for (const k in KINDS)
        if (KINDS[k].indexOf(ext) !== -1)
            return k;
    return "file";
}

function icon(kindName) {
    return ICONS[kindName] || ICONS.file;
}

function humanSize(bytes) {
    let n = Math.max(0, bytes || 0);
    if (n < 1000)
        return `${Math.round(n)} B`;
    const units = ["KB", "MB", "GB", "TB"];
    let u = -1;
    while (n >= 1000 && u < units.length - 1) {
        n /= 1000;
        u++;
    }
    return `${n >= 100 ? Math.round(n) : n.toFixed(1)} ${units[u]}`;
}

// ---- Persisted state: { items: [{ path, added }] }, newest first ----

function empty() {
    return { items: [] };
}

// Dropping a path that is already held moves it to the front. The oldest items fall off at the cap.
function add(state, paths, now) {
    const fresh = paths.map(p => ({ path: p, added: now }));
    const kept = state.items.filter(i => paths.indexOf(i.path) === -1);
    return { items: fresh.concat(kept).slice(0, MAX_ITEMS) };
}

function remove(state, path) {
    return { items: state.items.filter(i => i.path !== path) };
}

function parse(text) {
    let raw;
    try {
        raw = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (raw === null || typeof raw !== "object" || !Array.isArray(raw.items))
        return null;
    const items = [];
    for (const i of raw.items) {
        if (i === null || typeof i !== "object" || typeof i.path !== "string" || i.path.charAt(0) !== "/" || /[\t\n\r]/.test(i.path))
            continue;
        if (items.some(x => x.path === i.path))
            continue;
        items.push({ path: i.path, added: typeof i.added === "number" ? i.added : 0 });
    }
    return { items: items.slice(0, MAX_ITEMS) };
}

// ---- Runtime info from `stat -L --printf '%n\t%s\t%F\n'`: { path: { size, dir } } ----
// Paths stat did not print do not exist.

function parseStat(text) {
    const out = {};
    for (const line of String(text).split("\n")) {
        const f = line.split("\t");
        if (f.length === 3 && f[0] !== "")
            out[f[0]] = { size: parseInt(f[1], 10) || 0, dir: f[2] === "directory" };
    }
    return out;
}

function missing(info, path) {
    return info[path] === undefined;
}

// "3 items · 4.2 MB"; folders count as items but add no size.
function summary(state, info) {
    const n = state.items.length;
    let bytes = 0;
    for (const i of state.items) {
        const s = info[i.path];
        if (s && !s.dir)
            bytes += s.size;
    }
    return { count: n, bytes, text: `${n} ${n === 1 ? "item" : "items"} · ${humanSize(bytes)}` };
}
