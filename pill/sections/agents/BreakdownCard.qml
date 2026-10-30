pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.components
import "../../../lib/agentUsage.js" as U

// The period's API value by project or by model (top four), with bars against the top one. The two tabs
// switch between projects and models.
CaptionBox {
    id: root

    property bool projects: true
    property var rows: []
    readonly property real peak: rows.length > 0 ? Math.max(0.0001, rows[0].cost) : 1

    signal toggled

    tabs: [
        {
            text: "Projects",
            accent: "magenta"
        },
        {
            text: "Models",
            accent: "magenta"
        }
    ]
    currentTab: projects ? 0 : 1
    onTabClicked: index => {
        if ((index === 0) !== root.projects)
            root.toggled();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: 6

        Repeater {
            model: root.rows.slice(0, 4)

            delegate: RowLayout {
                id: line

                required property var modelData

                Layout.fillWidth: true
                spacing: Theme.gap

                InkText {
                    Layout.preferredWidth: 110
                    text: line.modelData.name
                    font.bold: true
                    elide: Text.ElideRight
                }

                LevelBar {
                    Layout.fillWidth: true
                    implicitHeight: 12
                    value: line.modelData.cost / root.peak
                    accent: root.projects ? "teal" : "pink"
                }

                InkText {
                    Layout.preferredWidth: 54
                    horizontalAlignment: Text.AlignRight
                    text: U.money(line.modelData.cost)
                    elide: Text.ElideRight
                    color: Theme.textMuted
                }
            }
        }

        InkText {
            Layout.fillWidth: true
            visible: root.rows.length === 0
            text: "Nothing in this period"
            color: Theme.textMuted
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
