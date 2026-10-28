.pragma library

// Name of the special workspace shown on a monitor, from its Hyprland IPC object ("" if none).
function specialName(monitorIpc) {
    return monitorIpc?.specialWorkspace?.name ?? "";
}

// Raw Hyprland events after which the special workspace in view, or a workspace's fullscreen flag, may have changed.
// Quickshell's workspace objects carry no fullscreen state until they are refreshed, so these refresh them.
var REFRESH_EVENTS = ["activespecial", "fullscreen"];

function refreshesWorkspaces(eventName) {
    return REFRESH_EVENTS.indexOf(eventName) !== -1;
}

// A special workspace is drawn over the active one, so either can hold the fullscreen window.
function fullscreen(activeWorkspace, specialWorkspace) {
    return (specialWorkspace?.hasFullscreen ?? false) || (activeWorkspace?.hasFullscreen ?? false);
}

// Whether a toplevel on workspace `toplevelWorkspace` is the one in view: the special workspace covers the
// active one, so it decides when shown. Hyprland keeps reporting the last focused window after it is covered
// or its workspace empties, so "active toplevel" alone is not enough to say there is a focused window.
function toplevelOnTop(toplevelWorkspace, activeWorkspace, special) {
    return toplevelWorkspace !== "" && toplevelWorkspace === (special !== "" ? special : activeWorkspace);
}

// `recent` (most recently focused first) with `toplevel` moved to the front, at most `cap` long. Windows that
// close drop off the end in time; a closed one left in the list has no workspace, so it never matches.
function remember(recent, toplevel, cap) {
    if (!toplevel)
        return recent;
    return [toplevel].concat(recent.filter(t => t !== toplevel)).slice(0, cap);
}

// The window a monitor shows as active when it does not have focus: the one focused last on the workspace in
// view there (Hyprland gives it focus back), or null.
function lastOn(recent, workspaceName) {
    return workspaceName === "" ? null : recent.find(t => (t?.workspace?.name ?? "") === workspaceName) ?? null;
}
