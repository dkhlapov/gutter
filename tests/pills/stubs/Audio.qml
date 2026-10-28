pragma Singleton

import QtQuick
import Quickshell

// Stand-in for services/Audio.qml in the pills check: a sink and a microphone that are both there.
Singleton {
    property bool ready: true
    property real volume: 0.7
    property bool muted: false
    property bool micReady: true
    property bool micMuted: false

    function press(delta: real): void {
    }
    function toggleMute(): void {
    }
    function toggleMicMute(): void {
    }
}
