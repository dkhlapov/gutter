import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.settings
import qs.services
import qs.theme
import "../lib/pillState.js" as PillState

// The workspace bar's surface on one monitor, at the top left. Like the top-right bar it reserves no room and
// floats in the gap the pill's exclusive zone keeps clear; only the row of boxes takes input. The bar stops short
// of the island's widest face (an activity, hovered), so it never runs under it or off the monitor. The side pills
// and the open panel are on the Overlay layer and cover any tail of a long bar that reaches them.
PanelWindow {
    id: win

    required property ShellScreen modelData

    screen: modelData

    anchors.top: true
    anchors.left: true
    implicitWidth: Theme.pillTop + bar.width + Theme.shadowOffset + Theme.shadowKeyline
    implicitHeight: Theme.pillTop + Theme.pillHeight + Theme.shadowOffset + Theme.shadowKeyline
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // On the top layer Hyprland hides it under a fullscreen window and shows it again after. The layer never
    // follows fullscreen: a surface moved below the overlay layer under a fullscreen window is hidden for good, and
    // unmapping it crashes Qt with a TrayIcon inside (test_windows.py).
    WlrLayershell.layer: Settings.hideInFullscreen ? WlrLayer.Top : WlrLayer.Overlay
    WlrLayershell.namespace: "gutter-workspaces"

    mask: Region {
        item: bar.boxItem
    }

    WorkspaceBar {
        id: bar

        x: Theme.pillTop
        y: Theme.pillTop
        screenName: win.modelData.name
        maxWidth: Math.max(0, (win.modelData.width - PillState.ACTIVITY_MAX_W - PillState.PEEK_W) / 2 - Theme.pillTop - Theme.gap)
    }
}
