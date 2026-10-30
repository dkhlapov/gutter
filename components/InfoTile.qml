import QtQuick
import QtQuick.Layouts
import qs.theme

// Label and glyph on one line (rule 7), the value below; every line single and eliding (rule 3).
Rectangle {
    id: root

    property string label
    property string icon
    property string value
    property bool large: false
    property color tone: Theme.paper
    property color ink: Theme.text

    Layout.fillWidth: true
    Layout.fillHeight: true
    implicitWidth: 80
    implicitHeight: column.implicitHeight + (large ? 16 : 10) + 2 * Theme.inkWidth
    color: tone
    border.color: Theme.ink
    border.width: Theme.inkWidth

    Column {
        id: column

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: (root.large ? 14 : 8) + Theme.inkWidth
        anchors.rightMargin: (root.large ? 14 : 8) + Theme.inkWidth
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.large ? 5 : 2

        Item {
            width: parent.width
            height: labelText.implicitHeight

            InkText {
                id: labelText

                anchors.left: parent.left
                anchors.right: glyph.visible ? glyph.left : parent.right
                anchors.rightMargin: glyph.visible ? 4 : 0
                text: root.label
                font.pixelSize: Theme.textMin
                elide: Text.ElideRight
                color: Theme.mutedOn(root.ink, root.tone)
            }

            // Same font as the label, so the glyph sits on the label's baseline.
            InkIcon {
                id: glyph

                // The label wins over the glyph in a narrow tile.
                visible: root.icon !== "" && labelText.implicitWidth + width + 4 <= column.width

                anchors.right: parent.right
                anchors.baseline: labelText.baseline
                icon: root.icon
                size: 16
                color: root.ink
            }
        }

        InkText {
            width: parent.width
            text: root.value
            font.pixelSize: root.large ? 18 : 14
            font.bold: true
            elide: Text.ElideRight
            color: root.ink
        }
    }
}
