pragma Singleton

import QtQuick
import Quickshell

// Stand-in for services/Agents.qml in the fit check.
Singleton {
    property var items: []
    property real now: Date.now()
    property var lastDone: null
}
