pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../lib/hypr.js" as HyprLib

Singleton {
    id: root

    readonly property string focusedScreenName: Hyprland.focusedMonitor?.name ?? ""

    // Windows in the order they were last focused, most recent first: Hyprland names only one active window, so
    // a monitor without focus finds its own here.
    property var recentToplevels: []

    function noteActive(): void {
        recentToplevels = HyprLib.remember(recentToplevels, Hyprland.activeToplevel, 32);
    }

    // Reactive. The active window on a monitor, or null when there is none: the focused window on the focused
    // monitor, else the one focused last on the workspace in view there. Hyprland keeps the last one as active
    // after its workspace empties or a special workspace covers it, so it only counts while it is on the layer
    // in view.
    function activeToplevelOn(screenName: string): HyprlandToplevel {
        const monitor = Hyprland.monitors.values.find(m => m.name === screenName);
        const active = monitor?.activeWorkspace?.name ?? "";
        const special = HyprLib.specialName(monitor?.lastIpcObject);
        const toplevel = monitor && monitor === Hyprland.focusedMonitor ? Hyprland.activeToplevel : HyprLib.lastOn(recentToplevels, special !== "" ? special : active);
        return HyprLib.toplevelOnTop(toplevel?.workspace?.name ?? "", active, special) ? toplevel : null;
    }

    function hasFullscreen(screenName: string): bool {
        const monitor = Hyprland.monitors.values.find(m => m.name === screenName);
        const special = HyprLib.specialName(monitor?.lastIpcObject);
        const specialWorkspace = special ? Hyprland.workspaces.values.find(w => w.name === special) : null;
        return HyprLib.fullscreen(monitor?.activeWorkspace, specialWorkspace);
    }

    property bool primed: false

    // The first refresh fills the monitors' IPC snapshots. It waits for Quickshell's own initial load:
    // refreshing before that leaves Hyprland.focusedMonitor null until the next focus change, and the
    // pill would stay unmapped.
    function prime(): void {
        if (primed || !Hyprland.focusedMonitor)
            return;
        primed = true;
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
    }

    // Monitor objects carry no special-workspace property; only their IPC snapshot does, so refresh it on toggles.
    // Workspace objects carry no fullscreen state until refreshed either: without it a fullscreen game on a special
    // workspace never counts as fullscreen.
    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (HyprLib.refreshesWorkspaces(event.name)) {
                Hyprland.refreshMonitors();
                Hyprland.refreshWorkspaces();
            }
        }

        function onFocusedMonitorChanged(): void {
            root.prime();
        }

        function onActiveToplevelChanged(): void {
            root.noteActive();
        }
    }

    Component.onCompleted: {
        prime();
        noteActive();
    }
}
