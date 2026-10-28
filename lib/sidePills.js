.pragma library
.import "agentUsage.js" as U

// The pills beside the island while something long-running goes on: music playing (left) and an agent working
// or waiting for you (right). Which one shows, what it says, and where it sits around the island.

// Wider than this a pill elides its text, even when the surface has the room.
var SIDE_MAX_W = 280;

// The music pill's content, or null while nothing plays. `f`: { playing, title, artist }.
function music(f) {
    if (!f.playing)
        return null;
    return { title: f.title || "Playing", artist: f.artist || "" };
}

// The agent pill's content, or null while no session works or waits. A session that needs you wins; with
// several working, the one that has worked longest sets the time (-1: none known).
function agent(items, now) {
    if (items.some(s => s.status === "waiting"))
        return { kind: "waiting", elapsed: -1 };
    const working = items.filter(s => s.status === "working");
    if (working.length === 0)
        return null;
    const since = working.map(s => s.promptAt).filter(t => t > 0);
    return { kind: "working", elapsed: since.length > 0 ? now - Math.min(...since) : -1 };
}

function agentLabel(model) {
    if (model.kind === "waiting")
        return "waiting";
    return model.elapsed >= 0 ? U.clock(model.elapsed) : "";
}

// Where the pills sit on a surface `surfaceW` wide with the island `islandW` wide in its centre: `gap` clear of
// the island, `edge` clear of the surface's sides (room for the shadow and keyline). `want`: { left, right }, the
// widths asked for, 0 for an absent pill. Both sides are capped to the same room, so the surface stays
// symmetric about the island, which never moves for them.
function layout(surfaceW, islandW, gap, edge, want) {
    const room = Math.max(0, Math.floor((surfaceW - islandW) / 2 - gap - edge));
    const cap = Math.min(SIDE_MAX_W, room);
    const islandX = (surfaceW - islandW) / 2;
    const leftW = Math.min(want.left, cap);
    const rightW = Math.min(want.right, cap);
    return { leftW, rightW, leftX: islandX - gap - leftW, rightX: islandX + islandW + gap };
}

// What the pointer is on, from each box's hover: "island", "music" (the music pill), "agents" (the Claude pill) or
// "" for none. The island and the pills hover as one (the panel opens from any, a pill on its own section), but
// each peeks only while the pointer is on it.
function pointerOn(island, music, claude) {
    return island ? "island" : music ? "music" : claude ? "agents" : "";
}
