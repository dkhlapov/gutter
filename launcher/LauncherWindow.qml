import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.theme

// The launcher's surface on one monitor: a box a little below the top edge, centred, over everything. It is mapped
// only on the monitor whose launcher is open, and takes the keyboard while it is: on demand, because the focus grab
// hands it the focus, whereas an exclusive surface keeps Hyprland from clearing the grab on a click outside. The
// surface is as tall as the tallest view can get (a full list of rows, or the session screen with its confirmation
// strip), so either grows inside it without the surface changing size; only the view shown takes input, the rest
// lets clicks through, and a click outside closes it. It never follows a fullscreen window: it only exists while
// it is wanted, and holds nothing that would crash on a remap (test_windows.py). Its sizes (not its text) grow with
// the monitor's height (`ui`), so it keeps its look on a big screen.
PanelWindow {
    id: win

    required property ShellScreen modelData
    // Room around the box for its shadow and keyline.
    readonly property real margin: Theme.shadowOffset + Theme.shadowKeyline
    // The scale of the launcher's own sizes: 1 up to 960 px of monitor height, then in proportion (1.5 at 1440).
    // The ink width, shadow and keyline are the shell's and do not scale.
    readonly property real ui: Math.max(1, modelData.height / 960)

    screen: modelData
    visible: Launcher.screen === modelData.name

    anchors.top: true
    margins.top: Math.round(modelData.height * 0.18)
    implicitWidth: Math.max(box.width, session.width) + 2 * margin
    implicitHeight: Math.max(box.tallestHeight, session.tallestHeight) + 2 * margin
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "gutter-launcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    mask: Region {
        item: contentBox
    }

    // The view that takes the keys: the search box, or the session screen.
    function focusView(): void {
        if (Launcher.mode === "session")
            session.focusScreen();
        else
            box.focusInput();
    }

    onVisibleChanged: {
        if (visible)
            focusView();
    }

    // The mode changes under an open window (`session` over the IPC, or /session typed): once the views have
    // swapped, the one now shown takes the focus.
    Connections {
        target: Launcher

        function onModeChanged(): void {
            if (win.visible)
                Qt.callLater(win.focusView);
        }
    }

    HyprlandFocusGrab {
        windows: [win]
        active: win.visible
        onCleared: Launcher.close()
    }

    // The sizes the box, its rows and the session screen share.
    LauncherMetrics {
        id: sizes

        ui: win.ui
    }

    // What takes input: the launcher box or the session screen, chosen by Launcher.mode. The one not shown is
    // invisible, so it neither swallows clicks nor keeps the focus, and the mask is the shown one's box.
    Item {
        id: contentBox

        x: win.margin
        y: win.margin
        width: Launcher.mode === "session" ? session.width : box.width
        height: Launcher.mode === "session" ? session.height : box.height

        LauncherBox {
            id: box

            metrics: sizes
            visible: Launcher.mode === "launcher"
        }

        SessionScreen {
            id: session

            metrics: sizes
            visible: Launcher.mode === "session"
        }
    }
}
