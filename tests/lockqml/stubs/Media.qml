pragma Singleton

import QtQuick
import Quickshell

// Stand-in for services/Media.qml in the lock's idle check (scripts/lock-qml.sh): Idle only asks whether audio plays,
// and the real service would look for players on the (private) session bus.
Singleton {
    property bool playing: false
}
