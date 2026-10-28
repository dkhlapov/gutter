import QtQuick
import qs.theme
import "../lib/scrollbar.js" as ScrollLib

// A vertical scroll bar for a list: an ink line with a paper thumb on it. It sits in a strip beside the list, so it
// never covers a row: anchor its left to the list's right (a `gap` away, top and bottom to the list's) and make the
// list that much narrower, by `reserve`, while there is something to scroll. It shows while the list scrolls or the
// pointer is over the list or the bar, and goes a moment after. Press the track to jump, drag the thumb to scroll.
Item {
    id: root

    // The list it scrolls: a ListView, GridView or Flickable.
    required property Flickable target

    // The visible length of the list. A list whose height eases to its size can say its final one here, so the bar
    // (and the room it takes) does not come and go while it moves.
    property real viewLength: target.height

    readonly property bool needed: ScrollLib.needed(viewLength, target.contentHeight)
    readonly property bool dragging: grab.pressed
    // Scrolled lately, so the bar lingers after a wheel notch or a flick.
    property bool recent: false
    readonly property bool shown: needed && (recent || dragging || hover.hovered || over.hovered)
    readonly property real thumbMin: 24
    readonly property real gap: 4
    // The room the list gives up for the bar: none while everything fits.
    readonly property real reserve: needed ? width + gap : 0
    readonly property var geometry: ScrollLib.thumb(viewLength, target.contentHeight, target.contentY - target.originY, height, thumbMin)

    width: 12
    opacity: shown ? 1 : 0
    // While there is nothing to scroll no strip is reserved, so the bar is not shown at all. Faded out it still takes
    // the pointer, which is safe because it covers no row: a pointer that reaches the strip first brings it back.
    visible: needed

    Behavior on opacity {
        Anim {}
    }

    Connections {
        target: root.target

        function onContentYChanged(): void {
            root.recent = true;
            linger.restart();
        }
    }

    Timer {
        id: linger

        interval: 900
        onTriggered: root.recent = false
    }

    // Over the list itself, not only the bar.
    HoverHandler {
        id: hover

        parent: root.target
    }

    HoverHandler {
        id: over
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 2
        height: parent.height
        color: Theme.ink
    }

    Rectangle {
        id: thumb

        width: root.width
        y: root.geometry.offset
        height: root.geometry.length
        color: root.dragging ? Theme.role.active : Theme.paper
        border.color: Theme.ink
        border.width: Theme.inkWidth
    }

    MouseArea {
        id: grab

        anchors.fill: parent
        enabled: root.needed
        cursorShape: Qt.PointingHandCursor
        // A drag stays a drag inside a flickable.
        preventStealing: true
        // Where inside the thumb the press landed, so the thumb does not jump to the cursor.
        property real grabOffset: 0

        function scrollTo(offset: real): void {
            const t = root.target;
            t.contentY = t.originY + ScrollLib.posAt(root.viewLength, t.contentHeight, offset, root.height, root.thumbMin);
        }

        onPressed: mouse => {
            // A wheel or flick still gliding would carry the list away from the thumb.
            root.target.cancelFlick();
            const inside = mouse.y >= thumb.y && mouse.y <= thumb.y + thumb.height;
            grabOffset = inside ? mouse.y - thumb.y : thumb.height / 2;
            scrollTo(mouse.y - grabOffset);
        }
        onPositionChanged: mouse => {
            if (pressed)
                scrollTo(mouse.y - grabOffset);
        }
        // The wheel over the strip scrolls the list as it does over the rows.
        onWheel: wheel => {
            if (wheel.angleDelta.y === 0 && wheel.pixelDelta.y === 0) {
                wheel.accepted = false;
                return;
            }
            const t = root.target;
            const top = t.originY;
            // A touchpad says how many pixels, a wheel only how far it turned.
            const delta = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 2;
            t.contentY = Math.max(top, Math.min(top + t.contentHeight - root.viewLength, t.contentY - delta));
        }
    }
}
