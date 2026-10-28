pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth as Bt

// The default Bluetooth adapter's power and the names of the devices connected to it. Without an adapter
// `available` is false and the row hides its chip.
Singleton {
    id: root

    readonly property var adapter: Bt.Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool powered: adapter?.enabled ?? false
    readonly property var connectedNames: adapter?.devices?.values.filter(d => d.connected).map(d => d.name || d.deviceName) ?? []
    readonly property int connectedCount: connectedNames.length

    function togglePower(): void {
        if (adapter)
            adapter.enabled = !adapter.enabled;
    }

    // BlueZ can answer a moment after start, so judge only after a wait.
    Timer {
        interval: 5000
        running: true
        onTriggered: {
            if (!root.available)
                console.warn("gutter: no Bluetooth adapter, hiding the Bluetooth chip");
        }
    }
}
