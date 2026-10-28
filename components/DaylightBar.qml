import QtQuick
import QtQuick.Layouts
import qs.theme

// Midnight-to-midnight track: night navy, a sun segment between sunrise and sunset, a square marker for now.
// Below: sunrise glyph and time, caption, sunset time and glyph. Without sun data only the track and the marker are drawn.
ColumnLayout {
    id: root

    property var sun
    property string riseText
    property string setText
    property color ink: Theme.text
    readonly property real trackHeight: 14
    readonly property real markerSize: 20
    readonly property real rowHeight: 22
    readonly property bool hasSun: (sun?.rise ?? null) !== null && (sun?.set ?? null) !== null

    spacing: Theme.gap

    Item {
        Layout.fillWidth: true
        implicitHeight: root.rowHeight

        Rectangle {
            id: track

            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: root.trackHeight
            color: Theme.accent.navy
            border.color: Theme.ink
            border.width: Theme.inkWidth

            Rectangle {
                visible: root.hasSun
                x: Theme.inkWidth + (root.sun?.rise ?? 0) * (track.width - 2 * Theme.inkWidth)
                y: Theme.inkWidth
                width: ((root.sun?.set ?? 0) - (root.sun?.rise ?? 0)) * (track.width - 2 * Theme.inkWidth)
                height: parent.height - 2 * Theme.inkWidth
                color: Theme.accent.sun
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(track.width - width, (root.sun?.now ?? 0) * track.width - width / 2))
            width: root.markerSize
            height: root.markerSize
            color: Theme.paper
            border.color: Theme.ink
            border.width: Theme.inkWidth
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.hasSun
        spacing: 4

        InkIcon {
            icon: ""
            color: root.ink
        }

        InkText {
            text: root.riseText
            font.pixelSize: 12
            font.bold: true
            color: root.ink
        }

        InkText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.sun?.caption ?? ""
            font.pixelSize: 12
            elide: Text.ElideRight
            color: root.ink
            opacity: 0.8
        }

        InkText {
            text: root.setText
            font.pixelSize: 12
            font.bold: true
            color: root.ink
        }

        InkIcon {
            icon: ""
            color: root.ink
        }
    }
}
