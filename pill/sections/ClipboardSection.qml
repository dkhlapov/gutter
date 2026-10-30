pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components
import "clipboard"
import "../../lib/clipboard.js" as ClipLib

// Clipboard history: the hovered (else newest) item large on the left with copy / pin / delete, and
// every item as a card in a two-column grid on the right. Clicking a card copies it and closes the panel.
Item {
    id: root

    property string query: ""
    readonly property var shown: ClipLib.filter(Clipboard.items, query)

    EmptyState {
        anchors.centerIn: parent
        visible: Clipboard.missing || (Clipboard.items.length === 0 && Clipboard.loaded)
        icon: Clipboard.missing ? "" : ""
        text: Clipboard.missing ? "Needs wl-clipboard (wl-paste)" : "Copy something and it shows up here"
    }

    RowLayout {
        anchors.fill: parent
        visible: Clipboard.items.length > 0
        spacing: Theme.pad

        PeekCard {
            Layout.preferredWidth: 320
            Layout.fillWidth: false
            Layout.fillHeight: true
        }

        CaptionBox {
            Layout.fillWidth: true
            Layout.fillHeight: true
            tabs: [
                {
                    text: "History",
                    accent: "lime"
                }
            ]
            currentTab: 0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.pad
                spacing: Theme.pad

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gap

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Theme.pillHeight
                        color: Theme.paper
                        border.color: Theme.ink
                        border.width: Theme.inkWidth

                        InkIcon {
                            id: searchIcon

                            anchors.left: parent.left
                            anchors.leftMargin: Theme.pad
                            anchors.verticalCenter: parent.verticalCenter
                            icon: ""
                            size: 14
                        }

                        TextInput {
                            id: search

                            anchors.left: searchIcon.right
                            anchors.leftMargin: Theme.gap
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.pad
                            anchors.verticalCenter: parent.verticalCenter
                            clip: true
                            color: Theme.text
                            selectionColor: Theme.accent.sun
                            selectedTextColor: Theme.on.sun
                            font.family: Theme.font
                            font.pixelSize: 13
                            onTextChanged: root.query = text
                        }

                        InkText {
                            anchors.left: search.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: search.text === ""
                            text: `Search ${Clipboard.items.length} items…`
                            color: Theme.textMuted
                        }

                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            cursorShape: Qt.IBeamCursor
                            onClicked: search.forceActiveFocus()
                        }
                    }

                    InkButton {
                        // Room on the right for the button's hard shadow.
                        Layout.rightMargin: Theme.shadowOffset
                        text: "Clear"
                        icon: ""
                        onClicked: Clipboard.clear()
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    GridView {
                        id: grid

                        anchors.fill: parent
                        anchors.rightMargin: scroll.reserve
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        cellWidth: Math.floor(width / 2)
                        cellHeight: 76
                        model: root.shown

                        delegate: ClipRow {
                            width: grid.cellWidth
                            height: grid.cellHeight
                        }
                    }

                    InkScrollBar {
                        id: scroll

                        anchors.top: grid.top
                        anchors.bottom: grid.bottom
                        anchors.left: grid.right
                        anchors.leftMargin: gap
                        target: grid
                    }

                    EmptyState {
                        anchors.centerIn: parent
                        visible: root.shown.length === 0
                        icon: ""
                        text: "Nothing matches"
                    }
                }
            }
        }
    }
}
