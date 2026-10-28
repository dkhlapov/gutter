.pragma library

var ACCENTS = ["navy", "teal", "magenta", "coral", "sun", "lime", "pink"];
var ROLES = ["active", "urgent", "focusBorder", "ok", "special", "muted"];
// The names the shadow.color setting takes: the ink, an accent, or a role (the accent it maps to).
var SHADOW_COLOURS = ["ink"].concat(ACCENTS, ROLES);

var HEX = /^#[0-9a-fA-F]{6}$/;

function fail(error) {
    return { palette: null, error: error };
}

function isObject(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v);
}

function colour(v) {
    return typeof v === "string" && HEX.test(v) ? v.toLowerCase() : null;
}

// One half of a palette: { ink, paper, text, accents }, read from the object o. prefix is the dotted path of o
// in error messages ("" for the top level of a version 1 file, "light." for a half of a version 2 file).
// Without needText (version 1) text is the ink. Returns { half } or { error }.
function parseHalf(o, prefix, needText) {
    var names = needText ? ["ink", "paper", "text"] : ["ink", "paper"];
    var half = { accents: {} };
    var i;
    for (i = 0; i < names.length; i++) {
        var c = colour(o[names[i]]);
        if (c === null)
            return { error: prefix + names[i] + ": must be a #rrggbb colour" };
        half[names[i]] = c;
    }
    if (!needText)
        half.text = half.ink;

    if (!isObject(o.accents))
        return { error: prefix + "accents: must be an object" };
    var k;
    for (k in o.accents) {
        if (ACCENTS.indexOf(k) === -1)
            return { error: prefix + "accents." + k + ": unknown accent" };
    }
    for (i = 0; i < ACCENTS.length; i++) {
        var a = colour(o.accents[ACCENTS[i]]);
        if (a === null)
            return { error: prefix + "accents." + ACCENTS[i] + ": must be a #rrggbb colour" };
        half.accents[ACCENTS[i]] = a;
    }
    return { half: half };
}

// Parses the text of a palette.json, version 1 (one set of colours) or 2 (light and dark halves). A half is
// never partly applied. A version 1 file becomes the light half, with text = ink, and has no dark half (dark is
// null). In a version 2 file whose version, source and roles are fine, one missing or invalid half is set to
// null and the other kept: the palette comes back together with that half's error, and pick fills the null
// half from the default. Any other problem rejects the whole file (palette null).
// Returns { palette: { source, roles, light: Half | null, dark: Half | null } | null,
// error: "<field>: <reason>" | "" } where Half = { ink, paper, text, accents }.
function parse(text) {
    var o;
    try {
        o = JSON.parse(text);
    } catch (e) {
        return fail("file: not valid JSON");
    }
    if (!isObject(o))
        return fail("file: not a JSON object");
    if (o.version !== 1 && o.version !== 2)
        return fail("version: must be 1 or 2");
    if (o.source !== undefined && typeof o.source !== "string")
        return fail("source: must be a string");

    var out = { source: o.source || "", roles: {}, light: null, dark: null };
    var halfError = "";
    var i;
    if (o.version === 1) {
        var v1 = parseHalf(o, "", false);
        if (v1.error)
            return fail(v1.error);
        out.light = v1.half;
    } else {
        var names = ["light", "dark"];
        for (i = 0; i < names.length; i++) {
            var v2 = isObject(o[names[i]]) ? parseHalf(o[names[i]], names[i] + ".", true)
                : { error: names[i] + ": must be an object" };
            if (v2.error) {
                if (halfError !== "")
                    return fail(halfError);
                halfError = v2.error;
            } else {
                out[names[i]] = v2.half;
            }
        }
    }

    if (!isObject(o.roles))
        return fail(halfError || "roles: must be an object");
    var k;
    for (k in o.roles) {
        if (ROLES.indexOf(k) === -1)
            return fail(halfError || "roles." + k + ": unknown role");
    }
    for (i = 0; i < ROLES.length; i++) {
        var role = o.roles[ROLES[i]];
        if (typeof role !== "string" || ACCENTS.indexOf(role) === -1)
            return fail(halfError || "roles." + ROLES[i] + ": must be an accent name");
        out.roles[ROLES[i]] = role;
    }

    return { palette: out, error: halfError };
}

// Parses the text of theme.json, { "version": 1, "mode": "light" | "dark" }: the mode now on screen.
// Returns { mode, error: "" } when valid, else { mode: "light", error: "<field>: <reason>" }.
function parseThemeFile(text) {
    var o;
    try {
        o = JSON.parse(text);
    } catch (e) {
        return { mode: "light", error: "file: not valid JSON" };
    }
    if (!isObject(o))
        return { mode: "light", error: "file: not a JSON object" };
    if (o.version !== 1)
        return { mode: "light", error: "version: must be 1" };
    if (o.mode !== "light" && o.mode !== "dark")
        return { mode: "light", error: "mode: must be \"light\" or \"dark\"" };
    return { mode: o.mode, error: "" };
}

// The colours to draw with: the half of a parsed palette named by mode ("dark" is the dark half, anything else
// the light half), with the palette's roles and source. A half the palette lacks (a version 1 file has no dark
// half) comes from defaults, a parsed version 2 palette.
function pick(parsed, mode, defaults) {
    var name = mode === "dark" ? "dark" : "light";
    var half = parsed[name] || defaults[name];
    return { ink: half.ink, paper: half.paper, text: half.text, accents: half.accents,
        roles: parsed.roles, source: parsed.source };
}

// WCAG 2.x relative luminance of "#rrggbb".
function luminance(hex) {
    var c = [1, 3, 5].map(function (p) {
        var v = parseInt(hex.slice(p, p + 2), 16) / 255;
        return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

// WCAG 2.x contrast ratio, 1 to 21.
function contrast(hexA, hexB) {
    var a = luminance(hexA);
    var b = luminance(hexB);
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

// Whichever of the two colours a and b reads better on the background (an accent, or an ink plate).
function textOn(accentHex, a, b) {
    return contrast(accentHex, a) >= contrast(accentHex, b) ? a : b;
}

// Text on an accent, in both modes: the light half's ink (black) or paper (cream), whichever contrasts more.
// tools/palette.py builds the accents so this is black on every light accent and cream on every dark one.
// light is the light half; returns { <accent name>: colour } for the given accents.
function onAccents(accents, light) {
    var o = {};
    for (var i = 0; i < ACCENTS.length; i++)
        o[ACCENTS[i]] = textOn(accents[ACCENTS[i]], light.ink, light.paper);
    return o;
}

// Text on an ink plate: the same black/cream pair, whichever reads on ink (cream on black lines in light mode,
// black on cream lines in dark mode). light is the light half.
function textOnInk(ink, light) {
    return textOn(ink, light.ink, light.paper);
}

// The paper line round the outer surfaces' shadows: none when there is no shadow (offset 0) to outline.
function shadowKeyline(keyline, offset) {
    return offset > 0 ? keyline : 0;
}

// The shadow's colour in the half applied (a pick() result): its ink, an accent, or the accent a role maps to.
// A name it does not know is teal, the default.
function shadowColour(applied, name) {
    if (name === "ink")
        return applied.ink;
    if (ROLES.indexOf(name) !== -1)
        return applied.accents[applied.roles[name]];
    if (ACCENTS.indexOf(name) !== -1)
        return applied.accents[name];
    return applied.accents.teal;
}
