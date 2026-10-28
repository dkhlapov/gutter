.pragma library

// Only short activities: music playing and an agent working are not here, they do not take the island.
var PRIORITY = { hud: 100, keys: 100, timerDone: 90, agentDone: 85, agentLimit: 82, notification: 70, trackChange: 50, timer: 30, stopwatch: 20 };

function alive(entry, now) {
    return entry.expiresAt === null || entry.expiresAt > now;
}

function upsert(list, entry) {
    return list.filter(e => e.id !== entry.id).concat([entry]);
}

function remove(list, id) {
    return list.filter(e => e.id !== id);
}

function prune(list, now) {
    return list.filter(e => alive(e, now));
}

// Highest priority wins; ties go to the most recently shown.
function top(list, now) {
    let best = null;
    for (const e of list) {
        if (!alive(e, now))
            continue;
        if (!best || e.priority > best.priority || (e.priority === best.priority && e.seq > best.seq))
            best = e;
    }
    return best;
}

function nextExpiry(list, now) {
    let next = null;
    for (const e of list)
        if (e.expiresAt !== null && e.expiresAt > now && (next === null || e.expiresAt < next))
            next = e.expiresAt;
    return next;
}
