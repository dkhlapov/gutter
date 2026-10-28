import QtQuick
import qs.components
import qs.services
import qs.theme
import "../lib/lock.js" as LockLib

// What the last password check said, in a speech bubble under the field: coral for a wrong password or an error,
// sun (the nearest to amber) for a lockout, and "…" while a check runs. It overlays the layout: its owner places it
// under the field, and it takes no room in the column.
SpeechBubble {
    id: root

    property real ui: 1

    readonly property bool checking: Auth.checking
    readonly property string kind: Auth.stateKind
    readonly property string message: checking ? "…" : Auth.stateText
    readonly property string accent: LockLib.stateAccent(kind, checking)

    visible: message !== ""
    // Shakes with the field on a failed check (a transform: its owner places it by x and y).
    transform: Translate {
        x: shake.offset
    }
    tailX: 0.5
    tailHeight: Math.round(12 * ui)
    tailHalfBase: Math.round(7 * ui)
    padX: Math.round(14 * ui)
    padY: Math.round(7 * ui)
    fill: accent === "" ? Theme.paper : Theme.accent[accent]

    Shake {
        id: shake

        ui: root.ui
    }

    InkText {
        text: root.message
        color: root.accent === "" ? Theme.text : Theme.on[root.accent]
        font.bold: true
        font.pixelSize: Math.round(14 * root.ui)
        font.letterSpacing: Math.round(root.ui)
        font.capitalization: Font.AllUppercase
    }
}
