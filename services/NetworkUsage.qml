pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/stats.js" as Stats

// Network throughput (bytes per second) from /proc/net/dev, once a second while something holds a ServiceRef on
// it. The buffers hold the last `historyLength` speeds, oldest first; they restart from empty when sampling
// resumes after a pause.
Singleton {
    id: root

    readonly property int historyLength: 60
    readonly property int sampleInterval: 1000

    property int refs: 0
    property real downloadSpeed: 0
    property real uploadSpeed: 0
    property var downloadBuffer: []
    property var uploadBuffer: []

    // The last good sample and when it was taken; null until one is read, and after a failed read.
    property var previous: null
    property real previousAt: 0

    onRefsChanged: {
        if (refs > 0)
            return;
        previous = null;
        downloadSpeed = 0;
        uploadSpeed = 0;
        downloadBuffer = [];
        uploadBuffer = [];
    }

    Timer {
        interval: root.sampleInterval
        repeat: true
        running: root.refs > 0
        triggeredOnStart: true
        onTriggered: netdev.reload()
    }

    FileView {
        id: netdev

        path: "/proc/net/dev"
        onLoaded: {
            const now = Date.now();
            const cur = Stats.parseNetDev(text());
            const s = Stats.netSpeed(root.previous, cur, (now - root.previousAt) / 1000);
            root.previous = cur;
            root.previousAt = now;
            root.downloadSpeed = s.down;
            root.uploadSpeed = s.up;
            root.downloadBuffer = Stats.pushSample(root.downloadBuffer, s.down, root.historyLength);
            root.uploadBuffer = Stats.pushSample(root.uploadBuffer, s.up, root.historyLength);
        }
        onLoadFailed: root.previous = null
    }
}
