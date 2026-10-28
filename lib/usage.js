.pragma library

// Shape of the usage blob by load: calm cookie, busier sun, spiky burst when hot.
function shapeFor(p) {
    const v = Number(p) || 0;
    return v < 0.4 ? "cookie" : v < 0.8 ? "sunny" : "burst";
}

// /proc/cpuinfo names end in " 8-Core Processor"; a name cut short can end in a bare " 8-". Both go.
function cpuModel(name) {
    return String(name ?? "").replace(/\s+\d+-(Core Processor)?$/, "");
}

// Corners of the usage blob for a shape kind, centred on (cx, cy) with outer radius r: a star of `points`
// tips whose notches sit at `notch` of r. Calm is a blunt diamond-ish cookie, busy a sun, hot a spiky burst.
var SHAPES = {
    cookie: { points: 4, notch: 0.78, turn: -Math.PI / 4 },
    sunny: { points: 8, notch: 0.8, turn: -Math.PI / 2 },
    burst: { points: 12, notch: 0.58, turn: -Math.PI / 2 }
};

function shapeOutline(kind, cx, cy, r) {
    const s = SHAPES[kind] || SHAPES.cookie;
    const out = [];
    for (let i = 0; i < s.points * 2; i++) {
        const radius = i % 2 === 0 ? r : r * s.notch;
        const a = s.turn + i * Math.PI / s.points;
        out.push({ x: cx + radius * Math.cos(a), y: cy + radius * Math.sin(a) });
    }
    return out;
}
