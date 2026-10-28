.pragma library

// Prints the local offset, then one line per zone ("invalid" when /usr/share/zoneinfo lacks it).
// Zones arrive as positional arguments, never inside the script text.
var SCRIPT = 'date +%z; for z; do if [ -f "/usr/share/zoneinfo/$z" ]; then TZ="$z" date +%z; else echo invalid; fi; done';

function validZone(z) {
    return typeof z === "string" && /^[A-Za-z0-9_+-]+(\/[A-Za-z0-9_+-]+)*$/.test(z);
}

function command(zones) {
    return ["sh", "-c", SCRIPT, "sh"].concat(zones.map(z => validZone(z) ? z : "invalid"));
}

function parseOffset(s) {
    const m = /^([+-])(\d\d)(\d\d)$/.exec(String(s || "").trim());
    if (!m)
        return null;
    const v = parseInt(m[2], 10) * 60 + parseInt(m[3], 10);
    return m[1] === "-" ? -v : v;
}

function parseOffsets(text, count) {
    const lines = String(text || "").split("\n");
    const zones = [];
    for (let i = 0; i < count; i++)
        zones.push(parseOffset(lines[i + 1]));
    return { local: parseOffset(lines[0]), zones };
}

// Every zone changes its offset on a quarter hour (UTC), so refreshing a little after each one keeps the
// offsets right within seconds of a DST switch anywhere.
var QUARTER_MS = 15 * 60 * 1000;
var SETTLE_MS = 2000;

function msToNextRefresh(nowMs) {
    return QUARTER_MS - (nowMs % QUARTER_MS) + SETTLE_MS;
}

function pad(n) {
    return n < 10 ? "0" + n : String(n);
}

// QML's JS engine cannot format arbitrary zones; shift UTC by the zone's offset instead.
function timeAt(nowMs, offsetMin) {
    const d = new Date(nowMs + offsetMin * 60000);
    return pad(d.getUTCHours()) + ":" + pad(d.getUTCMinutes());
}

function relative(offsetMin, localMin) {
    const diff = offsetMin - localMin;
    if (diff === 0)
        return "0 h";
    const a = Math.abs(diff);
    const h = Math.floor(a / 60);
    const m = a % 60;
    return (diff > 0 ? "+" : "−") + (m === 0 ? `${h} h` : `${h} h ${m} m`);
}

// Per-tile data for the configured clocks; the time itself is computed by each tile.
function tiles(clocks, offsets, localMin) {
    return clocks.map((c, i) => {
        const offsetMin = offsets[i] ?? null;
        return {
            label: c.label,
            offsetMin,
            relative: offsetMin === null || localMin === null ? "" : relative(offsetMin, localMin)
        };
    });
}
