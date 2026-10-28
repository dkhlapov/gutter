pragma Singleton

import QtQuick
import Quickshell
import "../lib/power.js" as PowerLib

// The power menu's actions: which ones logind allows (asked again each time the menu opens), and running one.
// With `dryRun` set (GUTTER_POWER_DRY_RUN=1 at start, or `gutter powerDryRun true` over IPC) an action is only
// logged, so the menu can be tried without locking, suspending or powering off the machine.
Singleton {
    id: root

    // logind's answers, { CanSuspend: "yes", ... }; empty until the first query returns.
    property var can: ({})
    readonly property var entries: PowerLib.entries(can)
    property bool dryRun: Quickshell.env("GUTTER_POWER_DRY_RUN") === "1"
    // The last action a dry run would have taken, for checks.
    property string lastDryRun: ""
    // The monitor whose bar shows the power menu, "" when it is closed. One menu at a time.
    property string menuScreen: ""

    function toggleMenu(screenName: string): void {
        menuScreen = menuScreen === screenName ? "" : screenName;
        if (menuScreen !== "")
            refresh();
    }

    function refresh(): void {
        query.run(PowerLib.canQuery(), null);
    }

    function run(id: string): void {
        const step = PowerLib.route(id, dryRun, Quickshell.env("XDG_SESSION_ID") ?? "");
        switch (step.act) {
        case "lock":
            // The lock is Gutter's own, not a command.
            Lock.request();
            break;
        case "exec":
            Quickshell.execDetached(step.command);
            break;
        case "log":
            lastDryRun = id;
            console.info(step.log);
            break;
        }
    }

    QueuedProcess {
        id: query

        onFinished: text => root.can = PowerLib.parseCan(text)
    }

    Component.onCompleted: refresh()
}
