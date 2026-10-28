import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.theme
import "../../lib/glyphs.js" as Glyphs
import "../../lib/pillState.js" as PillState
import "../../lib/tools.js" as ToolsLib

// "timer": icon, progress bar, time left (dimmed while paused). "stopwatch": icon and elapsed time.
// "timerDone" is a speech bubble: a ringing alarm, TIME'S UP! and the duration, until the panel opens.
RowLayout {
    id: root

    required property string kind
    readonly property bool bubble: PillState.isBubble(kind)
    readonly property bool paused: kind === "timer" && Timers.timer.state === "paused"
    readonly property string accent: kind === "timerDone" ? "coral" : kind === "stopwatch" ? "magenta" : paused ? "navy" : "teal"

    spacing: Theme.gap

    IconPlate {
        id: plate

        accent: root.accent
        icon: Glyphs.glyph(root.kind === "timerDone" ? "alarm" : root.kind === "stopwatch" ? "timer_play" : root.paused ? "timer_pause" : "timer")

        // The alarm rings: a short back-and-forth every second.
        SequentialAnimation {
            running: root.kind === "timerDone" && root.visible
            loops: Animation.Infinite
            alwaysRunToEnd: true

            NumberAnimation {
                target: plate.glyph
                property: "rotation"
                to: 14
                duration: 120
            }
            NumberAnimation {
                target: plate.glyph
                property: "rotation"
                to: -14
                duration: 160
            }
            NumberAnimation {
                target: plate.glyph
                property: "rotation"
                to: 0
                duration: 120
            }
            PauseAnimation {
                duration: 600
            }
        }
    }

    LevelBar {
        Layout.preferredWidth: 120
        visible: root.kind === "timer"
        accent: root.accent
        value: Timers.timerFraction
    }

    InkText {
        Layout.minimumWidth: root.kind === "stopwatch" ? 76 : 52
        visible: !root.bubble
        horizontalAlignment: Text.AlignRight
        text: root.kind === "stopwatch" ? ToolsLib.stopwatchClock(Timers.stopwatchElapsed) : ToolsLib.clock(Timers.timerLeft)
        font.bold: true
        font.pixelSize: Theme.textSize
        // Paused is dimmed text, not a different colour.
        opacity: root.paused ? 0.55 : 1
    }

    ColumnLayout {
        visible: root.bubble
        spacing: 2

        BubbleHeadline {
            text: "TIME'S UP!"
        }

        InkText {
            text: ToolsLib.spoken(Timers.timer.durationMs)
            opacity: 0.7
        }
    }
}
