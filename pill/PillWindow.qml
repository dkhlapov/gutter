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
    // Over a fullscreen window the pill drops to the bottom layer, under it, instead of unmapping: a window
    // that is destroyed and made again while a TrayIcon is inside crashes Qt (test_windows.py).
    WlrLayershell.layer: PillState.windowRaised({
        open: PillControl.openScreen === modelData.name,
        fullscreenHidden: Settings.hideInFullscreen && Hypr.hasFullscreen(modelData.name)
    }) ? WlrLayer.Overlay : WlrLayer.Bottom
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
