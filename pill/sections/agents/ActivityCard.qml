pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.components
import "../../../lib/agentUsage.js" as U

// 13 weeks of API value as a heatmap (a column per week, Monday on top; today drawn larger) and its totals.
// The levels are four strengths of the section's own colour over paper (none for a quiet day), so colour carries
// "more or less" and nothing else; the legend under the grid says so. Hue is left to state: no red, no green.
CaptionBox {
    id: root

    property var heat: null
    readonly property var days: heat?.days ?? []
    readonly property real peak: Math.max(0, ...days)
    readonly property real cellSize: 11
    // A hairline, not the ink lines' width: on a 12 px square a thick outline hides the level's colour.
    readonly property real cellBorder: 1
    // How far today grows past its cell; the grid gap is two more, so it never covers a neighbour.
    readonly property real todayGrowth: 2
    // The legend's swatches are a little smaller than the grid's cells, so grid and legend fit the card.
    readonly property real swatchSize: 9
    readonly property real legendRoom: 6
    readonly property var levels: [0, 0.3, 0.55, 0.8, 1].map(a => Qt.tint(Theme.paper, Qt.alpha(Theme.accent.magenta, a)))

    tabs: [
        {
            text: `Activity · 13 weeks · ${U.money(root.heat?.total ?? 0)}`,
            accent: "magenta"
        }
    ]
    currentTab: 0

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad
        // The legend under the grid takes the rest of the card's height.
        anchors.topMargin: root.legendRoom
        anchors.bottomMargin: root.legendRoom
        spacing: 14

        ColumnLayout {
            id: gridColumn

            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            Grid {
                id: grid

                rows: 7
                flow: Grid.TopToBottom
                spacing: root.todayGrowth + 2

                Repeater {
                    model: root.days.length

                    delegate: Item {
                        id: cell

                        required property int index
                        readonly property bool today: index === (root.heat?.today ?? -1)

                        width: root.cellSize
                        height: root.cellSize
                        z: today ? 1 : 0

                        // Days still to come are left blank, but keep their place in the grid. Today grows into the
                        // gap around it, so it stands out without a thicker border eating its colour.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: cell.today ? -root.todayGrowth : 0
                            visible: cell.index <= (root.heat?.today ?? 0)
                            color: root.levels[U.heatLevel(root.days[cell.index], root.peak)]
                            border.color: Theme.ink
                            border.width: root.cellBorder
                        }
                    }
                }
            }

            // What the colours mean: the same four strengths, from a quiet day to the busiest one.
            Row {
                id: legend

                Layout.alignment: Qt.AlignRight
                spacing: 4

                InkText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Less"
                    color: Theme.textMuted
                }

                Repeater {
                    model: root.levels

                    delegate: Rectangle {
                        required property color modelData

                        anchors.verticalCenter: parent.verticalCenter
                        width: root.swatchSize
                        height: root.swatchSize
                        color: modelData
                        border.color: Theme.ink
                        border.width: root.cellBorder
                    }
                }

                InkText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "More"
                    color: Theme.textMuted
                }
            }
        }

        // As tall as the grid beside it: the first stat level with its top row, the last with its bottom one.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: grid.height
            Layout.alignment: Qt.AlignVCenter
            // Centred on the grid, not on the grid and the legend under it.
            Layout.bottomMargin: legend.height + gridColumn.spacing
            spacing: 0

            Repeater {
                model: [
                    {
                        label: "Active days",
                        value: String(root.heat?.activeDays ?? 0)
                    },
                    {
                        label: "In a row",
                        value: String(root.heat?.streak ?? 0)
                    },
                    {
                        label: "Busiest day",
                        value: root.heat?.busiest ? root.heat.busiest.label : "—"
                    }
                ]

                delegate: ColumnLayout {
                    id: stat

                    required property var modelData

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    InkText {
                        Layout.fillWidth: true
                        text: stat.modelData.value
                        horizontalAlignment: Text.AlignRight
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    InkText {
                        Layout.fillWidth: true
                        text: stat.modelData.label
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        color: Theme.textMuted
                    }
                }
            }
        }
    }
}
