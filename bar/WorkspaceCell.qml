pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.services
import qs.components
import "../lib/workspaces.js" as WS

// One workspace in the workspace bar: its own small ink box with the number (a special workspace's glyph) in a
// tab on the left, then the icons of the apps open on it, each app once and at most four with a "+n" after.
// The tab is paper while the workspace is empty and its accent once it has windows; the whole box fills with the
// active role while it is in view and the urgent role when a window asks for attention. Hovered it shows
// halftone dots.
Item {
    id: root

    // A cell from Workspaces.pageFor: { id, label, name, state, accent, apps }.
    required property var cell

    readonly property int maxApps: 4
    readonly property var summary: WS.appSummary(cell.apps, maxApps)
    readonly property bool special: cell.id < 0
    readonly property bool empty: cell.state === "empty"
    readonly property string boxAccent: cell.state === "active" ? Theme.roleAccent.active : cell.state === "urgent" ? Theme.roleAccent.urgent : ""
    readonly property string tabAccent: special ? "magenta" : cell.accent
    readonly property real tabWidth: Theme.pillHeight - 2 * Theme.inkWidth
    readonly property bool hovered: area.containsMouse

    // The app icons' model, brought in line with the summary so a window opening or closing updates the icons in
    // place instead of rebuilding them.
    ListModel {
        id: appModel

        dynamicRoles: true
    }

    onSummaryChanged: WS.syncList(appModel, summary.apps, "appId")
    Component.onCompleted: WS.syncList(appModel, summary.apps, "appId")

    signal clicked
    signal wheeled(var wheel)

    // A square while empty; with apps, the tab (ruled off from them) and the apps with a gap on both sides.
    implicitWidth: tabWidth + (apps.visible ? apps.implicitWidth + 2 * Theme.gap : 0) + 2 * Theme.inkWidth
    implicitHeight: Theme.pillHeight

    InkBox {
        anchors.fill: parent
        keyline: true
        fill: root.boxAccent !== "" ? Theme.accent[root.boxAccent] : Theme.paper

        Item {
            anchors.fill: parent
            visible: root.hovered
            opacity: 0.35

            Halftone {}
        }

        // The number tab, ruled off from the icons.
        Rectangle {
            id: tab

            width: root.tabWidth
            height: parent.height
            color: root.empty ? "transparent" : Theme.accent[root.tabAccent]

            Rectangle {
                visible: apps.visible
                anchors.right: parent.right
                width: Theme.inkWidth
                height: parent.height
                color: Theme.ink
            }

            InkIcon {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: apps.visible ? -Theme.inkWidth / 2 : 0
                visible: root.special
                icon: WS.specialIcon(root.cell.name ?? root.cell.label)
                size: Theme.glyphSize
                color: root.empty ? (root.boxAccent !== "" ? Theme.on[root.boxAccent] : Theme.text) : Theme.on[root.tabAccent]
            }

            InkText {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: apps.visible ? -Theme.inkWidth / 2 : 0
                visible: !root.special
                text: root.cell.label
                color: root.empty ? (root.boxAccent !== "" ? Theme.on[root.boxAccent] : Theme.text) : Theme.on[root.tabAccent]
                font.bold: true
                font.pixelSize: Theme.textSize
            }
        }

        Row {
            id: apps

            visible: root.summary.apps.length > 0
            anchors.verticalCenter: parent.verticalCenter
            x: tab.width + Theme.gap
            spacing: 6

            Repeater {
                model: appModel

                Item {
                    id: app

                    required property string appId
                    readonly property string icon: Workspaces.appIcon(appId)

                    implicitWidth: Theme.appIconSize
                    implicitHeight: Theme.appIconSize

                    TrayIcon {
                        anchors.fill: parent
                        size: Theme.appIconSize
                        visible: app.icon !== ""
                        source: app.icon
                    }

                    // An app without an icon in the theme: the first letter of its id.
                    InkText {
                        anchors.centerIn: parent
                        visible: app.icon === ""
                        text: app.appId.replace(/^.*\./, "").charAt(0).toUpperCase()
                        color: root.boxAccent !== "" ? Theme.on[root.boxAccent] : Theme.text
                        font.bold: true
                        font.pixelSize: Theme.textSize
                    }
                }
            }

            InkText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.summary.more > 0
                text: `+${root.summary.more}`
                color: root.boxAccent !== "" ? Theme.on[root.boxAccent] : Theme.text
                font.bold: true
                font.pixelSize: Theme.textSize
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        onWheel: wheel => root.wheeled(wheel)
    }
}
