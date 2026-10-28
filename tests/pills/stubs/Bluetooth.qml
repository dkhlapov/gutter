pragma Singleton

import QtQuick
import Quickshell

// Stand-in for services/Bluetooth.qml in the pills check: an adapter that is on and has no device connected.
Singleton {
    property bool available: true
    property bool powered: true
    property var connectedNames: []
    property int connectedCount: 0

    function togglePower(): void {
    }
}
