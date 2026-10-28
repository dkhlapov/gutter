pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/agents.js" as AgentsLib
import "../lib/activities.js" as ActLib

// Claude Code sessions, read from the log that scripts/agent-hook.sh appends to. Created at start-up
// (shell.qml) so "needs you" and "finished" show in the pill without opening the Agents tab.
Singleton {
    id: root

    readonly property string logPath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/gutter/agents.jsonl`
    readonly property string settingsPath: `${Quickshell.env("CLAUDE_CONFIG_DIR") || Quickshell.env("HOME") + "/.claude"}/settings.json`
    property var events: []
    property var items: []
    readonly property var counts: AgentsLib.counts(items)
    property real now: Date.now()
    property bool hooksInstalled: false
    property bool statusLineInstalled: false
    // Stop events up to this time are history: only later ones raise the "finished" alert.
    property real seenUntil: Date.now()
    property var lastDone: null

    function refresh(): void {
        now = Date.now();
        items = AgentsLib.list(AgentsLib.reduce(events, now));
    }

    FileView {
        id: log

        path: root.logPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.events = AgentsLib.parseLines(text());
            const finished = AgentsLib.finishedSince(root.events, root.seenUntil);
            if (finished.length > 0) {
                root.seenUntil = finished[finished.length - 1].t;
                // The newest long task of the batch: a quick Stop after it doesn't hide it.
                const long = finished.filter(f => f.took >= AgentsLib.DONE_MIN_MS);
                if (long.length > 0) {
                    const f = long[long.length - 1];
                    root.lastDone = { project: AgentsLib.project(f.cwd), prompt: f.prompt, took: f.took };
                    Activities.show("agentDone", ActLib.PRIORITY.agentDone, AgentsLib.DONE_ALERT_MS, "agents");
                }
            }
            root.refresh();
        }
        onLoadFailed: {
            root.events = [];
            root.refresh();
        }
    }

    // Only to show the install hints on the Agents tab.
    FileView {
        path: root.settingsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.hooksInstalled = text().indexOf("agent-hook.sh") !== -1;
            root.statusLineInstalled = text().indexOf("agent-statusline.sh") !== -1;
        }
        onLoadFailed: {
            root.hooksInstalled = false;
            root.statusLineInstalled = false;
        }
    }

    // Elapsed times tick while anything runs; no need to re-read the log for that.
    Timer {
        running: root.counts.working + root.counts.waiting > 0
        repeat: true
        interval: 1000
        onTriggered: root.refresh()
    }

    // The log is replaced (not appended) when the hook trims it, which a file watch can miss.
    Timer {
        running: true
        repeat: true
        interval: 5000
        onTriggered: log.reload()
    }
}
