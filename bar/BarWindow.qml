import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.settings
import qs.services
import qs.theme

// The top-right bar's surface on one monitor. It reserves no room of its own: it floats in the gap the pill's
// exclusive zone keeps clear. The surface is tall enough for a menu below the bar; only the bar and an open menu
// take input, the rest lets clicks through. A click outside while a menu is open closes it.
PanelWindow {
    id: win

    required property ShellScreen modelData

    screen: modelData

    anchors.top: true
    anchors.right: true
    // At least as wide as a menu (InkMenu's body plus its outline and shadow room).
    implicitWidth: Math.max(bar.needWidth, 280 + Theme.pillTop)
    implicitHeight: 640
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // Over a fullscreen window it drops to the bottom layer, under it, instead of unmapping: a window that is
    // destroyed and made again while a TrayIcon is inside crashes Qt (test_windows.py).
    WlrLayershell.layer: Settings.hideInFullscreen && Hypr.hasFullscreen(modelData.name) ? WlrLayer.Bottom : WlrLayer.Top
    WlrLayershell.namespace: "gutter-bar"
    WlrLayershell.keyboardFocus: bar.menuOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        item: bar.boxItem

        Region {
            item: bar.menuItem
        }
    }

    HyprlandFocusGrab {
        windows: [win]
        active: bar.menuOpen
        onCleared: bar.closeMenus()
    }

    Bar {
        id: bar

        anchors.fill: parent
        screen: win.modelData
    }
}
