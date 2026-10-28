pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/stats.js" as Stats

// Mounted filesystems from `df -kP`, every 10 s while something holds a ServiceRef on it. `disks` rows are
// { mount, used, total, free, perc, hasRoot } (sizes in kiB, perc 0..1); `primaryDisk` is the one mounted at "/".
Singleton {
    id: root

    property int refs: 0
    property var disks: []
    readonly property var primaryDisk: disks.find(d => d.hasRoot) ?? null

    Timer {
        interval: 10000
        repeat: true
        running: root.refs > 0
        triggeredOnStart: true
        onTriggered: {
            if (!df.running)
                df.running = true;
        }
    }

    Process {
        id: df

        command: ["df", "-kP"]
        stdout: StdioCollector {
            onStreamFinished: root.disks = Stats.parseDf(text)
        }
    }
}
