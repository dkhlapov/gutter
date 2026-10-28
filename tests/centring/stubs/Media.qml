pragma Singleton

import QtQuick
import Quickshell

// Stand-in for services/Media.qml in the centring check: a playing track, and the player features the check switches.
Singleton {
    readonly property var active: ({ identity: "Player", dbusName: "player", isPlaying: true })
    readonly property var players: [active]
    property bool playing: true
    property string title: "A track"
    property string artist: "An artist"
    property string album: "An album"
    property string artUrl: ""
    property real position: 42
    property real length: 180
    property bool canShuffle: false
    property bool shuffle: false
    property bool canLoop: false
    property int loopState: 0
    readonly property var cava: QtObject {
        property int refs: 0
        readonly property int bars: 24
        readonly property var values: new Array(24).fill(0)
    }

    function select(id: string): void {
    }
    function togglePlaying(): void {
    }
    function next(): void {
    }
    function previous(): void {
    }
    function seek(seconds: real): void {
    }
    function toggleShuffle(): void {
    }
    function cycleLoop(): void {
    }
}
