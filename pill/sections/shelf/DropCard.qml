import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components

// Count of held files with their size. While a drag is over the pill the card turns sun-yellow.
CaptionBox {
    id: root

    readonly property bool hot: Shelf.dropping
    readonly property bool empty: Shelf.items.length === 0
    readonly property color ink: hot ? Theme.on.sun : Theme.text

    tabs: [
        {
            text: "File shelf",
            accent: "coral"
        }
    ]
    currentTab: 0
    fill: hot ? Theme.accent.sun : Theme.paper

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.gap

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            InkBox {
                id: badge

                anchors.centerIn: parent
                fill: Theme.accent.coral
                // Its content is centred, which the box counts as 0, so the size is stated.
                implicitWidth: 124
                implicitHeight: 124

                // The glyph of an empty shelf; a count once something is held.
                InkIcon {
                    anchors.centerIn: parent
                    visible: root.empty || root.hot
                    icon: root.hot ? "\u{f01da}" : "\u{f0a4d}"
                    size: 52
                    color: Theme.on.coral
                }

                InkText {
                    anchors.centerIn: parent
                    visible: !root.empty && !root.hot
                    text: Shelf.items.length
                    font.pixelSize: 52
                    font.bold: true
                    color: Theme.on.coral
                }
            }
        }

        InkText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.hot ? "Release to add" : root.empty ? "Drop files on the pill" : Shelf.summary.text
            font.pixelSize: 14
            font.bold: true
            elide: Text.ElideRight
            color: root.ink
        }

        InkText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.hot ? "They are kept here, not copied" : root.empty ? "Held until you drag them out" : "Drag a tile out to use it"
            font.pixelSize: 12
            elide: Text.ElideRight
            color: root.ink
            opacity: 0.75
        }

        InkButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Theme.shadowOffset
            visible: !root.empty
            text: "Clear shelf"
            icon: "\u{f05e9}"
            onClicked: Shelf.clear()
        }
    }
}
