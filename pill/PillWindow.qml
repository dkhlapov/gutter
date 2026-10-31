import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.settings
import qs.services
import qs.theme
import "../lib/pillState.js" as PillState

PanelWindow {
    id: win

    required property ShellScreen modelData

    screen: modelData

    anchors.top: true
    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight
    color: "transparent"
    // The zone keeps tiled windows below the collapsed pill and its shadow, Theme.pillTop clear of it.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 2 * Theme.pillTop + Theme.pillHeight + Theme.shadowOffset - Theme.windowGap
    // On the top layer Hyprland hides the pill under a fullscreen window and shows it again after. The layer never
    // follows fullscreen: a surface moved below the overlay layer under a fullscreen window is hidden for good, and
    // unmapping it crashes Qt with a TrayIcon inside (test_windows.py).
    WlrLayershell.layer: PillState.windowRaised({
        open: PillControl.openScreen === modelData.name,
        hideInFullscreen: Settings.hideInFullscreen
    }) ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.namespace: "gutter"
    WlrLayershell.keyboardFocus: pill.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // The pill, plus the side pills and the speech bubble while they show. The exclusive zone stays the collapsed
    // pill's.
    mask: Region {
        item: pill.inputItem

        Region {
            item: pill.musicInput
        }

        Region {
            item: pill.claudeInput
        }

        Region {
            item: pill.bubbleInput
        }
    }

    HyprlandFocusGrab {
        windows: [win]
        active: pill.open
        // A drag out of the shelf grabs the pointer, which can clear the grab; closing now would end it.
        onCleared: {
            if (!Shelf.dragging)
                PillControl.close();
        }
    }

    // Keep awake (Tools tab): only a mapped window can inhibit idle, so every visible pill holds it.
    IdleInhibitor {
        window: win
        enabled: QuickToggles.keepAwake && win.visible
    }

    Pill {
        id: pill

        anchors.fill: parent
        screenName: win.modelData.name
        screen: win.modelData
    }
}
