pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/ddc.js" as DdcLib
import "../lib/activities.js" as ActLib

Singleton {
    id: root

    property var buses: ({})
    property bool detected: false
    property var levels: ({})
    property var writes: ({})
    // Monitors set while the running read was in flight; that read is older than their value.
    property var writtenDuringRead: ({})
    property var writers: ({})
    property bool warned: false
    readonly property real focusedLevel: levels[Hypr.focusedScreenName] ?? -1

    function hasDdc(name: string): bool {
        return buses[name] !== undefined;
    }

    // Slider path: no HUD.
    function setLevel(name: string, value: real): void {
        if (!hasDdc(name))
            return;
        const next = DdcLib.step(value, 0);
        levels = Object.assign({}, levels, { [name]: next });
        if (reader.running)
            writtenDuringRead[name] = true;
        write(name, DdcLib.request(writes, name, next));
    }

    // Brightness keys: the focused monitor, always with the HUD.
    function change(delta: real): void {
        const name = Hypr.focusedScreenName;
        if (!hasDdc(name)) {
            if (!warned)
                console.warn(`gutter: no DDC/CI brightness control for ${name}`);
            warned = true;
            return;
        }
        setLevel(name, DdcLib.step(levels[name] ?? 0.5, delta));
        Activities.show("brightness", ActLib.PRIORITY.hud, 1500, "");
    }

    // Re-reads one monitor (the panel does this when it opens); values being written are kept.
    function refresh(name: string): void {
        if (hasDdc(name) && !reader.running)
            read([buses[name]]);
    }

    function read(busList: var): void {
        const cmd = DdcLib.readCommand(busList);
        if (!cmd)
            return;
        writtenDuringRead = {};
        reader.command = ["sh", "-c", cmd];
        reader.running = true;
    }

    Process {
        running: true
        command: ["ddcutil", "detect", "--brief"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const d of DdcLib.parseDetect(text))
                    map[d.connector] = d.bus;
                root.buses = map;
                root.detected = true;
                root.read(Object.values(map));
            }
        }
    }

    Process {
        id: reader

        stdout: StdioCollector {
            onStreamFinished: {
                const byBus = DdcLib.parseLevels(text);
                const read = {};
                for (const name in root.buses)
                    if (byBus[root.buses[name]] !== undefined)
                        read[name] = byBus[root.buses[name]];
                root.levels = DdcLib.mergeRead(root.levels, read, root.writes, root.writtenDuringRead);
            }
        }
    }

    // One ddcutil write per monitor at a time; values requested meanwhile collapse to the latest.
    function write(name: string, r: var): void {
        writes = r.state;
        if (r.start === null)
            return;
        if (!writers[name])
            writers[name] = writerComponent.createObject(root, { name });
        const w = writers[name];
        w.command = ["ddcutil", "-b", buses[name], "setvcp", "10", String(Math.round(r.start * 100))];
        w.running = true;
    }

    Component {
        id: writerComponent

        Process {
            required property string name

            onExited: root.write(name, DdcLib.finished(root.writes, name))
        }
    }
}
