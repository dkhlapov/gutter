pragma Singleton

import QtQuick
import Quickshell

// Stand-in for services/Network.qml in the pills check: connected to a Wi-Fi network.
Singleton {
    property bool available: true
    property bool connected: true
    property bool wired: false
    property string ssid: "home-5G"
    property int strength: 80
}
