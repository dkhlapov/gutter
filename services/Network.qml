pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking

// The connection the status row shows: the connected Wi-Fi network (name, signal strength 0-100), or a cabled
// link. Without any network device `available` is false and the row hides its chip.
Singleton {
    id: root

    readonly property var devices: Networking.devices?.values ?? []
    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi && d.connected) ?? null
    readonly property var wifiNetwork: wifiDevice?.networks?.values.find(n => n.connected) ?? null

    readonly property bool wired: devices.some(d => d.type === DeviceType.Wired && d.connected)
    readonly property bool available: devices.length > 0
    readonly property bool connected: wired || wifiNetwork !== null
    readonly property string ssid: wired ? "" : wifiNetwork?.name ?? ""
    readonly property int strength: wired ? 100 : Math.round((wifiNetwork?.signalStrength ?? 0) * 100)

    // Devices can show up a moment after start (NetworkManager answers over D-Bus), so judge only after a wait.
    Timer {
        interval: 5000
        running: true
        onTriggered: {
            if (!root.available)
                console.warn("gutter: no network device, hiding the network chip");
        }
    }
}
