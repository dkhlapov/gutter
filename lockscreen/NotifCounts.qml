pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.services
import qs.theme
import "../lib/notifications.js" as NotifLib

// The unread notifications as one small speech bubble per app: the app's name and the number, nothing else (no
// titles, no text of any message). Hidden when there are none. `maxWidth` is the width the bubbles wrap at.
Flow {
    id: root

    property real ui: 1
    property real maxWidth: Math.round(170 * ui)
    // Whether the owner wants it at all (the layout shows one of two copies).
    property bool shown: true
    readonly property var counts: NotifLib.countsByApp(Notifications.history)
    readonly property bool has: counts.length > 0

    visible: shown && has
    width: maxWidth
    spacing: Math.round(6 * ui)

    Repeater {
        model: root.counts

        SpeechBubble {
            id: bubble

            required property var modelData

            tailX: 0.2
            tailHeight: Math.round(7 * root.ui)
            tailHalfBase: Math.round(4 * root.ui)
            padX: Math.round(8 * root.ui)
            padY: Math.round(3 * root.ui)

            Item {
                implicitWidth: name.width + gap + number.implicitWidth
                implicitHeight: Math.max(name.implicitHeight, number.implicitHeight)

                readonly property real gap: Math.round(6 * root.ui)

                InkText {
                    id: name

                    // Long names are cut to what fits beside the number.
                    width: Math.min(implicitWidth, root.maxWidth - 2 * bubble.padX - number.implicitWidth - parent.gap - 2 * Theme.inkWidth)
                    anchors.verticalCenter: parent.verticalCenter
                    text: bubble.modelData.app
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: Math.round(12 * root.ui)
                }

                InkText {
                    id: number

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(bubble.modelData.count)
                    font.bold: true
                    font.pixelSize: Math.round(12 * root.ui)
                }
            }
        }
    }
}
