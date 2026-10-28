.pragma library

// The longest password the lock screen takes, in characters (graphemes).
var MAX_PASSWORD = 256;

// The most UTF-16 units the buffer may hold. The grapheme cap alone lets a flood of combining marks grow one
// grapheme without end; this bounds the buffer's memory (PAM's own response limit is separate).
var MAX_PASSWORD_UNITS = MAX_PASSWORD * 8;

// Code points that attach to the one before them: combining marks, joiners and selectors, skin tones, keycaps
// and tag characters. The engine has no Intl.Segmenter and no \p{} escapes, so these are the common ranges.
var EXTEND = [
    [0x0300, 0x036F], [0x0483, 0x0489], [0x0591, 0x05BD], [0x05BF, 0x05BF], [0x05C1, 0x05C2], [0x05C4, 0x05C5],
    [0x05C7, 0x05C7], [0x0610, 0x061A], [0x064B, 0x065F], [0x0670, 0x0670], [0x06D6, 0x06DC], [0x06DF, 0x06E4],
    [0x06E7, 0x06E8], [0x06EA, 0x06ED], [0x0900, 0x0903], [0x093A, 0x093C], [0x093E, 0x094F], [0x0951, 0x0957],
    [0x0962, 0x0963], [0x0981, 0x0983], [0x09BC, 0x09BC], [0x09BE, 0x09C4], [0x09C7, 0x09C8], [0x09CB, 0x09CD],
    [0x09D7, 0x09D7], [0x09E2, 0x09E3], [0x09FE, 0x09FE], [0x0E31, 0x0E31], [0x0E34, 0x0E3A], [0x0E47, 0x0E4E],
    [0x1AB0, 0x1AFF], [0x1DC0, 0x1DFF], [0x200C, 0x200C], [0x20D0, 0x20FF], [0x3099, 0x309A], [0xFE00, 0xFE0F],
    [0xFE20, 0xFE2F], [0x1F3FB, 0x1F3FF], [0xE0020, 0xE007F], [0xE0100, 0xE01EF]
];
var ZWJ = 0x200D;

function inRanges(ranges, cp) {
    for (var i = 0; i < ranges.length; i++) {
        if (cp >= ranges[i][0] && cp <= ranges[i][1])
            return true;
    }
    return false;
}

function isRegional(cp) {
    return cp >= 0x1F1E6 && cp <= 0x1F1FF;
}

// A control character: it ends a grapheme on both sides, so nothing joins it.
function isControl(cp) {
    return cp < 0x20 || (cp >= 0x7F && cp <= 0x9F);
}

// The Hangul class of a code point: "L", "V", "T" for jamo, "LV" and "LVT" for precomposed syllables, else "".
function hangul(cp) {
    if ((cp >= 0x1100 && cp <= 0x115F) || (cp >= 0xA960 && cp <= 0xA97C))
        return "L";
    if ((cp >= 0x1160 && cp <= 0x11A7) || (cp >= 0xD7B0 && cp <= 0xD7C6))
        return "V";
    if ((cp >= 0x11A8 && cp <= 0x11FF) || (cp >= 0xD7CB && cp <= 0xD7FB))
        return "T";
    if (cp >= 0xAC00 && cp <= 0xD7A3)
        return (cp - 0xAC00) % 28 === 0 ? "LV" : "LVT";
    return "";
}

// Whether a Hangul code point of class `next` continues a syllable whose last code point is class `prev`.
function hangulJoins(prev, next) {
    if (prev === "L")
        return next === "L" || next === "V" || next === "LV" || next === "LVT";
    if (prev === "V" || prev === "LV")
        return next === "V" || next === "T";
    return (prev === "T" || prev === "LVT") && next === "T";
}

// The visible characters of a string, one entry each: a base with its combining marks, a ZWJ sequence, a flag
// (two regional indicators), a keycap, a Hangul syllable spelled in jamo and CRLF are one. Spread walks code
// points, where Qt's Array.from splits a surrogate pair in two.
function graphemes(text) {
    var cps = [...String(text)];
    var out = [];
    var i = 0;
    while (i < cps.length) {
        var cp = cps[i].codePointAt(0);
        var g = cps[i++];
        var last = hangul(cp);
        var sticky = !isControl(cp);
        if (cp === 0x0D && i < cps.length && cps[i] === "\n") {
            g += cps[i++];
        } else if (isRegional(cp) && i < cps.length && isRegional(cps[i].codePointAt(0))) {
            g += cps[i++];
        }
        while (sticky && i < cps.length) {
            var next = cps[i].codePointAt(0);
            if (next === ZWJ) {
                // A joiner takes the code point after it, on purpose: any emoji sequence it links, and
                // harmless for text that is not one.
                g += cps[i++];
                if (i < cps.length && !isControl(cps[i].codePointAt(0)))
                    g += cps[i++];
                last = "";
            } else if (inRanges(EXTEND, next) || (last !== "" && hangulJoins(last, hangul(next)))) {
                g += cps[i++];
                last = hangul(next);
            } else {
                break;
            }
        }
        out.push(g);
    }
    return out;
}

// The graphemes that fit the buffer: at most MAX_PASSWORD of them and MAX_PASSWORD_UNITS units, cut after a whole
// grapheme. `kept` is the buffer's own graphemes; when a grapheme that grew (a mark flood) would push them out, the
// buffer stays as it was.
function capped(all, kept) {
    var out = [];
    var units = 0;
    for (var j = 0; j < all.length && out.length < MAX_PASSWORD && units + all[j].length <= MAX_PASSWORD_UNITS; j++) {
        out.push(all[j]);
        units += all[j].length;
    }
    return out.length >= Math.min(kept.length, MAX_PASSWORD) ? out : kept;
}

// What a typed key does to the password buffer. `key.name` is "enter", "backspace", "escape" or "char" (then
// `key.text` is what it types). Characters are counted as graphemes, so an accent, a flag or an emoji family is
// one. Enter asks to submit when there is something to submit; holding it down does not repeat the submit.
// Returns the new buffer and whether to submit.
function keyEdit(buffer, key) {
    var chars = graphemes(buffer);
    switch (key.name) {
    case "enter":
        return { buffer: buffer, submit: chars.length > 0 && !key.repeat };
    case "backspace":
        if (key.ctrl)
            return { buffer: "", submit: false };
        chars.pop();
        return { buffer: chars.join(""), submit: false };
    case "escape":
        return { buffer: "", submit: false };
    case "char":
        // Printable text only: no control characters, and nothing for a key that types nothing. A paste's
        // trailing newlines are dropped, so the rest is taken; the paste never submits.
        var text = typeof key.text === "string" ? key.text : "";
        // A loop, not a regex: a long newline run in the middle would make the `$` match quadratic.
        var end = text.length;
        while (end > 0 && (text[end - 1] === "\n" || text[end - 1] === "\r"))
            end--;
        text = text.slice(0, end);
        if (/^[^\x00-\x1F\x7F-\x9F]+$/.test(text)) {
            // Cut the paste before segmenting it. The extra unit means a grapheme cut in half always overflows
            // and is dropped by capped().
            var room = Math.max(0, MAX_PASSWORD_UNITS - buffer.length) + 1;
            chars = capped(graphemes(buffer + text.slice(0, room)), chars);
        }
        return { buffer: chars.join(""), submit: false };
    }
    return { buffer: buffer, submit: false };
}

// What pam_faillock says in its message: whether the account is locked, and the minutes left to unlock (0 when
// it does not say).
function parseFaillock(message) {
    var text = String(message);
    var left = /\((\d+) minutes? left to unlock\)/.exec(text);
    return { locked: /account is locked/i.test(text), minutes: left ? parseInt(left[1], 10) : 0 };
}

// The `deny` setting of faillock.conf: the failed logins that lock the account. libpam reads the file top to
// bottom, drops a `#` comment to the end of its line and skips a `deny` line whose value is not a number; a later
// line overrides an earlier one, so the last numeric line counts. A missing or unreasonable value gives
// faillock's default of 3. Only blanks and tabs may sit round the `=`: a value on the next line is not this one.
function parseDeny(confText) {
    var lines = String(confText).split("\n");
    var value = "";
    for (var i = 0; i < lines.length; i++) {
        var m = /^[ \t]*deny[ \t]*=[ \t]*(\d+)[ \t\r]*$/.exec(lines[i].replace(/#.*/, ""));
        if (m)
            value = m[1];
    }
    var deny = value === "" ? 0 : parseInt(value, 10);
    return deny >= 1 && deny <= 100 ? deny : 3;
}

// The attempts left before the account locks.
function triesLeft(deny, failures) {
    return Math.max(0, deny - failures);
}

// What the lock screen says about a finished PAM attempt. `result` is "failed", "error" or "maxtries"; `info`
// has PAM's last `message`, faillock's `deny` and the `failures` so far. `kind` is "wrong", "locked" or "error".
function authState(result, info) {
    var faillock = parseFaillock(info.message);
    if (result === "maxtries" || (result === "failed" && faillock.locked))
        return { kind: "locked", text: faillock.minutes > 0 ? "Locked · " + faillock.minutes + " min" : "Locked" };
    if (result === "failed") {
        var left = triesLeft(info.deny, info.failures);
        return { kind: "wrong", text: left > 0 ? "Wrong password · " + left + " left" : "Wrong password" };
    }
    return { kind: "error", text: "Could not check the password" };
}

// Whether `fprintd-list` output shows an enrolled fingerprint: a finger line like ` - #0: right-index-finger`.
function hasPrints(output) {
    return /^\s*-\s*#\d+:/m.test(String(output));
}

// What a request to lock does. With the lock screen enabled it locks, unless the session is already locked;
// with it disabled nothing happens ("ignore"): no other lock screen takes over. A request that arrives while the
// lock is being unlocked (`unlocking`, the fade) is "queue"d: it is not moot, the lock is about to go, and it is
// asked for again once it has.
function lockDecision(s) {
    if (!s.enabled)
        return "ignore";
    if (s.locked)
        return s.unlocking ? "queue" : "ignore";
    return "lock";
}

// What to do about a queued lock request (see lockDecision), `s` being {pending, unlocking, locked, preview}:
// "none" when nothing is queued, "wait" while the unlock runs or the lock is still held or showing (the unlock's own
// signals arrive while `locked` has not yet followed the release), "retry" once nothing is left of the lock.
function pendingStep(s) {
    if (!s.pending)
        return "none";
    if (s.unlocking || s.locked || s.preview)
        return "wait";
    return "retry";
}

// The battery chip on the lock screen. `d` is the battery device (percentage 0..1) or null. Without a battery
// or a readable level there is no chip.
function batteryChip(d) {
    if (!d || !d.isPresent || typeof d.percentage !== "number" || isNaN(d.percentage))
        return { visible: false, text: "" };
    var percent = Math.round(Math.min(1, Math.max(0, d.percentage)) * 100);
    return { visible: true, text: percent + " %" + (d.charging ? " ⚡" : "") };
}

// The LockedHint from `busctl get-property` output ("b true") or from the test hint file ("true"). Anything else,
// an empty answer included, is false.
function parseLockedHint(text) {
    return /^(b\s+)?true$/.test(String(text).trim());
}

// The speech bubble's accent for the lock screen's state: coral for a wrong password or an error, sun (the nearest
// to amber) for a lockout, none (the paper bubble) for no state and while a check runs.
function stateAccent(kind, checking) {
    if (checking)
        return "";
    switch (kind) {
    case "locked":
        return "sun";
    case "wrong":
    case "error":
        return "coral";
    }
    return "";
}

// Whether the dry-run preview may open: not over a real lock, or one on its way (`held`: LockScreen holds it,
// `locked`: wanted, `secure`: the compositor confirmed it). It would take the Auth that the lock needs to unlock.
function previewAllowed(held, locked, secure) {
    return !(held || locked || secure);
}
