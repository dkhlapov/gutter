import QtQuick
import QtQuick.Layouts
import qs.services
import qs.theme
import qs.components
import "../../../lib/format.js" as Format

// Download and upload speed on top, their history below. Uses the NetworkUsage service (the caller holds
// the ServiceRef that keeps it ticking).
CaptionBox {
    id: root

    tabs: [
        {
            text: "Network",
            accent: "navy"
        }
    ]
    currentTab: 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                implicitWidth: 12
                implicitHeight: 12
                color: Theme.accent.teal
                border.color: Theme.ink
                border.width: 2
            }

            InkIcon {
                icon: ""
                size: 14
            }

            InkText {
                text: `${Format.bytes(NetworkUsage.downloadSpeed)}/s`
                font.pixelSize: Theme.textMin
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                implicitWidth: 12
                implicitHeight: 12
                color: Theme.accent.magenta
                border.color: Theme.ink
                border.width: 2
            }

            InkIcon {
                icon: ""
                size: 14
            }

            InkText {
                text: `${Format.bytes(NetworkUsage.uploadSpeed)}/s`
                font.pixelSize: Theme.textMin
            }
        }

        // Takes the free height (rule 5). Scaled to the largest recent speed, 1 KiB/s at least.
        Sparkline {
            id: sparkline

            property real targetMax: Math.max(1024, ...NetworkUsage.downloadBuffer, ...NetworkUsage.uploadBuffer)

            Layout.fillWidth: true
            Layout.fillHeight: true
            line1: NetworkUsage.downloadBuffer
            line2: NetworkUsage.uploadBuffer
            historyLength: NetworkUsage.historyLength
            interval: NetworkUsage.sampleInterval
            maxValue: targetMax

            Behavior on maxValue {
                Anim {}
            }

            // Sampling starts when this tab opens; a line needs two samples.
            InkText {
                anchors.centerIn: parent
                visible: NetworkUsage.downloadBuffer.length < 2
                text: "Collecting data..."
                color: Theme.textMuted
            }
        }
    }
}
