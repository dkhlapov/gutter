import QtQuick
import qs.theme

// A small coloured caption tab. An active tab stands taller than its neighbours.
// A `caption` is the lone title of a box with nothing to switch between (see CaptionBox): not a tab, so a paper
// plate with the accent as a small swatch, always at the resting height.
Item {
    id: root

    property string text
    property string accent: "sun"
    property bool active: false
    // Halftone dots over the accent, under the text.
    property bool halftone: false
    property bool caption: false
    readonly property real swatch: 10

    implicitWidth: label.implicitWidth + 2 * Theme.pad + (caption ? swatch + Theme.gap - 2 : 0)
    implicitHeight: Theme.pillHeight - 2 * Theme.inkWidth + (active && !caption ? 2 * Theme.inkWidth : 0)

    Rectangle {
        anchors.fill: parent
        color: root.caption ? Theme.paper : Theme.accent[root.accent]
        border.color: Theme.ink
        border.width: Theme.inkWidth
    }

    Item {
        anchors.fill: parent
        anchors.margins: Theme.inkWidth
        visible: root.halftone && !root.caption

        Halftone {}
    }

    // Keeps the dots from running through the text: a solid patch of the tab's own fill behind it.
    Rectangle {
        anchors.centerIn: label
        width: label.implicitWidth + 2 * Theme.inkWidth
        height: label.implicitHeight + 2 * Theme.platePad
        visible: root.halftone && !root.caption
        color: Theme.accent[root.accent]
    }

    Rectangle {
        visible: root.caption
        x: Theme.pad
        anchors.verticalCenter: parent.verticalCenter
        width: root.swatch
        height: root.swatch
        color: Theme.accent[root.accent]
        border.color: Theme.ink
        border.width: 2
    }

    InkText {
        id: label

        anchors.verticalCenter: parent.verticalCenter
        // The capitals sit a pixel above the middle of the line box, so the line is lowered to put them midway
        // between the tab's top and bottom borders.
        anchors.verticalCenterOffset: 1
        x: root.caption ? Theme.pad + root.swatch + Theme.gap - 2 : (parent.width - width) / 2
        text: root.text.toUpperCase()
        color: root.caption ? Theme.text : Theme.on[root.accent]
        font.bold: true
        font.letterSpacing: 0.5
        font.pixelSize: 11
    }
}
