pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.services

// Few files get big tiles that fill the card; many shrink to six columns and scroll.
GridView {
    id: root

    readonly property int itemCount: Shelf.items.length
    readonly property int columns: itemCount <= 3 ? 3 : itemCount <= 8 ? 4 : 6
    readonly property int rows: Math.max(1, Math.ceil(itemCount / columns))

    cellWidth: Math.floor(width / columns)
    cellHeight: Math.max(138, Math.min(210, Math.floor(height / rows)))
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: Shelf.items

    delegate: Item {
        id: cell

        required property var modelData

        width: root.cellWidth
        height: root.cellHeight

        // Room on the right and below for the tile's hard shadow.
        ShelfTile {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.topMargin: 4
            anchors.rightMargin: 4 + Theme.shadowOffset
            anchors.bottomMargin: 4 + Theme.shadowOffset
            path: cell.modelData.path
        }
    }
}
