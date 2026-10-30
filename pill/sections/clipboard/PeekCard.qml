import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components
import "../../../lib/clipboard.js" as ClipLib

// The selected item large, with Copy, pin and delete. Text is cut at what fits; a link, colour or
// image gets its own treatment. The tab names the kind.
CaptionBox {
    id: root

    readonly property var item: Clipboard.selected
    readonly property string kind: item ? ClipLib.type(item) : "text"
    readonly property var labels: ({
            text: "Text",
            link: "Link",
            colour: "Colour",
            image: "Image"
        })
    readonly property var accents: ({
            text: "navy",
            link: "teal",
            colour: "pink",
            image: "coral"
        })

    tabs: [
        {
            text: labels[kind],
            accent: accents[kind]
        }
    ]
    currentTab: 0
    visible: item !== null

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.gap

        InkText {
            Layout.fillWidth: true
            text: root.item ? `${ClipLib.meta(root.item)} · ${ClipLib.age(root.item.t, Clipboard.now)}` : ""
            elide: Text.ElideRight
            color: Theme.textMuted
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.paper
            border.color: Theme.ink
            border.width: Theme.inkWidth
            clip: true

            Image {
                anchors.fill: parent
                anchors.margins: Theme.inkWidth + 5
                visible: root.kind === "image"
                source: root.kind === "image" ? "file://" + root.item.path : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            Column {
                anchors.centerIn: parent
                visible: root.kind === "colour"
                spacing: Theme.pad

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 84
                    height: 84
                    color: root.kind === "colour" ? ClipLib.colour(root.item) : "transparent"
                    border.color: Theme.ink
                    border.width: Theme.inkWidth
                }

                InkText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.kind === "colour" ? ClipLib.colour(root.item).toUpperCase() : ""
                    font.pixelSize: 18
                    font.bold: true
                }
            }

            // Short copies are set large and centred so the card never looks empty; long ones fill it
            // top-down, cut at whole lines with an ellipsis.
            InkText {
                readonly property int length: text.length

                anchors.fill: parent
                anchors.margins: Theme.inkWidth + 8
                visible: root.kind === "text" || root.kind === "link"
                text: root.item && root.kind !== "image" ? root.item.text.trim().slice(0, 1200) : ""
                font.pixelSize: length <= 40 ? 24 : length <= 120 ? 18 : 13
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                textFormat: Text.PlainText
                verticalAlignment: length <= 120 && text.indexOf("\n") === -1 ? Text.AlignVCenter : Text.AlignTop
                horizontalAlignment: length <= 40 && text.indexOf("\n") === -1 ? Text.AlignHCenter : Text.AlignLeft
                maximumLineCount: Math.max(1, Math.floor(height / (font.pixelSize * 1.4)))
            }
        }

        RowLayout {
            Layout.fillWidth: true
            // Room on the right and below for the buttons' hard shadows.
            Layout.rightMargin: Theme.shadowOffset
            Layout.bottomMargin: Theme.shadowOffset
            spacing: Theme.gap

            InkButton {
                Layout.fillWidth: true
                text: "Copy"
                icon: ""
                accent: "lime"
                onClicked: {
                    Clipboard.copy(root.item);
                    PillControl.close();
                }
            }

            InkButton {
                icon: ""
                checked: root.item?.pinned ?? false
                onClicked: Clipboard.togglePin(root.item.id)
            }

            InkButton {
                icon: ""
                onClicked: Clipboard.remove(root.item.id)
            }
        }
    }
}
