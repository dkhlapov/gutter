.pragma library

function bytes(n) {
    const units = ["B", "KiB", "MiB", "GiB", "TiB"];
    let v = Math.max(0, n || 0);
    let i = 0;
    while (v >= 1024 && i < units.length - 1) {
        v /= 1024;
        i++;
    }
    return (i === 0 ? v.toFixed(0) : v.toFixed(1)) + " " + units[i];
}

function kib(n) {
    return bytes((n || 0) * 1024);
}

function pad(n) {
    return n < 10 ? "0" + n : String(n);
}

function duration(seconds) {
    const s = Math.max(0, Math.floor(seconds || 0));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    return h > 0 ? `${h}:${pad(m)}:${pad(s % 60)}` : `${m}:${pad(s % 60)}`;
}
