import QtQuick
import Quickshell.Services.UPower
import qs.components
import qs.services
import qs.theme
import "../lib/lock.js" as LockLib
import "../lib/status.js" as StatusLib

// A row of small chips along the bottom: the keyboard layout (a click switches it, as on the bar) and the
// battery's level (with a bolt while charging). A chip with nothing to show is left out, and so is the row:
// a desktop without a battery shows the layout alone. No window is needed.
Row {
    id: root

    property real ui: 1
    // Whether the owner wants it at all (the layout shows one of two copies).
    property bool shown: true
    readonly property var battery: LockLib.batteryChip({
        isPresent: UPower.displayDevice?.isPresent ?? false,
        percentage: UPower.displayDevice?.percentage,
        charging: UPower.displayDevice?.state === UPowerDeviceState.Charging
    })
    readonly property bool has: KbLayout.available || battery.visible

    visible: shown && has
    spacing: Math.round(10 * ui)

    InkButton {
        visible: KbLayout.available
        height: Math.round(24 * root.ui)
        text: StatusLib.kbShort(KbLayout.layout)
        textSize: Math.round(13 * root.ui)
        onClicked: KbLayout.next()
    }

    InkBox {
        visible: root.battery.visible

        Item {
            implicitWidth: level.implicitWidth + Math.round(18 * root.ui)
            implicitHeight: Math.round(24 * root.ui) - 2 * Theme.inkWidth

            InkText {
                id: level

                anchors.centerIn: parent
                text: root.battery.text
                font.bold: true
                font.pixelSize: Math.round(13 * root.ui)
            }
        }
    }
}
