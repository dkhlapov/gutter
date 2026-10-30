import QtQuick
import qs.theme

// Position in a track, in seconds. An ink-outlined track filled up to a square thumb. Dragging moves the
// thumb with the pointer and the seek is committed on release.
Item {
    id: root

    property real position
    property real length
    property color accent: Theme.accent.pink
    // Off: the bar only shows `position`, the pointer does nothing.
    property bool interactive: true
    // What a screen reader calls the bar ("Seek").
    property string accessibleName

    readonly property real thumbSize: 20
    readonly property real trackThickness: 12
    readonly property real travel: Math.max(1, width - thumbSize)
    readonly property real value: length > 0 ? Math.max(0, Math.min(1, position / length)) : 0
    // While the pointer is down the bar follows it; the position is committed on release.
    readonly property bool dragging: area.pressed
    // After a release the bar stays at the target until the player reports the new position (or 700 ms pass),
    // instead of jumping back to the old position first. A fraction of the length; -1 when not held.
    property real landed: -1
    readonly property real fraction: dragging ? fractionAt(area.mouseX) : landed >= 0 ? landed : value

    // What a screen reader's increase and decrease move the position by, in seconds.
    readonly property real accessibleStep: 5

    signal seek(real seconds)

    function seekBy(seconds: real): void {
        if (interactive && length > 0)
            seek(Math.max(0, Math.min(length, fraction * length + seconds)));
    }

    function fractionAt(x: real): real {
        return Math.max(0, Math.min(1, (x - thumbSize / 2) / travel));
    }

    onValueChanged: {
        if (landed >= 0 && Math.abs(value - landed) < 0.02)
            landed = -1;
    }

    implicitHeight: thumbSize + 4

    Accessible.role: interactive ? Accessible.Slider : Accessible.ProgressBar
    Accessible.name: accessibleName
    Accessible.description: `${Math.round(fraction * 100)}%`
    Accessible.focusable: interactive
    Accessible.onIncreaseAction: root.seekBy(accessibleStep)
    Accessible.onDecreaseAction: root.seekBy(-accessibleStep)

    Rectangle {
        id: track

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.trackThickness
        color: Theme.paper
        border.color: Theme.ink
        border.width: Theme.inkWidth

        Rectangle {
            x: Theme.inkWidth
            y: Theme.inkWidth
            width: Math.max(0, thumb.x + root.thumbSize / 2 - Theme.inkWidth)
            height: parent.height - 2 * Theme.inkWidth
            color: root.accent
        }
    }

    Rectangle {
        id: thumb

        anchors.verticalCenter: parent.verticalCenter
        x: root.fraction * root.travel
        width: root.thumbSize
        height: root.thumbSize
        color: Theme.paper
        border.color: Theme.ink
        border.width: Theme.inkWidth
    }

    MouseArea {
        id: area

        anchors.fill: parent
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onReleased: mouse => {
            root.landed = root.fractionAt(mouse.x);
            landTimer.restart();
            root.seek(root.landed * root.length);
        }
    }

    Timer {
        id: landTimer

        interval: 700
        onTriggered: root.landed = -1
    }
}
