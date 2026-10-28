import QtQuick
import qs.components
import qs.services

// The speech bubble of a transient activity (timer done, agent done, notification): the activity's view on
// paper, with the tail at the left of its top edge (SpeechBubble's default). The pill lines it up with its own left
// edge, so the tail points up at the pill's tab. For a notification the bubble holds the click area and the hover
// that pauses its timer.
SpeechBubble {
    id: root

    required property string activityId

    // A notification acts on the whole balloon, padding ring and tail included, and holds its timer while the
    // pointer is anywhere on it. The click area sits below the view, so the view's buttons and × take their
    // clicks first. Both are parented to the balloon, not left in the padded content (the default property),
    // so their coordinates are the ones `inside` takes. While the screen is locked nothing is hovered.
    readonly property Item clickArea: click
    readonly property HoverHandler hoverArea: hover
    readonly property bool notification: activityId === "notification" && Notifications.current !== null
    readonly property bool pointed: notification && !Notifications.screenLocked && hover.hovered && inside(hover.point.position.x, hover.point.position.y)

    width: implicitWidth
    height: implicitHeight

    // Counted, not a flag (see Notifications.bubbleHovers).
    onPointedChanged: Notifications.hoverBubble(pointed)
    // A bubble torn down under the pointer would leave the timer paused.
    Component.onDestruction: {
        if (pointed)
            Notifications.hoverBubble(false);
    }

    HoverHandler {
        id: hover

        parent: root
    }

    MouseArea {
        id: click

        parent: root
        z: -1
        anchors.fill: parent
        enabled: root.notification
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        containmentMask: QtObject {
            function contains(point: point): bool {
                return root.inside(point.x, point.y);
            }
        }
        onClicked: {
            // A notification with nothing to reach (see `Notifications.activate`) still has its bubble taken down.
            if (!Notifications.activate(Notifications.currentId))
                Notifications.dismissBubble();
        }
    }

    ActivityView {
        anchors.centerIn: parent
        activityId: root.activityId
    }
}
