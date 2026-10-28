pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/activities.js" as ActLib
import "../lib/keys.js" as KeysLib

// The source of the keys HUD: a short pop-up for a Caps Lock or Num Lock toggle and for a layout switch.
// Hyprland sends no event for the lock keys and the LED files raise no inotify events, so a non-consuming bind on
// each key (hypr/gutter/keybinds.lua, global shortcuts in ipc/Shortcuts.qml) calls `poke()`, which reads the
// keyboards' LEDs once the compositor has updated them. The LEDs are the compositor's own xkb state, shared by
// every keyboard, which `hyprctl devices -j` is not (it holds one state per device). Layout switches come from
// KbLayout. Nothing shows at start-up or while the screen is locked; a lock state read meanwhile is kept, so an
// unlock does not announce it.
Singleton {
    id: root

    // The last reading; null until the first.
    property var locks: null
    readonly property bool caps: locks?.caps ?? false
    readonly property bool num: locks?.num ?? false
    // The kind (KeysLib.name) of the last change shown, and for a lock key whether it went on.
    property string kind: ""
    // The layout seen last, so that a switch is told from the first reading.
    property string seenLayout: ""

    // A lock key was pressed: read the LEDs after the compositor had its turn.
    function poke(): void {
        settle.restart();
    }

    function announce(kind: string): void {
        root.kind = kind;
        if (KeysLib.allowed(Lock.locked, Lock.preview))
            Activities.show(KeysLib.activityId(kind), ActLib.PRIORITY.keys, 1500, "");
    }

    Connections {
        target: KbLayout

        function onLayoutChanged(): void {
            const prev = root.seenLayout;
            root.seenLayout = KbLayout.layout;
            if (KeysLib.layoutChanged(prev, KbLayout.layout))
                root.announce("layout");
        }
    }

    // The bind fires before the key reaches the xkb state, so the LEDs follow a moment later.
    Timer {
        id: settle

        interval: 60
        onTriggered: reader.run(["sh", "-c", `for k in capslock numlock; do v=0; for f in /sys/class/leds/*::$k/brightness; do [ -r "$f" ] && [ "$(cat "$f")" != 0 ] && v=1; done; echo "\${k%lock}=$v"; done`], null)
    }

    QueuedProcess {
        id: reader

        onFinished: text => {
            const next = KeysLib.parseLocks(text);
            if (next === null)
                return;
            const changes = KeysLib.lockChanges(root.locks, next);
            root.locks = next;
            for (const c of changes)
                root.announce(c.key);
        }
    }

    Component.onCompleted: {
        seenLayout = KbLayout.layout;
        settle.start();
    }
}
