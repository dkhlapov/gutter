import QtQuick
import QtQuick.Layouts
import qs.theme
import "../lib/tiles.js" as TilesLib

// Equal-column grid with full rows only (rule 4). Delegates fill their cells.
GridLayout {
    id: root

    property var model: []
    property Component delegate

    function check(): void {
        if (model.length > 0 && !TilesLib.fullRows(model.length, columns))
            console.error(`gutter: TileGrid: ${model.length} tiles leave a ragged row of ${columns} columns`);
    }

    rowSpacing: Theme.gap
    columnSpacing: Theme.gap
    uniformCellWidths: true
    uniformCellHeights: true
    onModelChanged: check()

    Repeater {
        model: root.model
        delegate: root.delegate
    }
}
