import QtQuick
import qs.theme
import "../lib/wheel.js" as WheelLib

// A track with a filled part and a square handle. `moved` fires while dragging; the caller sets `value`.
// The fill is `accent` (a Theme.accent name; the active role when empty), or solid ink while `muted`.
// The wheel turns into whole notches on `stepped`. Disabled, the fill is hidden and the track ignores input.
// Not `interactive` (a HUD only shows a level): the fill stays, the pointer passes through to what lies beneath.
Item {
    id: root

    property real value: 0 // 0..1
    property bool vertical: false
    property string accent: ""
    property bool muted: false
    property bool interactive: true

    readonly property real trackThickness: 12
    readonly property real handleLong: 22
    readonly property real handleShort: 16
    readonly property real travel: (vertical ? height : width) - handleShort
    readonly property real clamped: Math.max(0, Math.min(1, value))

    signal moved(real value)
    signal stepped(int steps)

    implicitWidth: vertical ? handleLong : 120
    implicitHeight: vertical ? 120 : handleLong

    function valueAt(pos: real): real {
        const p = Math.max(0, Math.min(1, (pos - handleShort / 2) / travel));
        return vertical ? 1 - p : p;
    }

    Rectangle {
        id: track

        anchors.centerIn: parent
        width: root.vertical ? root.trackThickness : root.width
        height: root.vertical ? root.height : root.trackThickness
        color: Theme.paper
        border.color: Theme.ink
        border.width: Theme.inkWidth

        Rectangle {
            x: Theme.inkWidth
            y: root.vertical ? handle.y + root.handleShort / 2 : Theme.inkWidth
            width: root.vertical ? parent.width - 2 * Theme.inkWidth : handle.x + root.handleShort / 2 - Theme.inkWidth
            height: root.vertical ? parent.height - y - Theme.inkWidth : parent.height - 2 * Theme.inkWidth
            visible: root.enabled
            color: root.muted ? Theme.ink : root.accent === "" ? Theme.role.active : Theme.accent[root.accent]
        }
    }

    Rectangle {
        id: handle

        width: root.vertical ? root.handleLong : root.handleShort
        height: root.vertical ? root.handleShort : root.handleLong
        x: root.vertical ? 0 : root.clamped * root.travel
        y: root.vertical ? (1 - root.clamped) * root.travel : 0
        color: Theme.paper
        border.color: Theme.ink
        border.width: Theme.inkWidth
    }

    // Pointer state, internal to the slider.
    QtObject {
        id: pointerState

        // Distance from the handle's centre to the cursor when the press landed on the handle, else 0.
        property real grabOffset: 0
        // The wheel's fraction of a notch not yet stepped.
        property real wheelRest: 0
    }

    MouseArea {
        id: area

        anchors.fill: parent
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        // Inside a flickable (the mixer's row of strips) a drag along the track stays a drag.
        preventStealing: true
        onWheel: wheel => {
            if (Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y)) {
                wheel.accepted = false; // horizontal scroll switches sections
                return;
            }
            const r = WheelLib.accumulate(pointerState.wheelRest, wheel.angleDelta.y);
            pointerState.wheelRest = r.rest;
            if (r.steps !== 0)
                root.stepped(r.steps);
        }
        onPressed: mouse => {
            const pos = root.vertical ? mouse.y : mouse.x;
            const centre = (root.vertical ? handle.y : handle.x) + root.handleShort / 2;
            // A press on the handle keeps its offset so the handle does not jump; elsewhere it jumps to the cursor.
            pointerState.grabOffset = Math.abs(pos - centre) <= root.handleShort / 2 ? pos - centre : 0;
            root.moved(root.valueAt(pos - pointerState.grabOffset));
        }
        onPositionChanged: mouse => {
            if (pressed)
                root.moved(root.valueAt((root.vertical ? mouse.y : mouse.x) - pointerState.grabOffset));
        }
    }
}
