pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components
import "shelf"

// Files held for later. A summary card on the left (it lights up while a drag is over the pill), the
// held files as tiles on the right, or three hints while the shelf is empty.
RowLayout {
    id: root

    spacing: Theme.pad

    // Files may have changed on disk since the shelf was last shown.
    Component.onCompleted: Shelf.refresh()

    DropCard {
        Layout.preferredWidth: 260
        Layout.fillHeight: true
    }

    CaptionBox {
        Layout.fillWidth: true
        Layout.fillHeight: true
        tabs: [
            {
                text: "On the shelf",
                accent: "coral"
            }
        ]
        currentTab: 0

        ShelfGrid {
            id: grid

            anchors.fill: parent
            anchors.margins: Theme.pad
            anchors.rightMargin: Theme.pad + scroll.reserve
            visible: Shelf.items.length > 0
        }

        InkScrollBar {
            id: scroll

            anchors.top: grid.top
            anchors.bottom: grid.bottom
            anchors.left: grid.right
            anchors.leftMargin: gap
            target: grid
        }

        ShelfHints {
            anchors.fill: parent
            anchors.margins: Theme.pad
            anchors.rightMargin: Theme.pad + Theme.shadowOffset
            anchors.bottomMargin: Theme.pad + Theme.shadowOffset
            visible: Shelf.items.length === 0
        }
    }
}
