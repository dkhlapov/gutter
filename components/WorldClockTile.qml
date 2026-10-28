import QtQuick
import QtQuick.Layouts
import qs.theme

// City and offset on the left, time on the right (rule 3: everything elides).
Rectangle {
    id: root

    property string label
    property string time
    property string offset
    property color tone: Theme.paper
    property color ink: Theme.text

    Layout.fillWidth: true
    Layout.fillHeight: true
    implicitHeight: 44
    color: tone
    border.color: Theme.ink
    border.width: Theme.inkWidth

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.pad
        anchors.rightMargin: Theme.pad
        spacing: 6

        ColumnLayout {
            Layout.fillWidth: true
            spacing: -1

            InkText {
                Layout.fillWidth: true
                text: root.label
                font.pixelSize: 12
                font.bold: true
                elide: Text.ElideRight
                color: root.ink
            }

            InkText {
                Layout.fillWidth: true
                visible: root.offset !== ""
                text: root.offset
                font.pixelSize: 11
                elide: Text.ElideRight
                color: root.ink
                opacity: 0.7
            }
        }

        InkText {
            text: root.time
            font.pixelSize: 17
            font.bold: true
            color: root.ink
        }
    }
}
