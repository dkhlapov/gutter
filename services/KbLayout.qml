pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../lib/status.js" as StatusLib

// The main keyboard's active layout name ("Swedish (no dead keys)"), kept current from Hyprland's
// `activelayout` event.
Singleton {
    id: root

    // The last layout read; kept when a refresh fails.
    property string layout: ""
    // False until the first read finds a keyboard, and while hyprctl fails or reports none.
    property bool available: false
    property bool warned: false

    // Switches every keyboard: layouts are configured once for all of them.
    function next(): void {
        switcher.run(["hyprctl", "switchxkblayout", "all", "next"], null);
    }

    function refresh(): void {
        reader.run(["hyprctl", "devices", "-j"], null);
    }

    QueuedProcess {
        id: reader

        onFinished: text => {
            const state = StatusLib.layoutState(root.layout, text);
            root.layout = state.layout;
            root.available = state.available;
            if (state.available)
                root.warned = false;
            else if (!root.warned) {
                console.warn("gutter: no keyboard layout from hyprctl, hiding the keyboard chip");
                root.warned = true;
            }
        }
    }

    QueuedProcess {
        id: switcher
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "activelayout")
                root.refresh();
        }
    }

    Component.onCompleted: refresh()
}
