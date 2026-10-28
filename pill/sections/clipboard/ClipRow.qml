import QtQuick
import qs.theme
import qs.services
import qs.components
import "../../../lib/clipboard.js" as ClipLib

// One history card: a badge (icon, colour swatch or thumbnail), the text in two lines, and age / size
// below. Pin and delete appear on hover (a pin stays visible). The card under the pointer is the selected
// one and turns sun-yellow.
Item {
    id: root

    required property var modelData
    readonly property string kind: ClipLib.type(modelData)
    readonly property bool hovered: area.containsMouse || pinArea.containsMouse || delArea.containsMouse
    readonly property bool selected: Clipboard.selected?.id === modelData.id
    readonly property string accent: kind === "link" ? "teal" : "navy"
    readonly property color ink: selected ? Theme.on.sun : Theme.text

    // Room on the right and below for the card's hard shadow.
    InkBox {
        id: card

        anchors.fill: parent
        anchors.margins: 3
        anchors.rightMargin: 3 + Theme.shadowOffset
        anchors.bottomMargin: 3 + Theme.shadowOffset
        fill: root.selected ? Theme.accent.sun : Theme.paper

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: {
                if (containsMouse)
                    Clipboard.selectedId = root.modelData.id;
            }
            onClicked: {
                Clipboard.copy(root.modelData);
                PillControl.close();
            }
        }

        Rectangle {
            id: badge

            x: Theme.pad
            y: (card.height - height) / 2 - Theme.inkWidth
            width: 38
            height: 38
            color: root.kind === "colour" ? ClipLib.colour(root.modelData) : Theme.accent[root.accent]
            border.color: Theme.ink
            border.width: Theme.inkWidth
            clip: true

            InkIcon {
                anchors.centerIn: parent
                visible: root.kind === "text" || root.kind === "link"
                icon: root.kind === "link" ? "" : (root.modelData.text ?? "").indexOf("\n") !== -1 ? "" : ""
                size: 16
                color: Theme.on[root.accent]
            }

            Image {
                anchors.fill: parent
                anchors.margins: Theme.inkWidth
                visible: root.kind === "image"
                source: root.kind === "image" ? "file://" + root.modelData.path : ""
                sourceSize.width: 80
                sourceSize.height: 80
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }

        Column {
            x: badge.x + badge.width + Theme.gap
            y: (card.height - height) / 2 - Theme.inkWidth
            width: actions.x - x - 6
            spacing: 2

            InkText {
                width: parent.width
                text: root.kind === "image" ? "Image" : ClipLib.preview(root.modelData.text, 120)
                font.pixelSize: 12
                font.bold: true
                maximumLineCount: 2
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                color: root.ink
            }

            InkText {
                width: parent.width
                text: `${ClipLib.meta(root.modelData)} · ${ClipLib.age(root.modelData.t, Clipboard.now)}`
                font.pixelSize: 11
                elide: Text.ElideRight
                color: root.ink
                opacity: 0.75
            }
        }

        // The buttons are faded, not hidden, so they always take their room and the text keeps its width.
        Row {
            id: actions

            x: card.width - 2 * Theme.inkWidth - width - 8
            y: (card.height - height) / 2 - Theme.inkWidth
            spacing: 8

            InkIcon {
                id: pin

                icon: root.modelData.pinned ? "" : ""
                size: 15
                color: root.ink
                opacity: root.modelData.pinned ? 1 : root.hovered ? 0.5 : 0
                rotation: root.modelData.pinned ? 0 : 45

                MouseArea {
                    id: pinArea

                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Clipboard.togglePin(root.modelData.id)
                }
            }

            InkIcon {
                id: del

                icon: ""
                size: 15
                color: root.ink
                opacity: root.hovered ? 1 : 0

                MouseArea {
                    id: delArea

                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Clipboard.remove(root.modelData.id)
                }
            }
        }
    }
}
