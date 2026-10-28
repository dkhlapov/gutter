pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/stats.js" as Stats

// RAM in use, from /proc/meminfo, once a second while something holds a ServiceRef on it. Sizes in kiB.
Singleton {
    id: root

    property int refs: 0
    property real used: 0
    property real total: 0
    property real percentage: 0

    Timer {
        interval: 1000
        repeat: true
        running: root.refs > 0
        triggeredOnStart: true
        onTriggered: meminfo.reload()
    }

    FileView {
        id: meminfo

        path: "/proc/meminfo"
        onLoaded: {
            const m = Stats.parseMeminfo(text());
            root.used = m.used;
            root.total = m.total;
            root.percentage = m.percentage;
        }
    }
}
