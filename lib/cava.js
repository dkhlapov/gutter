.pragma library

// The cava side of the audio visualiser: the config it is run with and the parser for what it prints. Pure
// functions; services/Cava.qml owns the process.

// cava's config: the PipeWire default source in, one ASCII frame per line out, bars separated by ";" (59) and
// frames by newline (10), each bar 0..1000.
function config(bars, framerate) {
    return [
        "[general]",
        `bars = ${bars}`,
        `framerate = ${framerate}`,
        "",
        "[input]",
        "method = pipewire",
        "source = auto",
        "",
        "[output]",
        "method = raw",
        "data_format = ascii",
        "ascii_max_range = 1000",
        "bar_delimiter = 59",
        "frame_delimiter = 10",
        ""
    ].join("\n");
}

function zeros(bars) {
    return new Array(bars).fill(0);
}

// One output line as `bars` values 0..1. A trailing delimiter is fine; an empty, short or garbled line (a torn
// read, or the process starting up) is silence, not a partial frame. Extra values are dropped.
function parseFrame(line, bars) {
    const parts = String(line ?? "").trim().split(";");
    if (parts[parts.length - 1] === "")
        parts.pop();
    if (parts.length < bars)
        return zeros(bars);
    const out = [];
    for (let i = 0; i < bars; i++) {
        const v = /^-?\d+(\.\d+)?$/.test(parts[i].trim()) ? Number(parts[i]) : NaN;
        if (isNaN(v))
            return zeros(bars);
        out.push(Math.min(1, Math.max(0, v / 1000)));
    }
    return out;
}
