import QtQuick
import qs.theme

// A read-only level: paper track, accent fill, ink outline. (InkSlider is for dragging; this has no handle.)
Rectangle {
    id: root

    property real value // 0..1
    property string accent: "teal"
    readonly property real clamped: Math.max(0, Math.min(1, value))

    implicitHeight: 14
    implicitWidth: 80
    color: Theme.paper
    border.color: Theme.ink
    border.width: Theme.inkWidth

    Rectangle {
        x: Theme.inkWidth
        y: Theme.inkWidth
        width: root.clamped * (parent.width - 2 * Theme.inkWidth)
        height: parent.height - 2 * Theme.inkWidth
        color: Theme.accent[root.accent]

        Behavior on width {
            Anim {}
        }
    }
}
