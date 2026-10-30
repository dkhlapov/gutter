pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components
import "../../../lib/agents.js" as AgentsLib
import "../../../lib/agentUsage.js" as U

// What runs now: sessions working or waiting for you (from the hooks), each with its model, output and
// API value (from the transcripts) and how long the current task has run. A waiting session is sun-yellow.
CaptionBox {
    id: root

    property var sessions: ({})
    readonly property real rowHeight: 52
    readonly property var live: Agents.items.filter(s => s.status === "working" || s.status === "waiting")

    // The count rides in the tab, so the rows get the box's whole height.
    readonly property string caption: {
        if (root.live.length > list.fits)
            return `Now · ${root.live.length} running · scroll`;
        return root.live.length > 1 ? `Now · ${root.live.length} running` : "Now";
    }

    tabs: [
        {
            text: root.caption,
            accent: "magenta"
        }
    ]
    currentTab: 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.gap

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.live.length > 0

            ListView {
                id: list

                // Whole rows only: the list is as tall as the rows that fit, so none is cut off at the box's edge.
                readonly property int fits: Math.max(1, Math.floor((parent.height + spacing) / (root.rowHeight + spacing)))

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: scroll.reserve
                height: fits * root.rowHeight + (fits - 1) * spacing
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: root.live

                delegate: Rectangle {
                    id: row

                    required property var modelData
                    readonly property bool waiting: modelData.status === "waiting"
                    readonly property var u: root.sessions[modelData.id] ?? null
                    readonly property color ink: waiting ? Theme.on.sun : Theme.text

                    width: ListView.view.width
                    height: root.rowHeight
                    color: waiting ? Theme.accent.sun : Theme.paper
                    border.color: Theme.ink
                    border.width: Theme.inkWidth

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.inkWidth + 6
                        anchors.rightMargin: Theme.inkWidth + 6
                        spacing: Theme.gap

                        InkIcon {
                            icon: row.waiting ? "\u{f0e46}" : "\u{f06c4}"
                            size: 16
                            color: row.ink

                            // Turns while the session works: a status light, linear and endless.
                            RotationAnimator on rotation {
                                running: !row.waiting && row.visible
                                from: 0
                                to: 360
                                duration: 3000
                                loops: Animation.Infinite
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            InkText {
                                Layout.fillWidth: true
                                text: AgentsLib.project(row.modelData.cwd)
                                font.bold: true
                                elide: Text.ElideRight
                                color: row.ink
                            }

                            InkText {
                                Layout.fillWidth: true
                                text: row.waiting ? (row.modelData.message || "Needs your input") : row.u ? `${row.u.model} · ${U.tokens(row.u.output)} out · ${U.money(row.u.cost)}` : (row.modelData.tool || "Thinking")
                                elide: Text.ElideRight
                                color: Theme.mutedOn(row.ink, row.waiting ? Theme.accent.sun : Theme.paper)
                            }
                        }

                        InkText {
                            visible: !row.waiting && row.modelData.promptAt > 0
                            text: U.clock(Agents.now - row.modelData.promptAt)
                            font.pixelSize: 14
                            font.bold: true
                        }
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

        InkText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.live.length === 0
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: !Agents.hooksInstalled ? "Run scripts/install-agent-hooks.sh" : Agents.items.length > 0 ? "Idle" : "No session running"
            color: Theme.textMuted
        }
    }
}
