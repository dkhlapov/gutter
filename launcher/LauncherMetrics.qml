import QtQuick
import qs.theme

// The launcher's sizes that more than one of its views share, scaled by the window's `ui`: the sizes that are not
// text go through px(), and the text stays as it is. The window makes one and hands it to its views and rows.
QtObject {
    // The window's scale: 1 up to 960 px of monitor height, then in proportion.
    required property real ui
    readonly property int boxWidth: px(520)
    // The shell's padding and gap, scaled with the box.
    readonly property real pad: px(Theme.pad)
    readonly property real gap: px(Theme.gap)
    // One row of the launcher's list.
    readonly property real rowHeight: px(Theme.pillHeight - Theme.inkWidth)

    function px(size: real): int {
        return Math.round(size * ui);
    }
}
