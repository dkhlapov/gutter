import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.theme
import "../lib/pillState.js" as PillState

// The island's face, laid out inside an InkBox: the date and time, always the same width and height.
// While an activity that is not a speech bubble runs, its view stands in for the date and time. A HUD (volume,
// brightness, the keys) also begins with its label tab (VOL, BRI, KBD, CAPS, NUM), which reaches out to the box's
// outline by inkWidth on the left and top (its own outline coincides with it).
Item {
    id: root

    // An activity view replaces the body; `activityId` says which.
    property bool activity: false
    property string activityId: ""
    // Size of the box this sits in, outline included; the body stays centred in its width.
    property real boxWidth: implicitWidth + 2 * Theme.inkWidth
    property real boxHeight: Theme.pillHeight

    readonly property bool hud: activity && view.tabText !== ""
    // Where the body starts: after the label tab of a HUD, else after the padding.
    readonly property real bodyStart: hud ? tab.x + tab.width + Theme.pad : Theme.pad
    // The body never gets more than the room after the tab: while the box is narrower than the face (capped, or
    // still growing towards it) the text elides instead of running past the outline.
    readonly property var bodyFit: PillState.fit(body.implicitWidth, width - bodyStart - Theme.pad)
    // The width of each face; the pill asks both to size itself, whichever shows.
    readonly property real restWidth: Theme.pad + clockText.implicitWidth + Theme.pad
    readonly property real activityWidth: bodyStart + view.implicitWidth + Theme.pad

    implicitWidth: activity ? activityWidth : restWidth
    implicitHeight: Theme.pillHeight - 2 * Theme.inkWidth
    width: boxWidth - 2 * Theme.inkWidth
    height: boxHeight - 2 * Theme.inkWidth

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    LabelTab {
        id: tab

        x: -Theme.inkWidth
        y: -Theme.inkWidth
        width: Math.max(implicitWidth, 34)
        height: root.boxHeight
        visible: root.hud
        // Cut off at its own edge, like the body: its label stands taller than a box growing from nothing.
        clip: true
        text: view.tabText
        accent: view.tabAccent
        active: true
    }

    RowLayout {
        id: body

        x: root.bodyStart + root.bodyFit.x
        width: root.bodyFit.w
        height: root.height
        // The text gives way to a narrower box, but nothing gives way to a lower one (the box growing from nothing,
        // or into the taller track pop): the body is cut off at the outline until it fits.
        clip: true
        spacing: Theme.gap

        InkText {
            id: clockText

            visible: !root.activity
            text: `${Qt.formatDate(clock.date, "ddd d MMM")} · ${Qt.formatTime(clock.date, "HH:mm")}`
            font.pixelSize: Theme.textSize
            font.bold: true
        }

        ActivityView {
            id: view

            // Squeezed, the view gives way down to its fixed parts.
            Layout.fillWidth: true
            Layout.minimumWidth: minimumWidth
            visible: root.activity
            activityId: root.activity ? root.activityId : ""
        }
    }
}
