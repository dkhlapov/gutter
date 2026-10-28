.pragma library

// Workspaces come in groups of ten, one group per monitor (1-10, 11-20, ...), as the workspace pinning in your
// ~/.config/gutter/hypr-user.lua sets them up.
var SIZE = 10;

// First id of the group a monitor shows: the decade of its active workspace id, else 1.
function groupFirst(activeId) {
    if (!(activeId > 0))
        return 1;
    return Math.floor((activeId - 1) / SIZE) * SIZE + 1;
}

// Ids 1 and 11 share a colour, so a group looks alike on every monitor.
function accentFor(id, accents) {
    return accents[(id - 1) % SIZE % accents.length];
}

// Next workspace id inside first .. first + 9, wrapping at both ends.
function step(activeId, first, delta) {
    var offset = (activeId - first + delta) % SIZE;
    if (offset < 0)
        offset += SIZE;
    return first + offset;
}

function cellState(ws, active) {
    if (ws && ws.urgent)
        return "urgent";
    if (active)
        return "active";
    if (ws && ws.windows > 0)
        return "occupied";
    return "empty";
}

// workspaces: [{ id, name, windows, urgent, apps }]. `count` regular cells from `first` (ten by default), then one
// per open special workspace; each cell carries its workspace's app ids (`apps`, [] for none).
// `special` names the special workspace shown on this monitor ("special:music", or "" for none): it covers the
// active workspace, so it is the active cell while it shows. Specials open on other monitors are not active here.
function cells(first, workspaces, activeId, accents, special, count) {
    special = special || "";
    count = count || SIZE;
    var byId = {};
    var specials = [];
    for (var i = 0; i < workspaces.length; i++) {
        var w = workspaces[i];
        if (w.id < 0)
            specials.push(w);
        else
            byId[w.id] = w;
    }

    var out = [];
    for (var n = 0; n < count; n++) {
        var id = first + n;
        out.push({ id: id, label: String(id), state: cellState(byId[id], special === "" && id === activeId), accent: accentFor(id, accents), apps: appsOf(byId[id]) });
    }
    for (var s = 0; s < specials.length; s++) {
        var sp = specials[s];
        out.push({ id: sp.id, label: String(sp.name).replace(/^special:/, ""), name: sp.name, state: cellState(sp, sp.name === special), accent: "magenta", apps: appsOf(sp) });
    }
    return out;
}

function appsOf(ws) {
    return ws && ws.apps ? ws.apps : [];
}

// The workspace bar shows five workspaces of a monitor's ten at a time: the half of the group the active one is
// in (1-5 or 6-10 for the first group). An active workspace outside the group shows the first half.
var PAGE = 5;

function pageFirst(first, activeId) {
    var offset = activeId - first;
    if (!(offset >= 0 && offset < SIZE))
        return first;
    return first + Math.floor(offset / PAGE) * PAGE;
}

// The app ids to draw as icons for a workspace: each app once, in window order, at most `max` of them, and how
// many more there are. Ids are compared ignoring case; empty ones are skipped.
function appSummary(ids, max) {
    var seen = {};
    var unique = [];
    for (var i = 0; i < ids.length; i++) {
        var id = String(ids[i] || "");
        var key = id.toLowerCase();
        if (id === "" || seen[key])
            continue;
        seen[key] = true;
        unique.push(id);
    }
    return { apps: unique.slice(0, max), more: Math.max(0, unique.length - max) };
}

// Glyphs for the special workspaces hypr-user.lua opens (Material Design Icons, plane 15).
var SPECIAL_ICONS = {
    communication: "\u{f028c}", // md-forum
    music: "\u{f075a}", // md-music
    game: "\u{f0297}", // md-gamepad_variant
    sysmon: "\u{f0a07}", // md-monitor_dashboard
    todo: "\u{f0756}", // md-format_list_checks
    special: "\u{f0ae2}", // md-star_four_points: the scratch special workspace
    hidden: "\u{f0209}" // md-eye_off
};

// What the pill's label tab shows for a special workspace (`special:music` or `music`): its glyph, or the first
// letter of a name without one.
function specialIcon(name) {
    var bare = String(name).replace(/^special:/, "");
    if (Object.prototype.hasOwnProperty.call(SPECIAL_ICONS, bare))
        return SPECIAL_ICONS[bare];
    return bare.charAt(0).toUpperCase();
}

// A Lua double-quoted string literal. Workspace names are user text and Hyprland 0.56 parses a dispatch as
// Lua, so a name is never interpolated into one raw.
function luaString(text) {
    return '"' + String(text).replace(/[\\"\n\r]/g, function (c) {
        return c === "\n" ? "\\n" : c === "\r" ? "\\r" : "\\" + c;
    }) + '"';
}

// Dispatch (Lua) that focuses a workspace by id or name. With a monitor it focuses that monitor and, when another
// monitor holds the workspace, moves it there first: a plain focus jumps to whichever monitor holds the workspace, so
// a workspace that has strayed from its group's monitor would send a click on one monitor's bar to the other.
function focusCommand(workspace, monitor) {
    var focus = "hl.dsp.focus({ workspace = " + luaString(workspace) + " })";
    if (!monitor)
        return focus;
    return "(function() local ws = hl.get_workspace(" + luaString(workspace) + ") "
        + "hl.dispatch(hl.dsp.focus({ monitor = " + luaString(monitor) + " })) "
        + "if ws and ws.monitor and ws.monitor.name ~= " + luaString(monitor) + " then "
        + "hl.dispatch(hl.dsp.workspace.move({ workspace = " + luaString(workspace) + ", monitor = " + luaString(monitor) + " })) end "
        + "return " + focus + " end)()";
}

// Dispatch (Lua) that shows or hides a special workspace; `name` is `special:music` or `music`.
function toggleSpecialCommand(name) {
    return "hl.dsp.workspace.toggle_special(" + luaString(String(name).replace(/^special:/, "")) + ")";
}
