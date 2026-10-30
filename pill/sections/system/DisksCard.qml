import QtQuick
import QtQuick.Layouts
import qs.services
import qs.theme
import qs.components
import "../../../lib/format.js" as Format

// One usage bar per mounted disk. Two disks fit; more scroll.
CaptionBox {
    id: root

    tabs: [
        {
            text: "Disks",
            accent: "pink"
        }
    ]
    currentTab: 0

    EmptyState {
        anchors.centerIn: parent
        visible: Storage.disks.length === 0
        icon: ""
        text: "No disks"
    }

    ListView {
        id: list

        anchors.fill: parent
        anchors.margins: Theme.pad
        anchors.rightMargin: Theme.pad + scroll.reserve
        visible: Storage.disks.length > 0
        clip: true
        spacing: 12
        boundsBehavior: Flickable.StopAtBounds
        model: Storage.disks

        delegate: ColumnLayout {
            id: disk

            required property var modelData

            width: ListView.view.width
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                InkIcon {
                    icon: ""
                    size: 15
                }

                InkText {
                    Layout.fillWidth: true
                    text: disk.modelData.mount
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                }

                InkText {
                    text: `${Format.kib(disk.modelData.used)} / ${Format.kib(disk.modelData.total)}`
                    color: Theme.textMuted
                }
            }

            LevelBar {
                Layout.fillWidth: true
                value: disk.modelData.perc
                accent: "pink"
            }
        }
    }

    InkScrollBar {
        id: scroll

        anchors.top: list.top
        anchors.bottom: list.bottom
        anchors.left: list.right
        anchors.leftMargin: gap
        target: list
    }
}
