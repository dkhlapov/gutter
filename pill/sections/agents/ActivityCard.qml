pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.components
import "../../../lib/agentUsage.js" as U

// 13 weeks of API value as a heatmap (a column per week, Monday on top; today drawn larger) and its totals.
// The levels are four named accents from cool to hot over paper, not tints of one colour.
CaptionBox {
    id: root

    property var heat: null
    readonly property var days: heat?.days ?? []
    readonly property real peak: Math.max(0, ...days)
    readonly property real cellSize: 12
    // A hairline, not the ink lines' width: on a 12 px square a thick outline hides the level's colour.
    readonly property real cellBorder: 1
    // How far today grows past its cell; the grid gap is two more, so it never covers a neighbour.
    readonly property real todayGrowth: 2
    readonly property var levels: [Theme.paper, Theme.accent.teal, Theme.accent.lime, Theme.accent.sun, Theme.accent.coral]

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
        spacing: 14

        Grid {
            id: grid

            Layout.alignment: Qt.AlignVCenter
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

        // As tall as the grid beside it: the first stat level with its top row, the last with its bottom one.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: grid.height
            Layout.alignment: Qt.AlignVCenter
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
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        opacity: 0.7
                    }
                }
            }
        }
    }
}
