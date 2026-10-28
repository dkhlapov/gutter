pragma Singleton

import QtQuick
import Quickshell
import qs.settings
import "../lib/worldclock.js" as ClockLib

// UTC offsets of the configured world clocks, read with `date` (refreshed just after every quarter hour, when DST switches happen).
Singleton {
    id: root

    readonly property var clocks: Settings.worldClocks
    property var offsets: []
    property var localOffset: null
    property var warned: ({})

    function refresh(): void {
        proc.run(ClockLib.command(clocks.map(c => c.tz)), clocks);
    }

    onClocksChanged: refresh()

    QueuedProcess {
        id: proc

        // Output for a list that has since changed is left to the run that list queued. Compared by content: an array
        // read from a var property is not the same object each time.
        onFinished: (text, asked) => {
            if (JSON.stringify(asked) !== JSON.stringify(root.clocks))
                return;
            const r = ClockLib.parseOffsets(text, asked.length);
            root.localOffset = r.local;
            root.offsets = r.zones;
            r.zones.forEach((o, i) => {
                const tz = asked[i].tz;
                if (o === null && !root.warned[tz]) {
                    console.warn(`gutter: unknown time zone ${tz}`);
                    root.warned[tz] = true;
                }
            });
        }
    }

    Timer {
        running: true
        triggeredOnStart: true
        interval: ClockLib.msToNextRefresh(Date.now())
        onTriggered: {
            root.refresh();
            interval = ClockLib.msToNextRefresh(Date.now());
            restart();
        }
    }
}
