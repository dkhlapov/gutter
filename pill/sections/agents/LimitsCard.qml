pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components
import "../../../lib/agentUsage.js" as U

// Plan limits: the 5-hour session, the week and, when Anthropic's usage endpoint reports it, the weekly limit of
// one model; % used and when each resets. Pro / Max only. AgentUsage merges the endpoint with the status-line
// bridge (Claude Code CLI sessions), so they show without the CLI.
CaptionBox {
    id: root

    readonly property var limits: AgentUsage.limits
    readonly property bool known: limits.session !== null || limits.week !== null
    // Every window has reset since Claude Code last reported: the bars would all be empty.
    readonly property bool allRenewed: known && [limits.session, limits.week, limits.model].filter(w => w !== null).every(w => w.renewed)
    readonly property var empty: U.limitsEmpty(AgentUsage.limitsReason)

    tabs: [
        {
            text: "Claude",
            accent: "magenta"
        }
    ]
    currentTab: 0

    function barAccent(pct: real): string {
        return pct >= 95 ? "coral" : pct >= 80 ? "sun" : "teal";
    }

    // Something is working: a lamp on the box's top edge blinks (on and off, not faded). The wrapper fills the
    // box, so the box does not count the lamp's position in its implicit size.
    Item {
        anchors.fill: parent

        Rectangle {
            id: pulse

            readonly property bool working: Agents.counts.working > 0
            property bool lit: true

            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: Theme.pad
            anchors.topMargin: -(Theme.inkWidth + 5)
            width: 14
            height: 14
            visible: working && lit
            color: Theme.accent.magenta
            border.color: Theme.ink
            border.width: Theme.inkWidth

            Timer {
                running: pulse.working && root.visible
                repeat: true
                interval: 700
                onTriggered: pulse.lit = !pulse.lit
            }
        }
    }

    // `limits` is rebuilt every second (it counts down to the resets), so the model is a fixed count: a model of
    // fresh objects would recreate the rows each second and restart the bars' animation from empty.
    ColumnLayout {
        id: rows

        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.gap
        visible: root.known && !root.allRenewed

        Repeater {
            model: root.known ? (root.limits.model !== null ? 3 : 2) : 0

            delegate: ColumnLayout {
                id: row

                required property int index
                readonly property var modelData: ({ label: U.windowLabel(index, root.limits.model?.name ?? ""), span: index === 0 ? 5 * 3600 : 7 * 86400 })
                readonly property var w: index === 0 ? root.limits.session : index === 1 ? root.limits.week : root.limits.model

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    InkText {
                        text: row.modelData.label
                        font.pixelSize: 12
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.maximumWidth: rows.width * 0.6
                    }

                    InkIcon {
                        visible: (row.w?.resetsIn ?? -1) > 0
                        icon: "\u{f006a}"
                        size: 13
                        opacity: 0.7
                    }

                    InkText {
                        Layout.fillWidth: true
                        text: row.w === null ? "" : row.w.renewed ? "Reset · waiting for new data" : row.w.resetsIn > 0 ? U.duration(row.w.resetsIn) : ""
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        opacity: 0.7
                    }

                    InkText {
                        text: row.w === null || row.w.pct === null ? "—" : `${Math.round(row.w.pct)}%`
                        font.pixelSize: 13
                        font.bold: true
                    }
                }

                LevelBar {
                    id: bar

                    readonly property real pace: U.pace(row.w, row.modelData.span)

                    Layout.fillWidth: true
                    implicitHeight: 12
                    value: (row.w?.pct ?? 0) / 100
                    accent: root.barAccent(row.w?.pct ?? 0)

                    // Pace mark: how much of the window has passed; use beyond it runs ahead of pace.
                    Rectangle {
                        visible: bar.pace >= 0
                        x: Math.round(bar.pace * (bar.width - width))
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: bar.height + 6
                        color: Theme.ink
                    }
                }
            }
        }
    }

    EmptyState {
        anchors.centerIn: parent
        visible: !root.known || root.allRenewed
        compact: true
        textWidth: Math.max(0, root.width - 2 * Theme.pad - 44 - Theme.pad)
        accent: "magenta"
        icon: "\u{f0150}" // md-clock_outline
        text: root.allRenewed ? "Limits have reset" : root.empty.title
        hint: root.allRenewed ? "A new window has started. Usage appears with the next reading." : root.empty.hint
    }
}
