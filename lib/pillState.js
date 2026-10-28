.pragma library

function resolveSection(requested, current, sections) {
    if (requested && sections.indexOf(requested) !== -1)
        return requested;
    if (sections.indexOf(current) !== -1)
        return current;
    return sections[0];
}

function shiftSection(current, sections, delta) {
    const idx = Math.max(0, sections.indexOf(current));
    return sections[Math.max(0, Math.min(sections.length - 1, idx + delta))];
}

// The sections that show message bodies. A lock, even the dry-run preview, must never show them: the panel stays
// off them while the screen is locked.
var BODY_SECTIONS = ["notifications"];

// Whether the panel may open on `section` (a requested name, or "" for the last one): not on a body section while locked.
function canOpen(section, locked) {
    return !locked || BODY_SECTIONS.indexOf(section) === -1;
}

// The sections the panel can show right now.
function allowedSections(sections, locked) {
    return locked ? sections.filter(s => BODY_SECTIONS.indexOf(s) === -1) : sections;
}

// Whether an open panel on `section` must close because the screen locked.
function closeOnLock(section, locked) {
    return !canOpen(section, locked);
}

// The section the panel lands on for a request, or null when there is none to land on: a request for a body section
// while locked, or no section left (the only one configured is a body section). Null means leave everything as it was.
function landing(requested, current, sections, locked) {
    const allowed = allowedSections(sections, locked);
    return canOpen(requested, locked) && allowed.length > 0 ? resolveSection(requested, current, allowed) : null;
}

// The section `delta` steps from `current` among the allowed ones, or null when there are none.
function shifted(current, sections, delta, locked) {
    const allowed = allowedSections(sections, locked);
    return allowed.length > 0 ? shiftSection(current, allowed, delta) : null;
}

var OPEN_W = 1010;
var OPEN_H = 420;
var ACTIVITY_MAX_W = 420;
// The track-change pop is the one face taller than the resting island.
var TRACK_H = 48;
// Hovering the island grows it by this much (all round, so half on each side), the one thing hover changes.
var PEEK_W = 32;
var PEEK_H = 6;

// Lays content `w` wide into `room`: never wider than the room (the text in it elides instead), centred in what
// is left over. Returns its width and its offset into the room.
function fit(w, room) {
    const width = Math.max(0, Math.min(w, room));
    return { w: width, x: (Math.max(0, room) - width) / 2 };
}

// The island's mode, and whether it peeks: hovered (not open or hidden), it grows a little. The panel itself
// opens on hover through Settings.openOnHover, which is no input here.
function derive(f) {
    if (f.open)
        return { mode: "open", peek: false };
    if (f.fullscreenHidden)
        return { mode: "hidden", peek: false };
    return { mode: f.hasActivity ? "activity" : "idle", peek: !!f.hovered };
}

// What a peek adds to the box's size, on top of `size`: nothing unless the view peeks. Kept apart from `size` so
// the pill can animate it on its own and lay the side pills out around the island's width without it.
function peekSize(view) {
    return view.peek ? { w: PEEK_W, h: PEEK_H } : { w: 0, h: 0 };
}

// The box for `view`: `width` is the resting island's width and `restH` its height (Theme.pillHeight); `act` is
// the width the current activity's face asks for and its id.
function size(view, width, act, restH) {
    if (view.mode === "open")
        return { w: OPEN_W, h: OPEN_H };
    if (view.mode === "hidden")
        return { w: width, h: 0 };
    if (view.mode === "activity")
        return { w: Math.min(ACTIVITY_MAX_W, Math.max(width, Math.ceil(act.w))), h: act.id === "track" ? TRACK_H : restH };
    return { w: width, h: restH };
}

// Off the overlay layer, under fullscreen windows, unless the panel is open on this screen. The window is
// never unmapped for this: destroying and recreating a window that holds a TrayIcon crashes Qt (see test_windows.py).
function windowRaised(f) {
    return f.open || !f.fullscreenHidden;
}

// Activities that show as speech bubbles instead of pills.
var BUBBLES = ["timerDone", "agentDone", "notification"];

function isBubble(id) {
    return BUBBLES.indexOf(id) !== -1;
}
