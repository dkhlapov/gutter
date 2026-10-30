.pragma library

// Logic for the notification server: Gutter owns org.freedesktop.Notifications, the service turns each
// Quickshell Notification into a record (below) and keeps the history, the bubble queue and the saved state.
// Times are milliseconds since the epoch; urgency is 0 low, 1 normal, 2 critical.
var HISTORY_MAX = 100;
var MAX_BODY = 2000;
var MAX_NAME = 200;
var MAX_ID = 2147483647;
var MAX_ACTIONS = 10;
var MAX_PATH = 4096;
var SHOWN_MAX = 200;
var STATE_VERSION = 1;

var ENTITIES = { "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&nbsp;": " ", "&amp;": "&" };

// Bodies may carry the markup subset of the spec (<b>, <i>, <a>, <img>); the pill shows plain text.
function plain(s) {
    return s.replace(/<[^<>]*>/g, "").replace(/&(lt|gt|quot|apos|#39|nbsp|amp);/g, m => ENTITIES[m]).replace(/\s+/g, " ").trim();
}

function text(v) {
    return typeof v === "string" ? v : "";
}

// Markup is cut from the raw text clipped to four times the limit first: stripping a very long run of "<" with
// no ">" is quadratic.
function clean(v, max) {
    return plain(text(v).slice(0, max * 4)).slice(0, max);
}

// Stored strings are clipped to what a record can hold, so a sender cannot grow the saved file.
function clip(v, max) {
    return text(v).slice(0, max);
}

// Quickshell reports an image hint as image://icon/<path or theme name>, file://..., or image://qsimage/..
// (pixels held in memory); the record keeps the path or name and the file URL as they are. The in-memory image is
// dropped: its size is whatever the sender claimed, and loading one that claims more pixels than it sent crashes the shell.
function normaliseImage(v) {
    const s = clip(v, MAX_PATH);
    if (s.startsWith("image://qsimage/"))
        return "";
    return s.startsWith("image://icon/") ? s.slice("image://icon/".length) : s;
}

// Gutter's own failure notices (tools/gutter and the shell's ThemeMode send them as the app "gutter") that name a
// tool in a temporary folder: a check or test run from a scratch root, not the desktop's own failure. Neither
// shown nor kept.
function isStray(appName, body) {
    return text(appName).toLowerCase() === "gutter" && /^cannot run \/(tmp|var\/tmp)\//.test(text(body));
}

// Whether a Quickshell Notification is such a stray (see isStray), however it changed since it was first seen.
function isStrayNotification(n) {
    return isStray(n.appName, clean(n.body, MAX_BODY));
}

// A Quickshell Notification to a record, or null for one that is not shown: the volume and brightness popups
// that replace each other (the pill has HUDs for those) and empty ones. `id` is Gutter's own; the app's is serverId.
function fromNotification(n, id, now) {
    const hints = n.hints !== null && typeof n.hints === "object" ? n.hints : {};
    if (typeof (hints["x-canonical-private-synchronous"] ?? hints["synchronous"]) === "string")
        return null;
    const summary = clean(n.summary, MAX_NAME);
    const body = clean(n.body, MAX_BODY);
    if (summary === "" && body === "")
        return null;
    if (isStray(n.appName, body))
        return null;
    // A QML list<NotificationAction> is array-like, not an Array.
    const actions = n.actions && typeof n.actions.length === "number" ? Array.from(n.actions) : [];
    return {
        id,
        serverId: n.id,
        appName: text(n.appName).slice(0, MAX_NAME),
        icon: clip(n.appIcon, MAX_PATH),
        desktopEntry: clip(n.desktopEntry, MAX_NAME),
        summary,
        body,
        urgency: n.urgency === 0 || n.urgency === 2 ? n.urgency : 1,
        image: normaliseImage(n.image),
        actions: actions.filter(a => a.identifier !== "default" && a.identifier !== "inline-reply" && a.identifier.length <= MAX_NAME).slice(0, MAX_ACTIONS).map(a => ({ identifier: clip(a.identifier, MAX_NAME), text: clip(a.text, MAX_NAME) })),
        hasDefault: actions.some(a => a.identifier === "default"),
        canReply: n.hasInlineReply === true,
        replyPlaceholder: clip(n.inlineReplyPlaceholder, MAX_NAME),
        timeoutMs: n.expireTimeout > 0 ? n.expireTimeout : 0,
        transient: n.transient === true,
        resident: n.resident === true,
        at: now,
        count: 1,
        read: false,
        run: "",
        live: true,
        kept: false
    };
}

// Everything below "critical" waits while do-not-disturb is on.
function canBubble(record, dnd) {
    return !dnd || record.urgency === 2;
}

// How long the bubble stays: the app's own timeout within 4 – 9 s, 6 s when it has none; critical ones and
// ones with buttons or a reply box stay 15 s.
function duration(record) {
    if (record.urgency === 2 || record.actions.length > 0 || record.canReply)
        return 15000;
    if (record.timeoutMs > 0)
        return Math.max(4000, Math.min(9000, record.timeoutMs));
    return 6000;
}

var PRIORITY = { 0: 40, 1: 70, 2: 88 };

function priority(record) {
    return PRIORITY[record.urgency];
}

// While the screen is locked (or the dry-run preview is up) no bubble shows; the queue is kept and the history
// still takes the notifications.
function bubblesAllowed(locked, preview) {
    return !locked && !preview;
}

// How long a waiting bubble stays worth showing after a lock: older ones are dropped, so a morning of
// notifications does not play out as bubbles.
var STALE_MS = 60000;

// The ids of `queue` (order kept) whose record (`find(id)`, or null) arrived within `maxAge` of `now`.
function freshQueue(queue, find, now, maxAge = STALE_MS) {
    return queue.filter(id => {
        const record = find(id);
        return record !== null && record !== undefined && now - record.at <= maxAge;
    });
}

// What happens to the bubble queue when the lock ends. `head` is the id that was on top when it did (0 for none),
// `find(id)` the record or null. What is stale leaves the queue (`dropped`, for the caller to forget); `showHead`
// is true when the head is still the head, so the caller shows it again. A different head shows through the
// caller's own change handler for the head, so it is not shown here as well.
function resumePlan(queue, head, find, now) {
    const fresh = freshQueue(queue, find, now);
    const dropped = queue.filter(id => fresh.indexOf(id) === -1);
    return { queue: fresh, dropped, showHead: fresh.length > 0 && fresh[0] === head };
}

// Newest first, capped. An app reusing its notification (the same live serverId) updates that entry, which keeps
// its id and count and moves to the front; otherwise a repeat of the same app and summary replaces the older entry and raises the count.
// `replaced` lists the ids that left the history, so the service can drop their bubbles. Transient ones
// bubble but are not kept.
function remember(history, record, cap = HISTORY_MAX) {
    if (record.transient)
        return { history, replaced: [] };
    const live = history.findIndex(h => h.live && h.serverId === record.serverId);
    if (live !== -1) {
        const old = history[live];
        const entry = Object.assign({}, record, { id: old.id, count: old.count, read: false, kept: old.kept === true || record.kept === true });
        return { history: [entry].concat(history.filter(h => h !== old)), replaced: [] };
    }
    const same = history.filter(h => h.appName === record.appName && h.summary === record.summary);
    const entry = Object.assign({}, record, { count: same.length > 0 ? same[0].count + 1 : record.count });
    const rest = history.filter(h => same.indexOf(h) === -1);
    return { history: [entry].concat(rest).slice(0, cap), replaced: same.map(h => h.id) };
}

// A transient record that is wanted in the history after all (the user replies to it): it goes in as a
// non-transient, read one marked `kept`, merging with a repeat or an update the way `remember` does. `id` is the
// entry's (a live update of the same serverId keeps the older entry's id); `gone` lists the ids that left the
// history, replaced or pushed out by the cap.
function keepTransient(history, record, cap = HISTORY_MAX) {
    const result = remember(history, Object.assign({}, record, { transient: false, kept: true, read: true }), cap);
    const entry = Object.assign({}, result.history[0], { read: true });
    const list = [entry].concat(result.history.slice(1));
    return { history: list, id: entry.id, gone: history.filter(h => list.every(k => k.id !== h.id)).map(h => h.id) };
}

// Whether the record with id `id` (0 for none) is in the history. An update to such a record stays in the history
// instead of becoming a bubble-only transient (one that keepTransient moved there would otherwise be released).
function inHistory(history, id) {
    return id !== 0 && history.some(h => h.id === id);
}

// The number of bubbles the pointer is on after one more enters (`on`) or leaves; never negative.
function hoverCount(count, on) {
    return Math.max(0, count + (on ? 1 : -1));
}

// The saved record a Notification held over from before a reload takes back, or undefined. `run` is the instance id
// of this launch: the server numbers notifications from 1 in each launch (which outlives hot reloads), so within one
// its ids are unique, and a record made by this launch, no longer live, with that server id is the one. A transient
// Notification has a record only when it was kept for a reply, so it matches kept records alone. With none, a
// non-transient Notification is new (it came in before the file was saved) and a transient one has had its bubble.
function adoptTarget(history, serverId, run, transient) {
    return history.find(h => !h.live && h.run === run && h.serverId === serverId && (!transient || h.kept === true));
}

// `shown` is the list of server ids of this launch's transient notifications whose bubble has been up (the ones with no
// record in the history), saved with the history so a reload knows them. After `serverId`: the list, newest last, capped
// (server ids only grow, so the oldest are the ones no longer held over).
function shownAdd(shown, serverId, cap = SHOWN_MAX) {
    return shown.indexOf(serverId) !== -1 ? shown : shown.concat([serverId]).slice(-cap);
}

// The shown list a saved state holds for this launch (`run`); another launch numbered its notifications on its own.
function shownFor(saved, run) {
    return saved && saved.run === run ? saved.ids : [];
}

// Whether a held-over Notification with no record is to be let go: a transient one that had its bubble. One that did
// not (it was still waiting in the queue, or arrived while the shell reloaded) is new and shows like one.
function adoptLetGo(transient, shown, serverId) {
    return transient && shown.indexOf(serverId) !== -1;
}

// The record a held-over Notification takes back: `fresh` (fromNotification of it, with the old id and time) keeps
// the old count, read mark and run; with none (an update emptied it) the old record is live again. The run is kept
// from the old record because fresh has none. The record is never transient (a kept one is in the history to stay)
// and stays `kept` if it was.
function adoptEntry(old, fresh) {
    return fresh ? Object.assign({}, fresh, { count: old.count, read: old.read, run: old.run, transient: false, kept: old.kept === true }) : Object.assign({}, old, { live: true });
}

// Ids of the bubbles waiting to show, in order.
function queueAdd(queue, record, dnd) {
    return !canBubble(record, dnd) || queue.indexOf(record.id) !== -1 ? queue : queue.concat([record.id]);
}

function queueRemove(queue, id) {
    return queue.filter(q => q !== id);
}

// `queue` with `from` replaced by `to`, each id once (its first place kept), order kept; `queue` itself is not changed.
function queueMove(queue, from, to) {
    return queue.map(q => q === from ? to : q).filter((q, i, all) => all.indexOf(q) === i);
}

function markAllRead(history) {
    return history.map(h => h.read ? h : Object.assign({}, h, { read: true }));
}

function isUnread(record) {
    return !record.read;
}

function unreadCount(history) {
    return history.filter(isUnread).length;
}

// The ids the section counts as new: those of `ids` still in the history (a dismissed one leaves the count),
// then the unread ones not counted yet (marking read does not take one off).
function newIds(ids, history) {
    const kept = ids.filter(id => history.some(h => h.id === id));
    return kept.concat(history.filter(h => isUnread(h) && kept.indexOf(h.id) === -1).map(h => h.id));
}

// The lock screen's counts: the unread records (the ones unreadCount counts) per app, as { app, count, nameless };
// no title or body leaves here. Records with no app name are one entry of their own, `nameless`, shown as "Other":
// an app really called "Other" stays a separate entry. Most first, then by name (the nameless one after a real
// "Other"); at most 6.
var COUNTS_MAX = 6;
var NAMELESS = "Other";

function countsByApp(history) {
    const byApp = Object.create(null);
    let nameless = 0;
    for (const h of history.filter(isUnread)) {
        if (text(h.appName) === "")
            nameless++;
        else
            byApp[h.appName] = (byApp[h.appName] ?? 0) + 1;
    }
    const counts = Object.keys(byApp).map(app => ({ app, count: byApp[app], nameless: false }));
    if (nameless > 0)
        counts.push({ app: NAMELESS, count: nameless, nameless: true });
    const order = (a, b) => a < b ? -1 : a > b ? 1 : 0;
    return counts.sort((a, b) => b.count - a.count || order(a.app, b.app) || order(a.nameless, b.nameless)).slice(0, COUNTS_MAX);
}

function removeById(history, id) {
    return history.filter(h => h.id !== id);
}

// The steps that turn the ids a list shows (`have`) into the ids of `want`, in order, without rebuilding it: a
// ListModel kept this way leaves the cards that stay alone (their reply text, their focus, the scroll position).
// Steps apply one after the other: { op: "remove", at }, { op: "insert", at, id }, { op: "move", from, to }.
// A repeated id in `want` counts once.
function syncOps(have, want) {
    const ids = [];
    const wanted = {};
    for (const id of want) {
        if (!wanted[id]) {
            wanted[id] = true;
            ids.push(id);
        }
    }
    const cur = have.slice();
    const ops = [];
    for (let i = cur.length - 1; i >= 0; i--) {
        if (!wanted[cur[i]]) {
            ops.push({ op: "remove", at: i });
            cur.splice(i, 1);
        }
    }
    for (let i = 0; i < ids.length; i++) {
        if (cur[i] === ids[i])
            continue;
        const from = cur.indexOf(ids[i], i + 1);
        if (from !== -1) {
            ops.push({ op: "move", from, to: i });
            cur.splice(i, 0, cur.splice(from, 1)[0]);
        } else {
            ops.push({ op: "insert", at: i, id: ids[i] });
            cur.splice(i, 0, ids[i]);
        }
    }
    while (cur.length > ids.length) {
        ops.push({ op: "remove", at: cur.length - 1 });
        cur.pop();
    }
    return ops;
}

// Only a file survives a restart; an in-memory image or a theme icon name is dropped (the app icon stays).
function persistentImage(image) {
    return image.startsWith("/") || image.startsWith("file://") ? image : "";
}

function serialize(state) {
    const items = state.items.map(i => Object.assign({}, i, { image: persistentImage(text(i.image)) }));
    const shown = { run: text(state.run), ids: state.shown ?? [] };
    return JSON.stringify({ version: STATE_VERSION, dnd: state.dnd === true, next: state.next, items, shown });
}

function isObject(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v);
}

function whole(v, min, fallback, max = Number.MAX_SAFE_INTEGER) {
    return Number.isSafeInteger(v) && v >= min && v <= max ? v : fallback;
}

// One saved item with every piece put right; restored ones can no longer reach their app, and count as read.
function restoreItem(i) {
    return {
        id: whole(i.id, 1, 0, MAX_ID),
        serverId: whole(i.serverId, 0, 0),
        appName: i.appName.slice(0, MAX_NAME),
        icon: clip(i.icon, MAX_PATH),
        desktopEntry: clip(i.desktopEntry, MAX_NAME),
        summary: text(i.summary).slice(0, MAX_NAME),
        body: text(i.body).slice(0, MAX_BODY),
        urgency: i.urgency === 0 || i.urgency === 2 ? i.urgency : 1,
        image: persistentImage(clip(i.image, MAX_PATH)),
        actions: Array.isArray(i.actions) ? i.actions.filter(a => isObject(a) && typeof a.identifier === "string" && a.identifier.length <= MAX_NAME).slice(0, MAX_ACTIONS).map(a => ({ identifier: clip(a.identifier, MAX_NAME), text: clip(a.text, MAX_NAME) })) : [],
        hasDefault: i.hasDefault === true,
        canReply: i.canReply === true,
        replyPlaceholder: clip(i.replyPlaceholder, MAX_NAME),
        timeoutMs: whole(i.timeoutMs, 1, 0),
        transient: i.transient === true,
        resident: i.resident === true,
        at: typeof i.at === "number" && isFinite(i.at) ? i.at : 0,
        count: whole(i.count, 1, 1),
        read: true,
        run: typeof i.run === "string" ? i.run.slice(0, MAX_NAME) : "",
        live: false,
        kept: i.kept === true
    };
}

// The saved file back to { dnd, next, items, shown: { run, ids } }, or null when it is not a state file of this version (the
// caller starts empty). `next` ends up above every id, and an item without a usable id, or with one that came
// before, gets a new one.
function parseState(raw) {
    let state;
    try {
        state = JSON.parse(raw);
    } catch (e) {
        return null;
    }
    if (!isObject(state) || state.version !== STATE_VERSION)
        return null;
    const items = (Array.isArray(state.items) ? state.items : []).filter(i => isObject(i) && typeof i.appName === "string" && !isStray(i.appName, i.body)).slice(0, HISTORY_MAX).map(restoreItem);
    const seen = {};
    for (const i of items) {
        if (seen[i.id])
            i.id = 0;
        seen[i.id] = true;
    }
    let next = Math.max(whole(state.next, 1, 1, MAX_ID), 1 + Math.max(0, ...items.map(i => i.id)));
    for (const i of items) {
        if (i.id === 0)
            i.id = next++;
    }
    const saved = isObject(state.shown) ? state.shown : {};
    const ids = (Array.isArray(saved.ids) ? saved.ids : []).filter(id => whole(id, 0, -1) !== -1).slice(-SHOWN_MAX);
    return { dnd: state.dnd === true, next, items, shown: { run: typeof saved.run === "string" ? saved.run.slice(0, MAX_NAME) : "", ids } };
}

// Icon source for the bubble: a file path as the file, otherwise a theme icon name for Quickshell.iconPath.
function iconSource(record) {
    const image = text(record.image);
    const p = (image.startsWith("image://") ? "" : image) || text(record.icon);
    if (p.startsWith("/"))
        return { file: "file://" + p, name: "" };
    if (p.startsWith("file://"))
        return { file: p, name: "" };
    return { file: "", name: p || text(record.desktopEntry) || text(record.appName).toLowerCase() };
}

// "now", "3 min", "2 h", "4 d".
function ago(at, now) {
    const s = Math.max(0, Math.floor((now - at) / 1000));
    if (s < 60)
        return "now";
    if (s < 3600)
        return `${Math.floor(s / 60)} min`;
    if (s < 86400)
        return `${Math.floor(s / 3600)} h`;
    return `${Math.floor(s / 86400)} d`;
}

// Prints who owns the notification name: "self=<pid of the shell that runs this>", and when something does,
// "owner=<its pid>" and "cmd=<its command line, NULs as spaces>". The owner comes from busctl's status call, or, when
// that fails, from the bus's list of names (a name nobody holds fails the first and is not listed with a pid in the
// second; an activatable name has no connection and is held by nobody). "failed=1" when busctl could not tell: both
// calls fail, status answered with no pid, or the list shows a connection holding the name without a pid ("-").
// Without busctl the output is "nobusctl=1": asking again would not help.
function ownerCommand() {
    return ["sh", "-c", "command -v busctl >/dev/null || { echo nobusctl=1; exit 0; }; echo self=$PPID; bad=; if s=$(busctl --user status org.freedesktop.Notifications 2>/dev/null); then o=$(printf '%s\\n' \"$s\" | sed -n 's/^PID=//p'); [ -n \"$o\" ] || bad=1; elif l=$(busctl --user list --no-legend 2>/dev/null); then o=$(printf '%s\\n' \"$l\" | awk '$1 == \"org.freedesktop.Notifications\" { if ($2 ~ /^[0-9]+$/) print $2; else if ($5 != \"(activatable)\") print \"-\"; exit }'); [ \"$o\" != - ] || bad=1; else bad=1; fi; if [ -n \"$bad\" ]; then echo failed=1; elif [ -n \"$o\" ]; then echo owner=$o; echo \"cmd=$(tr '\\0' ' ' </proc/$o/cmdline 2>/dev/null)\"; fi"];
}

// Who else holds the notification name, from ownerCommand's output: the holder's command line, or "pid <n>" when
// it has none to show. null when Gutter holds the name, nobody does, or the check could not tell (see ownerState).
function otherOwner(output) {
    const self = /^self=(\d+)$/m.exec(output);
    if (!self)
        return null;
    const owner = /^owner=(\d+)$/m.exec(output);
    if (!owner || owner[1] === self[1])
        return null;
    const cmd = /^cmd=(.*)$/m.exec(output);
    const text = cmd ? cmd[1].trim() : "";
    return text !== "" ? text : `pid ${owner[1]}`;
}

// What ownerCommand's output says: "other" (another daemon holds the name), "none" (Gutter does, or nobody),
// "unsupported" (no busctl: the check cannot be made, so it is not repeated) or "unknown" (the check could not tell:
// no output, or busctl failing). An unknown check changes nothing: it is not evidence that nobody else holds the name.
function ownerState(output) {
    if (/^nobusctl=1$/m.test(output))
        return "unsupported";
    if (!/^self=\d+$/m.test(output) || /^failed=1$/m.test(output))
        return "unknown";
    return otherOwner(output) === null ? "none" : "other";
}

// Focuses the app's window by class (a desktop entry is the class for most apps). The argument is Lua, so the
// regex escapes and quotes are backslash-escaped once more; null when there is nothing to match on.
function focusCommand(record) {
    const name = text(record.desktopEntry) || text(record.appName);
    if (name === "")
        return null;
    const regex = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const lua = regex.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
    return ["hyprctl", "dispatch", `hl.dsp.focus({ window = "class:(?i)^${lua}$" })`];
}

// What a click on a notification does. A live one with a default action: { action: true }. Anything else (a live one
// without, or one that is no longer live: the app closed it, the server was turned off, or the shell restarted
// since) can only bring the app's window up: { command } while `windowClasses`, the classes of the open windows, has
// the one the focus command matches (it matches the class without regard to case). null when there is nothing to do.
function activation(record, live, hasAction, windowClasses) {
    if (live && hasAction)
        return { action: true };
    const command = focusCommand(record);
    if (!command)
        return null;
    const name = (text(record.desktopEntry) || text(record.appName)).toLowerCase();
    const classes = Array.isArray(windowClasses) ? windowClasses : [];
    if (!classes.some(c => typeof c === "string" && c.toLowerCase() === name))
        return null;
    return { command };
}
