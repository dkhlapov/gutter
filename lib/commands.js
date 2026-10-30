.pragma library
.import "launcher.js" as Launcher

var MAX_MINUTES = 1440;

function command(name, description, glyph, run, extra) {
    return {
        name: name,
        description: description,
        glyph: glyph,
        arg: extra && extra.arg ? extra.arg : "",
        confirm: !!(extra && extra.confirm),
        run: run
    };
}

// The slash commands, in the order they list when nothing is typed: the session actions (`powerEntries`, from
// power.js, so an action logind rules out is not offered), then the shell's own, then one `open` per section.
// Glyphs are Material Design Icons.
function list(sections, powerEntries) {
    const out = [];
    for (const e of powerEntries || [])
        out.push(command(e.id, e.label, e.icon, { type: "power", value: e.id }, { confirm: e.confirm }));
    out.push(command("session", "Open the session screen", "\u{f0a89}", { type: "session", value: "" })); // md-dock-window
    out.push(command("dark", "Switch to the dark page", "\u{f0594}", { type: "theme", value: "dark" })); // md-weather-night
    out.push(command("light", "Switch to the light page", "\u{f0599}", { type: "theme", value: "light" })); // md-white-balance-sunny
    out.push(command("theme", "Flip between light and dark", "\u{f050e}", { type: "theme", value: "toggle" })); // md-theme-light-dark
    out.push(command("dnd", "Toggle do-not-disturb", "\u{f009b}", { type: "dnd", value: "" })); // md-bell-off
    out.push(command("clear", "Clear the notification history", "\u{f01b4}", { type: "clear", value: "" })); // md-delete
    out.push(command("mute", "Toggle mute", "\u{f0581}", { type: "mute", value: "" })); // md-volume-off
    out.push(command("timer", "Start a countdown", "\u{f13ab}", { type: "timer", value: "" }, { arg: "minutes" })); // md-timer
    out.push(command("stopwatch", "Start or stop the stopwatch", "\u{f051f}", { type: "stopwatch", value: "" })); // md-timer-play
    for (const s of sections || [])
        out.push(command("open " + s, "Open the section on this monitor", "\u{f03cc}", { type: "open", value: s })); // md-open-in-new
    return out;
}

// A countdown length in minutes: a plain decimal number above 0 and at most a day. Never parsed from anything looser.
function validMinutes(text) {
    if (!/^\d+(\.\d+)?$/.test(text))
        return false;
    const n = Number(text);
    return isFinite(n) && n > 0 && n <= MAX_MINUTES;
}

// The commands for what was typed after the slash, best first. { command, arg, ready }: `ready` says the command
// can run as typed; a command that takes an argument is not ready until it has a good one.
function match(commands, text) {
    const t = String(text === undefined || text === null ? "" : text).trim();
    const scored = [];
    commands.forEach(function (c, index) {
        if (t === "") {
            scored.push({ command: c, arg: "", ready: c.arg === "", score: 0, index: index });
            return;
        }
        if (c.arg !== "") {
            const space = t.search(/\s/);
            const first = space === -1 ? t : t.slice(0, space);
            const rest = space === -1 ? "" : t.slice(space).trim();
            if (first.toLowerCase() === c.name) {
                scored.push({ command: c, arg: rest, ready: validMinutes(rest), score: Launcher.fuzzy(first, c.name), index: index });
            } else {
                // A partly typed name keeps its argument, so Tab completes to "/timer 5"; only the full name is ready.
                const s = Launcher.fuzzy(first, c.name);
                if (s > 0)
                    scored.push({ command: c, arg: rest, ready: false, score: s, index: index });
            }
            return;
        }
        const s = Launcher.fuzzy(t, c.name);
        if (s > 0)
            scored.push({ command: c, arg: "", ready: true, score: s, index: index });
    });
    scored.sort((a, b) => b.score - a.score || a.index - b.index);
    return scored.map(s => ({ command: s.command, arg: s.arg, ready: s.ready }));
}

// How to type a command: "/timer <minutes>" or "/lock".
function usage(command) {
    return "/" + command.name + (command.arg !== "" ? " <" + command.arg + ">" : "");
}
