pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.services
import "../lib/wheel.js" as WheelLib

// One monitor's workspace bar at the top left: five of its workspaces (the half of its group the active one is
// in, so 1-5 flips to 6-10), then the open special workspaces, each in its own box with the apps open on it.
// A click shows the workspace (a special one is shown or hidden); the wheel steps through the whole group.
// Many open special workspaces would run off the screen: the boxes are cut at `maxWidth`.
Item {
    id: root

    property string screenName
    property real maxWidth: Infinity

    readonly property var cells: Workspaces.pageFor(screenName).cells
    // The boxes' own rectangle, without the room for their shadows: what takes input.
    readonly property Item boxItem: box

    width: Math.min(row.implicitWidth, maxWidth)
    height: Theme.pillHeight + Theme.shadowOffset + Theme.shadowKeyline
    // Only while cut. It clips to this item, which leaves room below and right of the boxes for their shadows.
    clip: row.implicitWidth > maxWidth

    Item {
        id: box

        width: root.width
        height: Theme.pillHeight
    }

    Row {
        id: row

        spacing: Theme.pad

        Repeater {
            model: root.cells

            WorkspaceCell {
                required property var modelData

                cell: modelData
                onClicked: Workspaces.goTo(modelData.id, root.screenName)
                onWheeled: wheel => {
                    // A horizontal wheel is no step.
                    const dy = WheelLib.vertical(wheel.angleDelta);
                    if (dy !== 0)
                        Workspaces.stepOn(root.screenName, dy > 0 ? -1 : 1);
                }
            }
        }
    }
}
