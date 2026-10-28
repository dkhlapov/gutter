import QtQuick
import QtQuick.Layouts
import qs.components
import qs.theme

// What the shelf is for, shown while it is empty.
RowLayout {
    spacing: Theme.pad

    Repeater {
        model: [
            {
                icon: "\u{f01da}",
                title: "Drag in",
                text: "Drag files from your file manager or a browser onto the pill. It opens by itself.",
                accent: "teal"
            },
            {
                icon: "\u{f0193}",
                title: "Keep",
                text: "They stay on the shelf across restarts. Nothing is copied or moved.",
                accent: "sun"
            },
            {
                icon: "\u{f0207}",
                title: "Drag out",
                text: "Drag a tile into any app to attach, upload or paste it. Click a tile to open it.",
                accent: "pink"
            }
        ]

        delegate: InkBox {
            id: hint

            required property var modelData

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1

            // The wrapper fills the box (which the box counts as 0), so each hint starts at the same height.
            Item {
                anchors.fill: parent

                Column {
                    anchors.top: parent.top
                    anchors.topMargin: 28
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 2 * Theme.pad
                    spacing: Theme.gap

                    InkBox {
                        anchors.horizontalCenter: parent.horizontalCenter
                        fill: Theme.accent[hint.modelData.accent]
                        implicitWidth: 64
                        implicitHeight: 64

                        InkIcon {
                            anchors.centerIn: parent
                            icon: hint.modelData.icon
                            size: 30
                            color: Theme.on[hint.modelData.accent]
                        }
                    }

                    InkText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: hint.modelData.title
                        font.pixelSize: 15
                        font.bold: true
                    }

                    InkText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: hint.modelData.text
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        maximumLineCount: 4
                        opacity: 0.75
                    }
                }
            }
        }
    }
}
