.pragma library

var PLAYBACK = "Stream/Output/Audio";
// The master slider's accent; no application strip uses it.
var MASTER_ACCENT = "teal";

// One row of the mixer for a PipeWire node, or null when the node is not an application playing audio.
// `n` carries what Quickshell exposes: id, name, description and the property bag.
function describe(n) {
    const p = (n && n.properties) || {};
    if (p["media.class"] !== PLAYBACK)
        return null;
    const app = String(p["application.name"] || n.description || n.name || p["node.name"] || "").trim();
    if (app === "")
        return null;
    const title = String(p["media.name"] || "").trim();
    return {
        id: n.id,
        app,
        title: title.toLowerCase() === app.toLowerCase() ? "" : title,
        icon: String(p["application.icon-name"] || p["application.process.binary"] || app).toLowerCase()
    };
}

// Stable order (name, then node id) so sliders do not jump while something is dragged.
function byApp(a, b) {
    return a.row.app.localeCompare(b.row.app) || a.row.id - b.row.id;
}

// Describe every node once, keep the playback ones and sort them.
function sorted(nodes) {
    return nodes.map(node => ({ node, row: describe(node) })).filter(e => e.row !== null).sort(byApp);
}

function apps(nodes) {
    return sorted(nodes).map(e => e.row);
}

// The playback nodes themselves, in the same order as apps().
function playback(nodes) {
    return sorted(nodes).map(e => e.node);
}

// The accent of the application strip at `position`: the palette in order, minus the master's, so no strip
// shares the master slider's colour.
function stripAccent(position, accents) {
    const rest = accents.filter(a => a !== MASTER_ACCENT);
    return rest[position % rest.length];
}
