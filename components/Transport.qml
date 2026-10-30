import QtQuick
import qs.theme
import qs.services

// Previous / play-pause / next. The play button is the large one, in the sun accent.
Item {
    id: root

    property real buttonSize: Theme.pillHeight
    property real playSize: 46
    // Adds shuffle (first) and repeat (last) when the player supports them.
    property bool extended: false

    // The row of buttons; its centre is the centre of what is drawn (the buttons, without their hard shadow).
    readonly property alias group: row

    // The shadow falls right and down outside the buttons: room is kept below it, none beside it, so the group
    // is centred on whatever the transport is aligned to.
    implicitWidth: row.width
    implicitHeight: row.height + Theme.shadowOffset

    Row {
        id: row

        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 14

        InkButton {
            accessibleName: "Shuffle"
            anchors.verticalCenter: parent.verticalCenter
            visible: root.extended && Media.canShuffle
            height: root.buttonSize
            icon: ""
            checked: Media.shuffle
            checkable: true
            onClicked: Media.toggleShuffle()
        }

        InkButton {
            accessibleName: "Previous track"
            anchors.verticalCenter: parent.verticalCenter
            height: root.buttonSize
            icon: ""
            onClicked: Media.previous()
        }

        InkButton {
            accessibleName: Media.playing ? "Pause" : "Play"
            anchors.verticalCenter: parent.verticalCenter
            width: root.playSize * 1.4
            height: root.playSize
            icon: Media.playing ? "" : ""
            iconSize: root.playSize * 0.45
            accent: "sun"
            onClicked: Media.togglePlaying()
        }

        InkButton {
            accessibleName: "Next track"
            anchors.verticalCenter: parent.verticalCenter
            height: root.buttonSize
            icon: ""
            onClicked: Media.next()
        }

        InkButton {
            accessibleName: "Repeat"
            anchors.verticalCenter: parent.verticalCenter
            visible: root.extended && Media.canLoop
            height: root.buttonSize
            icon: Media.loopState === 1 ? "\u{f0458}" : ""
            checked: Media.loopState !== 0
            checkable: true
            onClicked: Media.cycleLoop()
        }
    }
}
