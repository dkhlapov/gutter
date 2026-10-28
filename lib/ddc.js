.pragma library

// Parses `ddcutil detect --brief` (only valid "Display N" blocks).
function parseDetect(text) {
    return text.trim().split("\n\n").filter(b => b.indexOf("Display ") === 0).map(b => {
        const bus = b.match(/I2C bus:\s*\/dev\/i2c-([0-9]+)/);
        const conn = b.match(/DRM connector:\s+(\S+)/);
        return bus && conn ? { bus: bus[1], connector: conn[1].replace(/^card\d+-/, "") } : null;
    }).filter(x => x !== null);
}

// Parses lines "<bus> VCP 10 C <cur> <max>" produced by readCommand.
function parseLevels(text) {
    const out = {};
    for (const line of text.split("\n")) {
        const m = line.trim().match(/^(\d+) VCP 10 C (\d+) (\d+)$/);
        if (m && parseInt(m[3]) > 0)
            out[m[1]] = parseInt(m[2]) / parseInt(m[3]);
    }
    return out;
}

// One shell command reading every bus; buses must be digits only.
function readCommand(buses) {
    if (!buses.every(b => /^\d+$/.test(b)))
        return "";
    return buses.map(b => `ddcutil -b ${b} getvcp 10 --brief | sed 's/^/${b} /'`).join("; ");
}

function step(value, delta) {
    return Math.round(Math.max(0, Math.min(1, value + delta)) * 100) / 100;
}

// Serial writer state: {running: {name: bool}, pending: {name: value}}. Returns the value to write now, or null.
function request(state, name, value) {
    const running = Object.assign({}, state.running);
    const pending = Object.assign({}, state.pending);
    if (running[name]) {
        pending[name] = value;
        return { state: { running, pending }, start: null };
    }
    running[name] = true;
    return { state: { running, pending }, start: value };
}

// Call when a write for `name` exits; starts the newest queued value, if any.
function finished(state, name) {
    const running = Object.assign({}, state.running);
    const pending = Object.assign({}, state.pending);
    if (pending[name] !== undefined) {
        const start = pending[name];
        delete pending[name];
        return { state: { running, pending }, start };
    }
    running[name] = false;
    return { state: { running, pending }, start: null };
}

// Applies a fresh read; monitors with a write running or queued, or written since the read started
// (`writtenSince`), keep the value being written.
function mergeRead(levels, read, state, writtenSince) {
    const out = Object.assign({}, levels);
    const running = (state && state.running) || {};
    const pending = (state && state.pending) || {};
    const written = writtenSince || {};
    for (const name in read)
        if (!running[name] && pending[name] === undefined && !written[name])
            out[name] = read[name];
    return out;
}
