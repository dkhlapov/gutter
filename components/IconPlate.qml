import QtQuick
import qs.theme

// A small square badge: a Nerd Font glyph on an accent fill with an ink outline, or, when `source` loads,
// that picture on paper. `glyph` is the glyph item, for a caller that turns or rings it.
Item {
    id: root

    property string accent: "teal"
    property string icon
    property string source
    property real size: 26
    readonly property alias glyph: glyphItem
    readonly property bool hasImage: image.status === Image.Ready

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        color: root.hasImage ? Theme.paper : Theme.accent[root.accent]
        border.color: Theme.ink
        border.width: Theme.inkWidth
    }

    Image {
        id: image

        anchors.fill: parent
        anchors.margins: Theme.inkWidth + 1
        source: root.source
        sourceSize: Qt.size(48, 48)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }

    InkIcon {
        id: glyphItem

        anchors.centerIn: parent
        visible: !root.hasImage
        icon: root.icon
        size: Math.round(root.size * 0.6)
        color: Theme.on[root.accent]
    }
}
