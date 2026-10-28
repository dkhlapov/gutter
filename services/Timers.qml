pragma Singleton

import QtQuick
import Quickshell
import "../lib/tools.js" as ToolsLib
import "../lib/activities.js" as ActLib

// One countdown timer and one stopwatch, kept while the panel is closed (not across restarts).
Singleton {
    id: root

    property var timer: ToolsLib.timerIdle()
    property var stopwatch: ToolsLib.stopwatchIdle()
    property real now: Date.now()

    readonly property real timerLeft: ToolsLib.timerLeft(timer, now)
    readonly property real timerFraction: ToolsLib.timerFraction(timer, now)
    readonly property real stopwatchElapsed: ToolsLib.stopwatchElapsed(stopwatch, now)
    readonly property bool timerActive: timer.state === "running" || timer.state === "paused"

    function startTimer(minutes: real): void {
        Activities.hide("timerDone");
        now = Date.now();
        timer = ToolsLib.timerStart(minutes * 60000, now);
    }

    function toggleTimer(): void {
        now = Date.now();
        timer = ToolsLib.timerToggle(timer, now);
    }

    function addMinute(): void {
        Activities.hide("timerDone");
        now = Date.now();
        timer = ToolsLib.timerAdd(timer, 60000, now);
    }

    function resetTimer(): void {
        Activities.hide("timerDone");
        timer = ToolsLib.timerIdle();
    }

    function toggleStopwatch(): void {
        now = Date.now();
        stopwatch = ToolsLib.stopwatchToggle(stopwatch, now);
    }

    function lap(): void {
        now = Date.now();
        stopwatch = ToolsLib.stopwatchLap(stopwatch, now);
    }

    function resetStopwatch(): void {
        stopwatch = ToolsLib.stopwatchIdle();
    }

    function finish(): void {
        Activities.show("timerDone", ActLib.PRIORITY.timerDone, 60000, "tools");
        Quickshell.execDetached(["pw-play", "/usr/share/sounds/freedesktop/stereo/complete.oga"]);
    }

    // Reads timer.state, not timerActive: that binding may not have caught up with the change yet.
    onTimerChanged: {
        if (timer.state === "running" || timer.state === "paused")
            Activities.show("timer", ActLib.PRIORITY.timer, 0, "tools");
        else
            Activities.hide("timer");
    }

    onStopwatchChanged: {
        if (stopwatch.running)
            Activities.show("stopwatch", ActLib.PRIORITY.stopwatch, 0, "tools");
        else
            Activities.hide("stopwatch");
    }

    Timer {
        running: root.timer.state === "running" || root.stopwatch.running
        repeat: true
        // Tenths on the stopwatch need a faster tick than the timer's whole seconds.
        interval: root.stopwatch.running ? 100 : 250
        onTriggered: {
            root.now = Date.now();
            const next = ToolsLib.timerCheck(root.timer, root.now);
            if (next !== root.timer) {
                root.timer = next;
                root.finish();
            }
        }
    }

    // Opening the panel acknowledges the alert.
    Connections {
        target: PillControl

        function onOpenScreenChanged(): void {
            if (PillControl.openScreen !== "")
                Activities.hide("timerDone");
        }
    }
}
