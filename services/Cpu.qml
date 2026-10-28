pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/stats.js" as Stats

// CPU load (0..1) from /proc/stat deltas, once a second while something holds a ServiceRef on it. The model
// name and the temperature sensor (the k10temp or coretemp hwmon) are looked up the first time it is held.
// `temperature` is in °C, -1 when there is no sensor.
Singleton {
    id: root

    property int refs: 0
    property string name: ""
    property real percentage: 0
    property real temperature: -1

    // The last good /proc/stat sample; null until one is read, and after a failed read or a pause.
    property var previous: null
    // The sensor's hwmon directory; "" until found, and when there is none.
    property string sensor: ""
    property bool searched: false

    onRefsChanged: {
        if (refs <= 0) {
            previous = null;
            percentage = 0;
        } else if (!searched) {
            searched = true;
            finder.running = true;
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.refs > 0
        triggeredOnStart: true
        onTriggered: {
            stat.reload();
            if (root.sensor !== "")
                temp.reload();
        }
    }

    FileView {
        id: stat

        path: "/proc/stat"
        onLoaded: {
            const cur = Stats.parseCpuStat(text());
            root.percentage = Stats.cpuFraction(root.previous, cur);
            root.previous = cur;
        }
        onLoadFailed: root.previous = null
    }

    FileView {
        id: temp

        path: root.sensor !== "" ? `${root.sensor}/temp1_input` : ""
        onLoaded: root.temperature = Stats.parseTemp(text())
        onLoadFailed: root.temperature = -1
    }

    // The model name, read once.
    FileView {
        path: root.name === "" && root.refs > 0 ? "/proc/cpuinfo" : ""
        onLoaded: root.name = Stats.parseCpuModel(text())
    }

    Process {
        id: finder

        command: ["sh", "-c", 'for d in /sys/class/hwmon/hwmon*; do case "$(cat "$d/name" 2>/dev/null)" in k10temp|coretemp) echo "$d"; break;; esac; done']
        stdout: StdioCollector {
            onStreamFinished: root.sensor = text.trim()
        }
    }
}
