pragma Singleton

import QtQuick
import Quickshell

// Stand-in for services/Media.qml in the fit check: the track is whatever the check writes.
Singleton {
    property var active: ({})
    property bool playing: true
    property string title: ""
    property string artist: ""
    property string album: ""
    property string artUrl: ""
    readonly property var cava: QtObject {
        property int refs: 0
        readonly property int bars: 24
        readonly property var values: new Array(24).fill(0)
    }
}
