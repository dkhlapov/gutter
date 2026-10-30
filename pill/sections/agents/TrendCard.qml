pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.components
import "../../../lib/agentUsage.js" as U

// API value per hour (today) or per day (7 / 30 days) as bars; empty slots show as dashes.
CaptionBox {
    id: root

    property string period: "today"
    property var values: []
    property real total: 0
    readonly property real peak: Math.max(0.0001, ...values)
    readonly property var labels: U.trendLabels(period)

    tabs: [
        {
            text: "Trend",
            accent: "magenta"
        }
    ]
    currentTab: 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: 6

        InkText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: `${U.periodLabel(root.period)} · ${U.money(root.total)}`
            color: Theme.textMuted
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.values.length > 24 ? 2 : 3

            Repeater {
                model: root.values

                delegate: Item {
                    id: slot

                    required property real modelData

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // A flat accent bar standing on the baseline; an empty slot is a short dash of the muted role.
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: slot.modelData > 0 ? Math.max(6, slot.height * slot.modelData / root.peak) : 3
                        color: slot.modelData > 0 ? Theme.accent.magenta : Theme.role.muted

                        Behavior on height {
                            Anim {}
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: root.labels

                delegate: InkText {
                    required property string modelData
                    required property int index

                    Layout.fillWidth: true
                    horizontalAlignment: index === 0 ? Text.AlignLeft : index === 2 ? Text.AlignRight : Text.AlignHCenter
                    text: modelData
                    color: Theme.textMuted
                }
            }
        }
    }
}
