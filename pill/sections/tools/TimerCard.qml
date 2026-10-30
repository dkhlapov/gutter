pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components
import "../../../lib/tools.js" as ToolsLib

// Timer | Stopwatch (the two tabs), digits inside a ring, presets or laps, and the controls.
CaptionBox {
    id: root

    // Opens on the stopwatch only when it is the one in use.
    property bool stopwatch: Timers.stopwatch.running && !Timers.timerActive
    readonly property bool done: Timers.timer.state === "done"
    readonly property bool running: stopwatch ? Timers.stopwatch.running : Timers.timer.state === "running"

    tabs: [
        {
            text: "Timer",
            accent: "pink"
        },
        {
            text: "Stopwatch",
            accent: "pink"
        }
    ]
    currentTab: stopwatch ? 1 : 0
    onTabClicked: index => root.stopwatch = index === 1

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.gap

        // Timer: time left, the ring empties. Stopwatch: elapsed, the ring sweeps once a minute.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Ring {
                anchors.centerIn: parent
                width: Math.min(140, parent.height)
                height: width
                thickness: 8
                animated: !root.stopwatch
                accent: root.done ? "lime" : "pink"
                value: root.stopwatch ? (Timers.stopwatchElapsed % 60000) / 60000 : root.done ? 1 : Timers.timerFraction

                Column {
                    anchors.centerIn: parent

                    InkText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.stopwatch ? ToolsLib.stopwatchClock(Timers.stopwatchElapsed) : root.done ? "Done" : ToolsLib.clock(Timers.timer.state === "idle" ? 0 : Timers.timerLeft)
                        font.pixelSize: root.stopwatch ? 18 : 26
                        font.bold: true
                    }

                    InkText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: text !== ""
                        text: root.stopwatch || Timers.timer.state === "idle" ? "" : `of ${ToolsLib.spoken(Timers.timer.durationMs)}`
                        color: Theme.textMuted
                    }
                }
            }
        }

        // Timer presets.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.rightMargin: Theme.shadowOffset
            visible: !root.stopwatch
            spacing: Theme.gap

            Repeater {
                model: ToolsLib.PRESETS

                delegate: InkButton {
                    required property int modelData

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    text: `${modelData}m`
                    checked: Timers.timer.durationMs === modelData * 60000 && Timers.timer.state !== "idle"
                    onClicked: Timers.startTimer(modelData)
                }
            }
        }

        // The two latest laps (lap number and lap time), or a hint before the first.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Theme.pillHeight
            Layout.rightMargin: Theme.shadowOffset
            visible: root.stopwatch
            spacing: Theme.gap

            InkText {
                Layout.fillWidth: true
                visible: Timers.stopwatch.laps.length === 0
                horizontalAlignment: Text.AlignHCenter
                text: "No laps yet"
                color: Theme.textMuted
            }

            Repeater {
                model: Timers.stopwatch.laps.slice(0, 2)

                delegate: InkBox {
                    id: lapChip

                    required property int index
                    required property real modelData
                    readonly property var laps: Timers.stopwatch.laps
                    readonly property real lapTime: modelData - (index + 1 < laps.length ? laps[index + 1] : 0)

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    shadow: false

                    InkText {
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 2 * Theme.gap)
                        elide: Text.ElideRight
                        text: `Lap ${lapChip.laps.length - lapChip.index}  ${ToolsLib.stopwatchClock(lapChip.lapTime)}`
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: false
            Layout.bottomMargin: Theme.shadowOffset
            spacing: 14

            InkButton {
                icon: "\u{f0709}"
                onClicked: root.stopwatch ? Timers.resetStopwatch() : Timers.resetTimer()
            }

            InkButton {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 46
                icon: root.running ? "\u{f03e4}" : "\u{f040a}"
                iconSize: 20
                accent: "pink"
                onClicked: {
                    if (root.stopwatch)
                        Timers.toggleStopwatch();
                    else if (Timers.timerActive)
                        Timers.toggleTimer();
                    else
                        Timers.startTimer(ToolsLib.PRESETS[1]);
                }
            }

            // +1 min on the timer, lap on the stopwatch.
            InkButton {
                icon: root.stopwatch ? "\u{f023b}" : "\u{f1ae2}"
                onClicked: root.stopwatch ? Timers.lap() : Timers.addMinute()
            }
        }
    }
}
