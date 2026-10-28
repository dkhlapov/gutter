pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme

// An InkBox with label tabs sitting on its top edge; each tab's lower border is the box's ink line.
// A lone tab has nothing to switch to, so it is drawn as a caption instead (a paper plate with the accent as a
// swatch, never raised) and is not clickable: only two or more tabs look and act like tabs.
Item {
    id: root

    property list<var> tabs: [] // each { text, accent }
    property int currentTab: -1
    property color fill: Theme.paper
    // Draws the current tab with halftone dots over its accent.
    property bool currentHalftone: false
    // A paper line around the box's shadow (see InkBox).
    property bool keyline: false
    // False fades the tabs out, for a box folding away under them (the pill's panel as it closes).
    property bool tabsShown: true
    default property alias content: box.content

    signal tabClicked(int index)

    // One tab only: drawn as a caption and not clickable.
    readonly property bool captioned: tabs.length === 1
    // Room above the box's edge for the tallest (active) tab, whether or not one is active,
    // so changing `currentTab` never moves the box.
    readonly property real headroom: tabs.length > 0 ? Theme.pillHeight - Theme.inkWidth : 0

    implicitWidth: Math.max(box.implicitWidth, tabRow.implicitWidth)
    implicitHeight: headroom + box.implicitHeight

    InkBox {
        id: box

        y: root.headroom
        width: root.width
        height: root.height - y
        fill: root.fill
        keyline: root.keyline
    }

    // Clipped to the box's width, so tabs past a narrowing box's edge are cut off with it.
    Item {
        width: root.width
        height: tabRow.height
        clip: true
        opacity: root.tabsShown ? 1 : 0
        enabled: root.tabsShown

        Behavior on opacity {
            Anim {
                duration: Theme.animMs / 2
            }
        }

        RowLayout {
            id: tabRow

            // Tabs sit on the box edge: their bottom border is the box's top border.
            y: 0
            height: root.headroom + Theme.inkWidth
            spacing: -Theme.inkWidth

            Repeater {
                model: root.tabs

                LabelTab {
                    id: tab

                    required property var modelData
                    required property int index

                    Layout.alignment: Qt.AlignBottom
                    text: tab.modelData.text
                    accent: tab.modelData.accent
                    active: tab.index === root.currentTab
                    caption: root.captioned
                    halftone: root.currentHalftone && tab.active
                    z: tab.active ? 1 : 0

                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.captioned
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.tabClicked(tab.index)
                    }
                }
            }
        }
    }
}
