.pragma library

// The folder Gutter keeps its state in: $XDG_STATE_HOME/gutter, else $HOME/.local/state/gutter,
// or "" when neither is set (so the caller has no file to read instead of one under "/.local/state").
function stateDir(xdgStateHome, home) {
    var base = xdgStateHome || (home ? home + "/.local/state" : "");
    return base ? base + "/gutter" : "";
}

// Turns the text of a wallpaper path file into one absolute path, or "" if there is none.
// The first non-blank line is used. A leading "~/" expands to home. Anything else that is not
// absolute (relative paths, "~user/", bare "~") gives "".
function parsePath(text, home) {
    if (typeof text !== "string")
        return "";
    var lines = text.split(/\r?\n/);
    var line = "";
    for (var i = 0; i < lines.length; i++) {
        var t = lines[i].trim();
        if (t !== "") {
            line = t;
            break;
        }
    }
    if (line.indexOf("~/") === 0) {
        if (!home || home.charAt(0) !== "/")
            return "";
        var rest = line.slice(2);
        if (rest.trim() === "")
            return "";
        line = home.replace(/\/+$/, "") + "/" + rest;
    }
    if (line.charAt(0) !== "/" || line.replace(/\/+$/, "") === "")
        return "";
    return line;
}
