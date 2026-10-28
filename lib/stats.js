.pragma library

// Parsers for the system-stats sources the shell reads itself (/proc, df, sysfs, lspci). Pure functions over
// text: the shell polls the files and feeds them in. Fractions run 0..1, memory and disk sizes are kiB,
// network rates bytes per second.

// Aggregate "cpu " line of /proc/stat. total sums user..steal (guest time is already inside user), busy is
// everything but idle and iowait.
function parseCpuStat(text) {
    const m = /^cpu\s+(.*)$/m.exec(String(text ?? ""));
    if (!m)
        return { busy: 0, total: 0 };
    const f = m[1].trim().split(/\s+/).slice(0, 8).map(Number);
    if (f.length < 4 || f.some(isNaN))
        return { busy: 0, total: 0 };
    const total = f.reduce((a, b) => a + b, 0);
    return { busy: total - f[3] - (f[4] || 0), total: total };
}

// Busy share between two parseCpuStat samples. No previous sample (or an empty one from a failed read), no
// elapsed time or counters that went backwards read as idle.
function cpuFraction(prev, cur) {
    if (!prev || !cur || !(prev.total > 0))
        return 0;
    const dt = cur.total - prev.total;
    if (!(dt > 0))
        return 0;
    return Math.min(1, Math.max(0, (cur.busy - prev.busy) / dt));
}

// First "model name" of /proc/cpuinfo, "" when there is none.
function parseCpuModel(cpuinfo) {
    const m = /^model name\s*:\s*(.*)$/m.exec(String(cpuinfo ?? ""));
    return m ? m[1].trim() : "";
}

// /proc/meminfo: used is what applications hold, MemTotal less MemAvailable (MemFree on kernels without it).
function parseMeminfo(text) {
    const s = String(text ?? "");
    const field = name => {
        const m = new RegExp("^" + name + ":\\s*(\\d+)", "m").exec(s);
        return m ? Number(m[1]) : null;
    };
    const total = field("MemTotal");
    if (total === null || total <= 0)
        return { total: 0, used: 0, percentage: 0 };
    const avail = field("MemAvailable") ?? field("MemFree") ?? total;
    const used = Math.max(0, total - avail);
    return { total: total, used: used, percentage: Math.min(1, used / total) };
}

const VIRTUAL_NET = /^(lo|veth.*|docker.*|br-.*|virbr.*)$/;

// /proc/net/dev: received and transmitted bytes summed over the real interfaces.
function parseNetDev(text) {
    let rx = 0, tx = 0;
    for (const line of String(text ?? "").split("\n")) {
        const i = line.indexOf(":");
        if (i < 0 || line.indexOf("|") >= 0)
            continue;
        if (VIRTUAL_NET.test(line.slice(0, i).trim()))
            continue;
        const f = line.slice(i + 1).trim().split(/\s+/).map(Number);
        if (f.length < 9 || isNaN(f[0]) || isNaN(f[8]))
            continue;
        rx += f[0];
        tx += f[8];
    }
    return { rx: rx, tx: tx };
}

// Bytes per second between two parseNetDev samples. A previous sample with no bytes at all is a failed read,
// not a baseline (it would turn the next sample into a since-boot burst). A counter that went down (an interface vanished or
// wrapped) reads as no traffic for that direction.
function netSpeed(prev, cur, seconds) {
    if (!prev || !cur || !(prev.rx + prev.tx > 0) || !(seconds > 0))
        return { down: 0, up: 0 };
    return {
        down: Math.max(0, cur.rx - prev.rx) / seconds,
        up: Math.max(0, cur.tx - prev.tx) / seconds
    };
}

// A copy of the history with `value` appended and the oldest samples dropped past `max`.
function pushSample(buffer, value, max) {
    const out = (buffer || []).concat([value]);
    return max > 0 ? out.slice(-max) : [];
}

const PSEUDO_FS = /^(tmpfs|devtmpfs|squashfs|overlay|efivarfs|none)$/;

// `df -kP`: real filesystems once per device (bind mounts and subvolumes repeat the device). hasRoot marks "/".
function parseDf(text) {
    const out = [];
    const seen = {};
    for (const line of String(text ?? "").split("\n")) {
        const m = /^(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+\d+%\s+(\/.*)$/.exec(line.trim());
        if (!m || PSEUDO_FS.test(m[1]) || seen[m[1]])
            continue;
        seen[m[1]] = true;
        const total = Number(m[2]), used = Number(m[3]);
        out.push({
            mount: m[5],
            used: used,
            total: total,
            free: Number(m[4]),
            perc: total > 0 ? Math.min(1, used / total) : 0,
            hasRoot: m[5] === "/"
        });
    }
    return out;
}

// Index of the card to show: the one with the most VRAM among those that report gpu_busy_percent, else -1.
function pickGpu(cards) {
    let best = -1;
    (cards || []).forEach((c, i) => {
        if (c && c.busyOk && (best < 0 || c.vram > cards[best].vram))
            best = i;
    });
    return best;
}

// A hwmon temp*_input file (millidegrees) as °C, -1 when it is missing or not a number.
function parseTemp(text) {
    const s = String(text ?? "").trim();
    return /^-?\d+$/.test(s) ? Number(s) / 1000 : -1;
}

// Device name of one `lspci -mm` line: the bracketed marketing name when there is one ("Navi 48 [Radeon RX
// 9070]" gives "Radeon RX 9070"), else the plain name. The device is the third quoted field.
function parseLspciName(line) {
    const q = String(line ?? "").match(/"[^"]*"/g);
    if (!q || q.length < 3)
        return "";
    const dev = q[2].slice(1, -1);
    const b = /\[([^\]]+)\]/.exec(dev);
    return (b ? b[1] : dev).trim();
}
