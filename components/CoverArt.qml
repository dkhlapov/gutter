import QtQuick
import qs.theme

// Album art inside an ink outline. While there is no image, a music note on the pink accent.
Item {
    id: root

    property string source

    clip: true

    Rectangle {
        anchors.fill: parent
        color: Theme.accent.pink
    }

    InkIcon {
        anchors.centerIn: parent
        visible: image.status !== Image.Ready
        icon: ""
        size: Math.max(10, Math.min(48, Math.round(Math.min(root.width, root.height) / 2)))
        color: Theme.on.pink
    }

    Image {
        id: image

        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        asynchronous: true
        cache: true
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: Theme.ink
        border.width: Theme.inkWidth
    }
}
