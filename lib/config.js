.pragma library
.import "palette.js" as PaletteLib

// The keys of Gutter's config.json (SCHEMA) and their defaults.
var SECTIONS = ["overview", "music", "calendar", "system", "weather", "tools", "agents", "shelf", "clipboard", "mixer", "notifications"];
var CONFIG_VERSION = 8;

var WORLD_CLOCKS = [
    { label: "New York", tz: "America/New_York" },
    { label: "London", tz: "Europe/London" },
    { label: "Tokyo", tz: "Asia/Tokyo" },
    { label: "UTC", tz: "UTC" }
];

var SCHEMA = {
    "openOnHover": { type: "bool", def: false },
    "hoverDelay": { type: "int", def: 250, min: 0, max: 2000 },
    "hideInFullscreen": { type: "bool", def: true },
    "idleContent": { type: "enum", def: "music", values: ["none", "music", "clock"] },
    "opensActivity": { type: "bool", def: true },
    // Accepted and kept in the file, but not used yet (the panel width is pillState.OPEN_W).
    "width": { type: "int", def: 200, min: 120, max: 600 },
    "gestures": { type: "bool", def: true },
    "notifications": { type: "bool", def: true },
    "configVersion": { type: "int", def: CONFIG_VERSION, min: 1, max: CONFIG_VERSION },
    "sections": { type: "enumList", def: SECTIONS, values: SECTIONS },
    "weather.location": { type: "string", def: "" },
    "weather.units": { type: "enum", def: "metric", values: ["metric", "imperial"] },
    "worldClocks": { type: "clocks", def: WORLD_CLOCKS },
    "theme.mode": { type: "enum", def: "sun", values: ["sun", "schedule", "light", "dark"] },
    "theme.schedule.light": { type: "time", def: "07:00" },
    "theme.schedule.dark": { type: "time", def: "20:00" },
    "shadow.color": { type: "enum", def: "teal", values: PaletteLib.SHADOW_COLOURS },
    "shadow.keyline": { type: "int", def: 0, min: 0, max: 2 },
    "shadow.offset": { type: "int", def: 3, min: 0, max: 8 },
    "launcher.terminal": { type: "string", def: "foot" },
    "launcher.maxRows": { type: "int", def: 8, min: 4, max: 12 },
    "lockscreen.enabled": { type: "bool", def: true },
    // Seconds; 0 means never.
    "lockscreen.idle.lock": { type: "int", def: 180, min: 0, max: 86400 },
    "lockscreen.idle.screenOff": { type: "int", def: 300, min: 0, max: 86400 },
    "lockscreen.idle.inhibitWhenAudio": { type: "bool", def: true },
    "lockscreen.idle.lockBeforeSleep": { type: "bool", def: true },
    "lockscreen.fingerprint": { type: "bool", def: true }
};

function clone(v) {
    return v !== null && typeof v === "object" ? JSON.parse(JSON.stringify(v)) : v;
}

function getPath(obj, path) {
    return path.split(".").reduce((o, k) => (o !== null && typeof o === "object") ? o[k] : undefined, obj);
}

function setPath(obj, path, value) {
    const keys = path.split(".");
    let o = obj;
    for (let i = 0; i < keys.length - 1; i++) {
        if (typeof o[keys[i]] !== "object" || o[keys[i]] === null)
            o[keys[i]] = {};
        o = o[keys[i]];
    }
    o[keys[keys.length - 1]] = value;
}

function isValid(spec, v) {
    switch (spec.type) {
    case "bool":
        return typeof v === "boolean";
    case "int":
        return typeof v === "number" && isFinite(v) && v >= spec.min && v <= spec.max;
    case "string":
        return typeof v === "string";
    case "enum":
        return spec.values.indexOf(v) !== -1;
    case "time":
        return typeof v === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(v);
    case "enumList":
        return Array.isArray(v) && v.length > 0 && v.every(x => spec.values.indexOf(x) !== -1) && new Set(v).size === v.length;
    }
    return false;
}

function validClock(c) {
    return c !== null && typeof c === "object" && typeof c.label === "string" && c.label !== "" && typeof c.tz === "string" && c.tz !== "";
}

// Exactly 4 clocks: invalid entries dropped, extras cut, the rest padded with unused defaults.
function clocks(v, warnings) {
    if (!Array.isArray(v)) {
        warnings.push(`invalid value for worldClocks: ${JSON.stringify(v)}`);
        return clone(WORLD_CLOCKS);
    }
    if (v.length > 4)
        warnings.push(`worldClocks: only the first 4 of ${v.length} clocks are shown`);
    const out = [];
    for (const c of v.slice(0, 4)) {
        if (validClock(c))
            out.push({ label: c.label, tz: c.tz });
        else
            warnings.push(`invalid world clock: ${JSON.stringify(c)}`);
    }
    for (const d of WORLD_CLOCKS)
        if (out.length < 4 && !out.some(c => c.tz === d.tz))
            out.push(clone(d));
    return out;
}

function defaults() {
    const out = {};
    for (const key in SCHEMA)
        setPath(out, key, clone(SCHEMA[key].def));
    return out;
}

// Validates every known key; invalid or missing values fall back to defaults.
function merge(raw) {
    const config = {};
    const warnings = [];
    for (const key in SCHEMA) {
        const spec = SCHEMA[key];
        const v = getPath(raw, key);
        if (v === undefined) {
            setPath(config, key, clone(spec.def));
        } else if (spec.type === "clocks") {
            setPath(config, key, clocks(v, warnings));
        } else if (isValid(spec, v)) {
            setPath(config, key, spec.type === "int" ? Math.round(v) : clone(v));
        } else {
            warnings.push(`invalid value for ${key}: ${JSON.stringify(v)}`);
            setPath(config, key, clone(spec.def));
        }
    }
    return { config, warnings };
}

// Configs written before a tab existed get it once: "overview" in front for version 1 (no configVersion),
// "tools" at the end for versions 1 and 2, "agents" at the end for versions 1 to 3, "shelf" at the end for versions 1 to 4, "clipboard" at the end for versions 1 to 5, "mixer" at the end for versions 1 to 6, "notifications" at the end for versions 1 to 7. The version stamp
// makes a later removal by the user stick.
function migrate(raw) {
    if (raw === null || typeof raw !== "object" || Array.isArray(raw) || raw.configVersion >= CONFIG_VERSION)
        return { raw, changed: false };
    const version = typeof raw.configVersion === "number" ? raw.configVersion : 1;
    const out = Object.assign({}, raw, { configVersion: CONFIG_VERSION });
    if (Array.isArray(raw.sections)) {
        let sections = raw.sections.slice();
        if (version < 2 && sections.indexOf("overview") === -1)
            sections = ["overview"].concat(sections);
        if (version < 3 && sections.indexOf("tools") === -1)
            sections = sections.concat(["tools"]);
        if (version < 4 && sections.indexOf("agents") === -1)
            sections = sections.concat(["agents"]);
        if (version < 5 && sections.indexOf("shelf") === -1)
            sections = sections.concat(["shelf"]);
        if (version < 6 && sections.indexOf("clipboard") === -1)
            sections = sections.concat(["clipboard"]);
        if (version < 7 && sections.indexOf("mixer") === -1)
            sections = sections.concat(["mixer"]);
        if (version < 8 && sections.indexOf("notifications") === -1)
            sections = sections.concat(["notifications"]);
        out.sections = sections;
    }
    return { raw: out, changed: true };
}

// Returns null when the text is not valid JSON, so callers can keep the last good config.
// `rewrite` is the migrated file content to write back, or null when nothing changed.
function parse(text) {
    let raw;
    try {
        raw = JSON.parse(text);
    } catch (e) {
        return null;
    }
    const m = migrate(raw);
    const result = merge(m.raw);
    result.rewrite = m.changed ? m.raw : null;
    return result;
}

// The text of a config file Gutter writes: two-space JSON with a final newline.
function serialize(config) {
    return JSON.stringify(config, null, 2) + "\n";
}

// The text Gutter writes as its first config: the defaults.
function firstRun() {
    return serialize(defaults());
}
