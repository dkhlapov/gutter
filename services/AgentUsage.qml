pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/agentUsage.js" as UsageLib
import "../lib/activities.js" as ActLib
import "../lib/shelf.js" as ShelfLib

// Claude Code usage: API-price value and tokens from the transcripts (scripts/agent-usage.py, re-run every
// 10 s while an agent works, every minute otherwise) and plan limits from two sources, the newer reading
// winning: Anthropic's usage endpoint (scripts/claude-limits.py, every few minutes, backing off on errors; it
// works without the CLI) and the status-line bridge (scripts/agent-statusline.sh, CLI sessions only).
// Created at start-up (shell.qml) so the near-limit pill works without the tab.
Singleton {
    id: root

    readonly property string script: ShelfLib.pathFromUrl(Qt.resolvedUrl("../scripts/agent-usage.py")) ?? ""
    readonly property string fetchScript: ShelfLib.pathFromUrl(Qt.resolvedUrl("../scripts/claude-limits.py")) ?? ""
    readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/gutter`
    property var data: null
    property var bridgeFile: null
    property var apiFile: null
    readonly property var limitsFile: UsageLib.newest(bridgeFile, apiFile)
    // Usage requests that failed in a row, and the server's Retry-After for the last one (s).
    property int fetchFailures: 0
    property int retryAfter: 0
    // Why the last request failed ("unavailable" without a usable login, "network", an HTTP status, ...); empty
    // before the first run and after a good one.
    property string limitsReason: ""
    property bool warned: false
    // scripts/smoke.sh runs against the real HOME and must not send the login anywhere or write state.
    readonly property bool smoke: Quickshell.env("GUTTER_SMOKE") === "1"
    // Both halves of a run are recorded, since its exit and its output can arrive in either order.
    property bool parsedOk: true
    property int exitCode: 0
    readonly property bool failed: !parsedOk || exitCode !== 0
    readonly property var limits: UsageLib.limits(limitsFile, Agents.now)
    // Highest % seen per window and reset time, so each threshold alerts once per window.
    property var alerted: ({})
    property bool seeded: false
    property var alert: null

    function refresh(): void {
        if (!proc.running)
            proc.running = true;
    }

    // The first limits seen after start-up only seed `alerted`; a window first seen later is new.
    onLimitsFileChanged: {
        if (!limitsFile)
            return;
        const l = UsageLib.limits(limitsFile, Date.now());
        const rl = limitsFile.rate_limits;
        const wins = [];
        for (const [name, w, raw] of [["Session", l.session, rl?.five_hour], ["Week", l.week, rl?.seven_day]])
            if (w && !w.renewed)
                wins.push({ key: `${name}:${raw?.resets_at ?? 0}`, name: name, pct: w.pct, resetsIn: w.resetsIn });
        const r = UsageLib.limitAlerts(alerted, wins, !seeded);
        alerted = r.seen;
        seeded = true;
        // Several at once: the last (the week) wins, as it is the harder limit.
        const w = wins.filter((_, i) => r.hits[i] > 0).pop();
        if (w) {
            alert = { window: w.name, pct: Math.round(w.pct), resetsIn: w.resetsIn };
            Activities.show("agentLimit", ActLib.PRIORITY.agentLimit, 8000, "agents");
        }
    }

    Process {
        id: proc

        command: ["python3", root.script]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.data = JSON.parse(text);
                    root.parsedOk = true;
                } catch (e) {
                    root.parsedOk = false;
                }
            }
        }
        onExited: code => root.exitCode = code
    }

    // The usage endpoint. Silent on failure (no network, a token that expired, a changed reply): the bridge's
    // reading or "No recent data" stands in, and the interval grows. One console warning per start-up.
    Process {
        id: fetcher

        command: ["python3", root.fetchScript]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null;
                try {
                    r = JSON.parse(text);
                } catch (e) {}
                if (r?.ok) {
                    root.fetchFailures = 0;
                    root.limitsReason = "";
                    root.retryAfter = 0;
                    return;
                }
                root.fetchFailures += 1;
                root.limitsReason = String(r?.reason ?? "");
                root.retryAfter = r?.retryAfter ?? 0;
                if (!root.warned && r?.reason !== "unavailable") {
                    root.warned = true;
                    console.warn(`AgentUsage: plan limits request failed (${r?.reason ?? "no reply"}); retrying later`);
                }
            }
        }
        onExited: fetchTimer.restart()
    }

    Component.onCompleted: fetcher.running = !smoke

    Timer {
        id: fetchTimer

        repeat: false
        interval: UsageLib.fetchDelay(root.fetchFailures, root.retryAfter)
        onTriggered: {
            if (!root.smoke && !fetcher.running)
                fetcher.running = true;
        }
    }

    FileView {
        path: `${root.stateDir}/claude-limits.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.bridgeFile = JSON.parse(text());
            } catch (e) {}
        }
        onLoadFailed: root.bridgeFile = null
    }

    FileView {
        path: `${root.stateDir}/claude-limits-api.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.apiFile = JSON.parse(text());
            } catch (e) {}
        }
        onLoadFailed: root.apiFile = null
    }

    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: Agents.counts.working > 0 ? 10000 : 60000
        onTriggered: root.refresh()
    }
}
