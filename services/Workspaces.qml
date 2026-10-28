pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../lib/hypr.js" as HyprLib
import "../lib/palette.js" as PaletteLib
import "../lib/workspaces.js" as WS

// A monitor's workspace group (the decade of its active workspace) and switching within it.
// `special` is the special workspace shown on the monitor ("" for none), read from its IPC snapshot, which
// Hypr refreshes on every activespecial event.
Singleton {
    id: root

    // Reactive: a binding calling this re-evaluates when workspaces or monitors change.
    function forScreen(screenName: string): var {
        const s = monitorState(screenName);
        return {
            first: s.first,
            activeId: s.activeId,
            special: s.special,
            cells: WS.cells(s.first, workspaceList(), s.activeId, PaletteLib.ACCENTS, s.special)
        };
    }

    // The workspace bar's five: the half of the monitor's group the active workspace is in, then the open special
    // workspaces. Reactive like forScreen.
    function pageFor(screenName: string): var {
        const s = monitorState(screenName);
        const first = WS.pageFirst(s.first, s.activeId);
        return {
            first,
            activeId: s.activeId,
            special: s.special,
            cells: WS.cells(first, workspaceList(), s.activeId, PaletteLib.ACCENTS, s.special, WS.PAGE)
        };
    }

    // An app's icon from its desktop entry (matched loosely on the app id), or "" when the theme has none.
    // Reading the entry list makes a binding look again once the entries have loaded.
    function appIcon(appId: string): string {
        const loaded = DesktopEntries.applications.values.length > 0;
        const icon = (loaded ? DesktopEntries.heuristicLookup(appId)?.icon : null) ?? appId;
        return Quickshell.iconPath(icon, true);
    }

    function monitorState(screenName: string): var {
        const monitor = Hyprland.monitors.values.find(m => m.name === screenName);
        const activeId = monitor?.activeWorkspace?.id ?? 0;
        return {
            activeId,
            special: HyprLib.specialName(monitor?.lastIpcObject),
            first: WS.groupFirst(activeId)
        };
    }

    // Every workspace with its windows' app ids, in window order.
    function workspaceList(): var {
        return Hyprland.workspaces.values.map(w => ({
                    id: w.id,
                    name: w.name,
                    windows: w.toplevels.values.length,
                    urgent: w.urgent,
                    apps: w.toplevels.values.map(t => t.wayland?.appId ?? t.lastIpcObject?.class ?? "")
                }));
    }

    // Hyprland 0.56 reads dispatches as Lua, so the legacy `workspace N` text no longer parses (the Lua forms
    // live in lib/workspaces.js, which escapes the names). A regular workspace is focused by its id; a special
    // one (negative id) is shown or hidden by its name.
    // `screenName` is the monitor the workspace is shown on: a workspace that sits on another monitor is brought here.
    function goTo(id: int, screenName: string): void {
        if (id >= 0) {
            Hyprland.dispatch(WS.focusCommand(String(id), screenName));
            return;
        }
        const name = Hyprland.workspaces.values.find(w => w.id === id)?.name ?? "";
        if (name !== "")
            Hyprland.dispatch(WS.toggleSpecialCommand(name));
    }

    function stepOn(screenName: string, delta: int): void {
        const s = forScreen(screenName);
        goTo(WS.step(s.activeId, s.first, delta), screenName);
    }
}
