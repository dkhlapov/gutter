import QtQuick
import qs.components
import qs.theme
import "../lib/pillState.js" as PillState

// A pill beside the island: an InkBox of the island's height (same ink, shadow and keyline), grown from nothing
// while `wanted` and folded away again after. It is also the input item for its side of the surface: as wide and
// as high as what shows, nothing at all while gone, so the window's mask covers only what is drawn. The island
// next to it never moves for it: the pill's x and width come from lib/sidePills.js (layout). Hovered, it peeks like
// the island does: it grows by the island's peek, evenly all round, into room that layout keeps free.
MouseArea {
    id: root

    // Set by the pill: whether it should show, the box's left edge and width, the line the island is centred on.
    property bool wanted: false
    property real boxX: 0
    property real boxW: 0
    property real centreY: Theme.pillTop + Theme.pillHeight / 2
    // Whether the pointer is on this pill (as the pill decides it: after the hover delay).
    property bool peeking: false
    default property alias content: body.data

    property real reveal: wanted ? 1 : 0
    readonly property bool shown: reveal > 0
    readonly property real boxH: Theme.pillHeight * reveal
    property real peekW: peeking && wanted ? PillState.PEEK_W : 0
    property real peekH: peeking && wanted ? PillState.PEEK_H : 0
    readonly property alias hovered: hover.hovered

    Behavior on reveal {
        Anim {}
    }
    Behavior on peekW {
        Anim {}
    }
    Behavior on peekH {
        Anim {}
    }

    // From the top edge of the screen down past the shadow, so the pointer thrown against the edge lands on it.
    x: boxX - peekW / 2
    y: 0
    width: shown ? boxW + peekW + Theme.shadowOffset : 0
    height: shown ? centreY + (boxH + peekH) / 2 + Theme.shadowOffset : 0
    visible: shown
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor

    HoverHandler {
        id: hover
    }

    InkBox {
        y: root.centreY - height / 2
        width: root.boxW + root.peekW
        height: root.boxH + root.peekH
        keyline: true

        // Cut off at the outline while the box grows from nothing, like the island's body.
        Item {
            id: body

            anchors.fill: parent
            clip: true
        }
    }
}
