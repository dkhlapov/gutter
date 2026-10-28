pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/cava.js" as CavaLib

// Audio bars for the visualiser: runs `cava` while something holds a ServiceRef on it and exposes its frames
// as `values` (`bars` numbers, 0..1). Without the binary, or if it exits, `available` goes false and the
// values stay zero (a warning is logged once); the next time `refs` goes 0 -> above 0 tries again.
Singleton {
    id: root

    property int refs: 0
    readonly property int bars: 24
    readonly property int framerate: 30
    property var values: CavaLib.parseFrame("", bars)
    property bool available: true

    readonly property string dir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/gutter`

    // cava died while held; stays until nothing holds the service any more.
    property bool failed: false
    property bool warned: false
    // A stop is in flight: the process is still alive, so a start waits for its exit.
    property bool stopping: false

    // A function, not a binding: onRefsChanged runs before bindings on `refs` are re-evaluated.
    function wanted(): bool {
        return refs > 0 && !failed;
    }

    onRefsChanged: {
        if (refs <= 0) {
            failed = false;
            values = CavaLib.parseFrame("", bars);
        }
        sync();
    }

    function sync(): void {
        if (wanted() && !proc.running && !stopping) {
            available = true;
            proc.running = true;
        } else if (!wanted() && proc.running && !stopping) {
            stopping = true;
            proc.running = false;
        }
    }

    Process {
        id: proc

        // The config goes next to the agents log in the runtime dir; the shell writes it and becomes cava.
        command: ["sh", "-c", 'mkdir -p "$1" && printf "%s\\n" "$2" > "$1/cava.conf" && exec cava -p "$1/cava.conf"', "sh", root.dir, CavaLib.config(root.bars, root.framerate)]

        stdout: SplitParser {
            onRead: line => {
                if (root.wanted() && !root.stopping)
                    root.values = CavaLib.parseFrame(line, root.bars);
            }
        }

        onExited: (code, status) => {
            if (root.stopping) {
                root.stopping = false;
                root.sync();
                return;
            }
            root.failed = true;
            root.available = false;
            root.values = CavaLib.parseFrame("", root.bars);
            if (!root.warned) {
                root.warned = true;
                console.warn(code === 127 ? "gutter: cava: not installed, the visualiser stays flat" : `gutter: cava: exited with code ${code}, the visualiser stays flat until it is shown again`);
            }
        }
    }
}
