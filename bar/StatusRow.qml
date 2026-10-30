pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.services
import "../lib/status.js" as StatusLib
import "../lib/wheel.js" as WheelLib

// Five bar cells: volume, microphone, keyboard layout, network, Bluetooth. A cell hides while its source is
// unavailable. A dimmed cell with its "off" glyph means off (muted, or Bluetooth powered down); a cell is filled
// only while the mouse is down.
Row {
    id: root

    spacing: Theme.pad

    // The bar, which shows the cells' tooltips, and the screen it is on (the network cell opens the island there).
    required property Item host
    required property string screenName
    property real wheelRest: 0
    // The widest of the volume glyphs, whichever shows: they differ by a few pixels.
    readonly property real widestGlyph: {
        let w = 0;
        for (let i = 0; i < glyphs.count; i++)
            w = Math.max(w, (glyphs.objectAt(i) as TextMetrics).width);
        return w;
    }

    TextMetrics {
        id: widest

        font: volume.labelFont
        text: "100%"
    }

    Instantiator {
        id: glyphs

        model: StatusLib.VOLUME_ICONS

        TextMetrics {
            required property string modelData

            font.family: Theme.font
            font.pixelSize: volume.iconSize
            text: modelData
        }
    }

    Segment {
        id: volume

        accessibleName: "Volume"
        accessibleDescription: Audio.muted ? "Muted" : StatusLib.percent(Audio.volume)
        // As wide as at 100 % with the widest glyph, so the cells beside it stay put while the volume changes.
        contentWidth: Math.max(implicitContentWidth, root.widestGlyph + widest.width + Theme.gap)
        icon: StatusLib.volumeIcon(Audio.volume, Audio.muted)
        text: StatusLib.percent(Audio.volume)
        visible: Audio.ready
        dimmed: Audio.muted
        onClicked: Audio.toggleMute()
        onWheeled: wheel => {
            // Whole notches only: touchpads and hi-res wheels send many small deltas per notch. A horizontal wheel is
            // no step.
            const r = WheelLib.accumulate(root.wheelRest, WheelLib.vertical(wheel.angleDelta));
            root.wheelRest = r.rest;
            if (r.steps !== 0)
                Audio.press(r.steps * 0.05);
        }
    }

    Segment {
        accessibleName: "Microphone"
        accessibleDescription: Audio.micMuted ? "Muted" : "On"
        visible: Audio.micReady
        icon: StatusLib.micIcon(Audio.micMuted)
        dimmed: Audio.micMuted
        onClicked: Audio.toggleMicMute()
    }

    Segment {
        accessibleName: "Keyboard layout"
        visible: KbLayout.available
        text: StatusLib.kbShort(KbLayout.layout)
        onClicked: KbLayout.next()
    }

    Segment {
        accessibleName: "Network"
        visible: Network.available
        icon: StatusLib.wifiIcon(Network.strength, Network.connected, Network.wired)
        // A long network name is cut, so it cannot push the bar across the screen.
        text: Network.connected ? Network.ssid : ""
        maxTextWidth: 160
        dimmed: !Network.connected
        tip: ({
                title: "Network",
                body: StatusLib.wifiTip(Network.connected, Network.wired, Network.ssid, Network.strength)
            })
        tipHost: root.host
        onClicked: PillControl.openOn(root.screenName, "system")
    }

    Segment {
        accessibleName: "Bluetooth"
        visible: Bluetooth.available
        icon: StatusLib.bluetoothIcon(Bluetooth.powered, Bluetooth.connectedCount)
        // A long device name is cut too.
        text: StatusLib.bluetoothText(Bluetooth.powered, Bluetooth.connectedNames)
        maxTextWidth: 120
        dimmed: !Bluetooth.powered
        tip: ({
                title: "Bluetooth",
                body: StatusLib.bluetoothTip(Bluetooth.powered, Bluetooth.connectedNames)
            })
        tipHost: root.host
        onClicked: Bluetooth.togglePower()
    }
}
