pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/stats.js" as Stats

// GPU load (0..1) and temperature of the card Stats.pickGpu chooses, once a second while something holds a
// ServiceRef on it. The cards are looked up the first time it is held (`detecting` until that, and the name
// lookup, are done); `available` is false when none reports gpu_busy_percent. `temperature` is in °C, -1 when
// unknown.
Singleton {
    id: root

    property int refs: 0
    property string name: ""
    property real percentage: 0
    property real temperature: -1
    property bool detecting: true
    property bool available: false

    // The chosen card's device directory and hwmon directory; "" until picked.
    property string device: ""
    property string hwmon: ""
    property bool searched: false

    onRefsChanged: {
        if (refs <= 0)
            percentage = 0;
        else if (!searched) {
            searched = true;
            finder.running = true;
        }
    }

    function pick(text: string): void {
        const cards = text.split("\n").filter(l => l !== "").map(l => {
            const f = l.split("\t");
            return {
                device: f[0],
                busyOk: f[1] === "1",
                vram: Number(f[2]) || 0,
                slot: f[3] ?? "",
                hwmon: f[4] ?? ""
            };
        });
        const i = Stats.pickGpu(cards);
        if (i < 0) {
            detecting = false;
            return;
        }
        device = cards[i].device;
        hwmon = cards[i].hwmon;
        if (cards[i].slot === "") {
            name = "GPU";
            finish();
            return;
        }
        namer.command = ["lspci", "-mm", "-s", cards[i].slot];
        namer.running = true;
    }

    // The name lookup ended (lspci ran, failed or is not installed): the card is used under a generic name when
    // no line came through. Safe to call again after the output was read.
    function namerDone(): void {
        if (!detecting)
            return;
        if (name === "")
            name = "GPU";
        finish();
    }

    function finish(): void {
        available = true;
        detecting = false;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.refs > 0 && root.available
        triggeredOnStart: true
        onTriggered: {
            busy.reload();
            if (root.hwmon !== "")
                temp.reload();
        }
    }

    FileView {
        id: busy

        path: root.device !== "" ? `${root.device}/gpu_busy_percent` : ""
        onLoaded: root.percentage = Math.min(1, Math.max(0, (Number(text().trim()) || 0) / 100))
    }

    FileView {
        id: temp

        path: root.hwmon !== "" ? `${root.hwmon}/temp1_input` : ""
        onLoaded: root.temperature = Stats.parseTemp(text())
        onLoadFailed: root.temperature = -1
    }

    // One line per card, tab separated: device directory, 1 if it reports gpu_busy_percent, VRAM bytes, PCI slot,
    // hwmon directory.
    Process {
        id: finder

        command: ["sh", "-c", 'for d in /sys/class/drm/card*/device; do [ -d "$d" ] || continue; b=0; [ -r "$d/gpu_busy_percent" ] && b=1; v=$(cat "$d/mem_info_vram_total" 2>/dev/null || echo 0); s=$(sed -n "s/^PCI_SLOT_NAME=//p" "$d/uevent" 2>/dev/null); h=$(ls -d "$d"/hwmon/hwmon* 2>/dev/null | head -n 1); printf "%s\\t%s\\t%s\\t%s\\t%s\\n" "$d" "$b" "$v" "$s" "$h"; done']
        stdout: StdioCollector {
            onStreamFinished: root.pick(text)
        }
    }

    Process {
        id: namer

        // Without lspci the process never produces output; its end (or a failed start) finishes the detection.
        onExited: root.namerDone()
        onRunningChanged: {
            if (!running)
                root.namerDone();
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root.name = Stats.parseLspciName(text.split("\n")[0]) || "GPU";
                root.finish();
            }
        }
    }
}
