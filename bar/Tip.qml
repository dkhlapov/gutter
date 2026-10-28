import QtQuick
import qs.theme
import qs.components

// A hover tooltip: a small caption box with an optional title tab over a line or two of text.
CaptionBox {
    id: root

    property string title
    property string body

    tabs: title !== "" ? [
        {
            text: root.title,
            accent: "teal"
        }
    ] : []
    currentTab: 0
    keyline: true
    width: implicitWidth
    height: implicitHeight

    Item {
        // Wide enough for the title tab; a long body wraps at 320 px.
        implicitWidth: text.width + 2 * Theme.pad
        implicitHeight: text.implicitHeight + Theme.pad

        InkText {
            id: text

            anchors.centerIn: parent
            width: Math.min(implicitWidth, 320)
            text: root.body
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
    }
}
