pragma Singleton

import QtQuick
import Quickshell
import "../lib/activities.js" as ActLib

Singleton {
    id: root

    property var entries: []
    property int seq: 0
    readonly property var current: ActLib.top(entries, Date.now())

    function show(id: string, priority: int, durationMs: int, section: string): void {
        seq++;
        entries = ActLib.upsert(entries, {
            id,
            priority,
            expiresAt: durationMs > 0 ? Date.now() + durationMs : null,
            section,
            seq
        });
        schedule();
    }

    function hide(id: string): void {
        entries = ActLib.remove(entries, id);
        schedule();
    }

    function schedule(): void {
        const next = ActLib.nextExpiry(entries, Date.now());
        if (next === null) {
            expiry.stop();
            return;
        }
        expiry.interval = Math.max(1, next - Date.now());
        expiry.restart();
    }

    Timer {
        id: expiry

        onTriggered: {
            root.entries = ActLib.prune(root.entries, Date.now());
            root.schedule();
        }
    }
}
