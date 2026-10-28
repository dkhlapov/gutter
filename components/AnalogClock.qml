pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import "../lib/calendar.js" as Cal

// Square ink-outlined face with 12 tick marks and hour / minute / second hands.
Item {
    id: root

    property date date
    property color ink: Theme.text
    property color face: Theme.paper
    property color accent: Theme.accent.coral
    readonly property var angles: Cal.handAngles(date.getHours(), date.getMinutes(), date.getSeconds())
    readonly property real r: width / 2

    implicitWidth: 112
    implicitHeight: 112

    Rectangle {
        anchors.fill: parent
        color: root.face
        border.color: Theme.ink
        border.width: Theme.inkWidth
    }

    Repeater {
        model: 12

        delegate: Rectangle {
            required property int index
            readonly property real a: index * Math.PI / 6

            width: index % 3 === 0 ? 6 : 4
            height: width
            color: root.ink
            x: root.r + (root.r - 17) * Math.sin(a) - width / 2
            y: root.r - (root.r - 17) * Math.cos(a) - height / 2
        }
    }

    component Hand: Rectangle {
        property real angle
        property real length

        x: root.r - width / 2
        y: root.r - length
        height: length
        transformOrigin: Item.Bottom
        rotation: angle
        antialiasing: true
    }

    Hand {
        width: 5
        length: root.r * 0.45
        angle: root.angles.hour
        color: root.ink
    }

    Hand {
        width: 4
        length: root.r * 0.66
        angle: root.angles.minute
        color: root.ink
    }

    Hand {
        width: 2
        length: root.r * 0.72
        angle: root.angles.second
        color: root.accent
    }

    Rectangle {
        anchors.centerIn: parent
        width: 10
        height: 10
        color: root.accent
        border.color: Theme.ink
        border.width: 2
    }
}
