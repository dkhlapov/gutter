import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.components

// A box tabbed with the device name: ring + model + temperature bar on the left, the usage shape on the right.
// `status` (not `state`, which Item already has): "" = normal, "missing" = no such device, "busy" = still detecting.
CaptionBox {
    id: root

    property string title
    property string model
    property string icon
    property string accent: "teal"
    property real usage
    property real temperature
    property string status: ""
    property string missingText

    tabs: [
        {
            text: root.title,
            accent: root.accent
        }
    ]
    currentTab: 0

    EmptyState {
        anchors.centerIn: parent
        visible: root.status !== ""
        icon: root.status === "busy" ? "" : root.icon
        busy: root.status === "busy"
        text: root.status === "busy" ? "Detecting…" : root.missingText
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad
        visible: root.status === ""
        spacing: 14

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Ring {
                    value: root.usage
                    accent: root.accent
                    icon: root.icon
                    implicitWidth: 64
                }

                InkText {
                    Layout.fillWidth: true
                    text: root.model
                    font.pixelSize: 13
                    font.bold: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                InkIcon {
                    icon: ""
                    size: 16
                }

                InkText {
                    text: root.temperature > 0 ? `${Math.round(root.temperature)} °C` : "— °C"
                    font.pixelSize: 13
                }

                LevelBar {
                    Layout.fillWidth: true
                    value: Math.min(1, root.temperature / 100)
                    accent: root.accent
                }
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            InkText {
                Layout.alignment: Qt.AlignHCenter
                text: "Usage"
                color: Theme.textMuted
            }

            UsageShape {
                value: root.usage
                accent: root.accent
            }
        }
    }
}
