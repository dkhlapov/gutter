import QtQuick
import qs.theme

// Centred icon and message for missing data; `busy` spins the icon while loading.
Column {
    id: root

    property alias icon: glyph.icon
    property alias text: label.text
    property bool busy: false
    property color ink: Theme.text

    spacing: 6

    InkIcon {
        id: glyph

        anchors.horizontalCenter: parent.horizontalCenter
        size: 32
        color: root.ink

        RotationAnimator on rotation {
            running: root.busy && root.visible
            from: 0
            to: 360
            duration: 1200
            loops: Animation.Infinite
        }
    }

    InkText {
        id: label

        anchors.horizontalCenter: parent.horizontalCenter
        font.pixelSize: 14
        color: root.ink
    }
}
