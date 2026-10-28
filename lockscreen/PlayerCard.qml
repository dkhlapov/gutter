import QtQuick
import qs.components
import qs.services
import qs.theme

// What is playing, on a small card: the cover, the title and the artist (one line each), and previous, play or
// pause, next. A supporting piece beside the clock, so it is small. Hidden while no music player is active. A
// click on a button does the player's action and takes no keyboard focus: the password field keeps the keys.
// It reads the Media singleton only (no window), so it works on the lock surface.
InkBox {
    id: root

    property real ui: 1
    // Whether the owner wants it at all (the layout shows one of two copies).
    property bool shown: true
    readonly property bool has: Media.active !== null

    visible: shown && has

    readonly property real coverSize: Math.round(46 * ui)
    readonly property real button: Math.round(22 * ui)
    readonly property real pad: Math.round(6 * ui)

    Item {
        implicitWidth: Math.round(280 * root.ui)
        implicitHeight: root.coverSize + 2 * root.pad

        CoverArt {
            id: cover

            x: root.pad
            anchors.verticalCenter: parent.verticalCenter
            width: root.coverSize
            height: root.coverSize
            source: Media.artUrl
        }

        Column {
            anchors.left: cover.right
            anchors.leftMargin: root.pad + 2
            anchors.right: transport.left
            anchors.rightMargin: root.pad
            anchors.verticalCenter: parent.verticalCenter

            InkText {
                width: parent.width
                text: Media.title !== "" ? Media.title : "Unknown"
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.bold: true
                font.pixelSize: Math.round(13 * root.ui)
            }

            InkText {
                width: parent.width
                visible: Media.artist !== ""
                text: Media.artist
                textFormat: Text.PlainText
                elide: Text.ElideRight
                opacity: 0.7
                font.pixelSize: Math.round(12 * root.ui)
            }
        }

        Row {
            id: transport

            anchors.right: parent.right
            anchors.rightMargin: root.pad
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(4 * root.ui)

            InkButton {
                width: root.button
                height: root.button
                icon: ""
                iconSize: Math.round(10 * root.ui)
                onClicked: Media.previous()
            }

            InkButton {
                width: root.button
                height: root.button
                icon: Media.playing ? "" : ""
                iconSize: Math.round(10 * root.ui)
                accent: "sun"
                onClicked: Media.togglePlaying()
            }

            InkButton {
                width: root.button
                height: root.button
                icon: ""
                iconSize: Math.round(10 * root.ui)
                onClicked: Media.next()
            }
        }
    }
}
