.pragma library

// The lock keys and the layout, as the keys HUD sees them. Hyprland sends no event for Caps Lock or Num Lock, so
// the service reads the keyboards' LEDs (the compositor keeps them in step with its xkb state) when a bound key
// is pressed, and compares with the last reading.

// What the LED reader script prints: one `<key>=<0|1>` line per lock key.
var LOCK_KEYS = ["caps", "num"];

// The lock state from the reader's output ("caps=1\nnum=0"); null when it holds no reading of either key.
function parseLocks(text) {
    const state = { caps: false, num: false };
    let seen = 0;
    for (const line of String(text).split("\n")) {
        const m = /^(caps|num)=([01])\s*$/.exec(line.trim());
        if (!m)
            continue;
        state[m[1]] = m[2] === "1";
        seen++;
    }
    return seen === 0 ? null : state;
}

// The lock keys whose state differs between two readings, in LOCK_KEYS order. The first reading (`prev` null)
// changes nothing: the HUD never fires at start-up.
function lockChanges(prev, next) {
    if (prev === null || next === null)
        return [];
    return LOCK_KEYS.filter(k => prev[k] !== next[k]).map(k => ({ key: k, on: next[k] }));
}

// Whether a layout name is a switch worth showing: both names known and different.
function layoutChanged(prev, next) {
    return prev !== "" && next !== "" && prev !== next;
}

// The HUDs stay quiet while the screen is locked (or its preview is up): nothing shows over the lock, and a
// change made meanwhile is not announced after the unlock.
function allowed(locked, preview) {
    return !locked && !preview;
}

// The activity id for a kind of change.
var ACTIVITY = { layout: "kbLayout", caps: "capsLock", num: "numLock" };

function activityId(kind) {
    return ACTIVITY[kind] ?? "";
}

// The word on the pill's label tab and the title of the face, per kind.
var NAMES = { layout: "Layout", caps: "Caps Lock", num: "Num Lock" };
var TABS = { layout: "KBD", caps: "CAPS", num: "NUM" };

function name(kind) {
    return NAMES[kind] ?? "";
}

function tab(kind) {
    return TABS[kind] ?? "";
}

// The icon name (glyphs.js) of a kind and its state: a lock key's is filled while on.
function icon(kind, on) {
    if (kind === "layout")
        return "keyboard";
    return on ? "lock" : "lock_open";
}
