import QtQuick
import Quickshell
import qs.services

// A failed check's jerk, for what shows it (the password field, the message bubble): `offset` is the sideways
// shift to translate by, 0 at rest, and every `Auth.flash` runs it once. Used as `transform: Translate { x: shake.offset }`
// so the item's own x and y stay with its layout.
Scope {
    id: root

    property real ui: 1
    property real offset: 0

    SequentialAnimation {
        id: shake

        NumberAnimation { target: root; property: "offset"; to: -8 * root.ui; duration: 40 }
        NumberAnimation { target: root; property: "offset"; to: 8 * root.ui; duration: 70 }
        NumberAnimation { target: root; property: "offset"; to: -5 * root.ui; duration: 60 }
        NumberAnimation { target: root; property: "offset"; to: 3 * root.ui; duration: 40 }
        NumberAnimation { target: root; property: "offset"; to: 0; duration: 30 }
    }

    Connections {
        function onFlash() {
            shake.restart();
        }

        target: Auth
    }
}
