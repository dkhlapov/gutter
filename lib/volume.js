.pragma library

function createTracker() {
    return { sinkId: null, volume: null, muted: null };
}

// A change only counts on the same sink after a first reading, so start-up and
// device switches never pop the HUD.
function update(tracker, sinkId, volume, muted) {
    const next = { sinkId, volume, muted };
    if (tracker.sinkId !== sinkId || tracker.volume === null)
        return { tracker: next, changed: false };
    const changed = Math.round(volume * 100) !== Math.round(tracker.volume * 100) || muted !== tracker.muted;
    return { tracker: next, changed };
}

// Works in whole percents and snaps to the step grid in the direction of travel
// (52 % up one step → 55 %, down one step → 50 %), so wheel steps stay even.
function step(volume, steps, size) {
    const q = Math.round((size === undefined ? 0.05 : size) * 100);
    const p = Math.round(volume * 100);
    if (steps === 0)
        return p / 100;
    const base = steps > 0 ? Math.floor(p / q) * q : Math.ceil(p / q) * q;
    return Math.max(0, Math.min(100, base + steps * q)) / 100;
}

function icon(volume, muted) {
    if (muted)
        return "volume_off";
    if (volume >= 0.5)
        return "volume_up";
    if (volume > 0)
        return "volume_down";
    return "volume_mute";
}
