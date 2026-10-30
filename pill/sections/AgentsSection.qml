pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components
import "agents"
import "../../lib/agentUsage.js" as U

// Claude Code usage, like Vorssaint's AI Agents page, in three equal columns of two equal cards: plan limits and
// what is running now on the left,
// the API value of the period with its trend in the middle, models / projects and 13 weeks of activity
// on the right. The period tabs (today, 7 days, 30 days) drive the middle and the breakdown.
Item {
    id: root

    readonly property var periods: ["today", "week", "month"]
    property string period: "today"
    property bool showProjects: true
    readonly property var usage: AgentUsage.data
    readonly property var p: usage?.periods?.[period] ?? null
    // Both cards of a column ask for the same half of the height (the columns' spacing is Theme.pad): the layout
    // shares spare room in proportion to what the items ask for, so unequal asks would give one card most of it.
    readonly property real cardHeight: Math.floor((height - Theme.pad) / 2)

    EmptyState {
        anchors.centerIn: parent
        visible: root.usage === null
        icon: AgentUsage.failed ? "\u{f0028}" : "\u{f0772}"
        // An endless linear turn of the glyph while the usage script runs.
        busy: !AgentUsage.failed
        text: AgentUsage.failed ? "Could not read Claude Code usage (needs python3)" : "Reading Claude Code usage…"
    }

    RowLayout {
        anchors.fill: parent
        visible: root.usage !== null
        spacing: Theme.pad

        // Limits and Now.
        ColumnLayout {
            id: leftColumn

            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.pad

            LimitsCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: root.cardHeight
            }

            NowCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: root.cardHeight
                sessions: root.usage?.sessions ?? ({})
            }
        }

        // Spending hero and trend.
        ColumnLayout {
            id: middleColumn

            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.pad

            // The three tabs are the period (today, 7 days, 30 days).
            CaptionBox {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: root.cardHeight
                tabs: root.periods.map(name => ({
                            text: U.periodLabel(name),
                            accent: "magenta"
                        }))
                currentTab: root.periods.indexOf(root.period)
                onTabClicked: index => root.period = root.periods[index]

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.pad
                    spacing: 0

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        InkText {
                            Layout.fillWidth: true
                            text: U.money(root.p?.cost ?? 0) + ((root.usage?.unknown?.length ?? 0) > 0 ? "+" : "")
                            font.pixelSize: 30
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        InkText {
                            Layout.fillWidth: true
                            text: (root.usage?.unknown?.length ?? 0) > 0 ? "API value · some models have no price" : "API value"
                            elide: Text.ElideRight
                            color: Theme.textMuted
                        }
                    }

                    // One gap at least between the figure and the tiles; the rest of the room goes here.
                    Item {
                        Layout.fillHeight: true
                        Layout.minimumHeight: Theme.gap
                    }

                    // Tiles at their natural height: squeezed, their content spilled over the top edge.
                    TileGrid {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        columns: 3
                        model: [
                            {
                                label: "Tokens",
                                icon: "\u{f01bc}",
                                value: U.tokens(root.p?.tokens ?? 0)
                            },
                            {
                                label: "Cached",
                                icon: "\u{f00e8}",
                                value: `${root.p?.cachePct ?? 0}%`
                            },
                            {
                                label: "Output",
                                icon: "\u{f1781}",
                                value: U.tokens(root.p?.output ?? 0)
                            }
                        ]

                        delegate: InfoTile {
                            required property var modelData

                            Layout.fillHeight: false
                            label: modelData.label
                            icon: modelData.icon
                            value: modelData.value
                        }
                    }
                }
            }

            TrendCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: root.cardHeight
                period: root.period
                values: root.p?.trend ?? []
                total: root.p?.cost ?? 0
            }
        }

        // Breakdown and activity.
        ColumnLayout {
            id: rightColumn

            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.pad

            BreakdownCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: root.cardHeight
                projects: root.showProjects
                rows: (root.showProjects ? root.p?.projects : root.p?.models) ?? []
                onToggled: root.showProjects = !root.showProjects
            }

            ActivityCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: root.cardHeight
                heat: root.usage?.heat ?? null
            }
        }
    }
}
