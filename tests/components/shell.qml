//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
import QtQuick
import QtTest
import Quickshell
import qs.components
import qs.theme

// The shared components check (scripts/components.sh). InkBox and SpeechBubble size from their visible content
// (a hidden box still measures its content), and InkSlider keeps its grab and wheel state private, steps on a
// vertical wheel, lets a horizontal one through to what lies beneath, and a press on the handle keeps its offset.
ShellRoot {
    id: shell

    property var failures: []
    property int checks: 0
    property int belowWheels: 0
    property var moves: []
    property int steps: 0

    function expect(ok, what) {
        checks++;
        if (!ok)
            failures.push(what);
    }

    function find(item, matches) {
        if (matches(item))
            return item;
        for (const child of item.children) {
            const found = find(child, matches);
            if (found)
                return found;
        }
        return null;
    }

    function sizing() {
        const edge = 2 * Theme.inkWidth;
        expect(shownBox.implicitWidth === 40 + edge && shownBox.implicitHeight === 20 + edge,
            "a box counts a hidden child: " + shownBox.implicitWidth + " x " + shownBox.implicitHeight);
        expect(hiddenBox.implicitWidth === 40 + edge && hiddenBox.implicitHeight === 20 + edge,
            "a hidden box collapses: " + hiddenBox.implicitWidth + " x " + hiddenBox.implicitHeight);
        expect(shownBubble.implicitWidth === 40 + 2 * shownBubble.padX,
            "a bubble counts a hidden child: " + shownBubble.implicitWidth);
        expect(shownBubble.implicitHeight === shownBubble.tailHeight + 20 + 2 * shownBubble.padY,
            "a bubble counts a hidden child's height: " + shownBubble.implicitHeight);
        expect(hiddenBubble.implicitWidth === 40 + 2 * hiddenBubble.padX,
            "a hidden bubble collapses: " + hiddenBubble.implicitWidth);
    }

    function slider() {
        const area = find(slide, i => i.cursorShape !== undefined);
        expect(area !== null, "no input area in the slider");
        expect(area.grabOffset === undefined && area.wheelRest === undefined, "the slider's grab and wheel state is public");

        // A horizontal scroll is released to what lies beneath; a vertical one steps and is kept.
        pointer.mouseWheel(slide, 60, 11, -120, 0);
        expect(shell.belowWheels === 1, "a horizontal wheel does not pass through the slider");
        expect(shell.steps === 0, "a horizontal wheel steps the slider");
        pointer.mouseWheel(slide, 60, 11, 0, 120);
        expect(shell.belowWheels === 1, "a vertical wheel passes through the slider");
        expect(shell.steps === 1, "a vertical wheel does not step the slider");

        // A press on the handle off its centre does not make the handle jump; a press elsewhere jumps to the cursor.
        const centre = slide.value * slide.travel + slide.handleShort / 2;
        shell.moves = [];
        pointer.mousePress(slide, centre + 5, 11);
        pointer.mouseRelease(slide, centre + 5, 11);
        expect(shell.moves.length === 1 && Math.abs(shell.moves[0] - slide.value) < 1e-9,
            "a press on the handle moves the value: " + JSON.stringify(shell.moves));
        shell.moves = [];
        pointer.mousePress(slide, slide.handleShort / 2, 11);
        pointer.mouseRelease(slide, slide.handleShort / 2, 11);
        expect(shell.moves.length === 1 && shell.moves[0] === 0, "a press off the handle does not jump to the cursor: " + JSON.stringify(shell.moves));
    }

    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 300
        color: "white"

        InkBox {
            id: shownBox

            x: 10
            y: 10

            Item {
                implicitWidth: 40
                implicitHeight: 20
            }

            Item {
                implicitWidth: 300
                implicitHeight: 300
                visible: false
            }
        }

        InkBox {
            id: hiddenBox

            x: 100
            y: 10
            visible: false

            Item {
                implicitWidth: 40
                implicitHeight: 20
            }
        }

        SpeechBubble {
            id: shownBubble

            x: 10
            y: 60

            Item {
                implicitWidth: 40
                implicitHeight: 20
            }

            Item {
                implicitWidth: 300
                implicitHeight: 300
                visible: false
            }
        }

        SpeechBubble {
            id: hiddenBubble

            x: 200
            y: 60
            visible: false

            Item {
                implicitWidth: 40
                implicitHeight: 20
            }
        }

        // What a slider sits over: a horizontal scroll it lets through reaches this.
        MouseArea {
            x: 10
            y: 200
            width: 120
            height: 22
            acceptedButtons: Qt.NoButton
            onWheel: wheel => shell.belowWheels++
        }

        InkSlider {
            id: slide

            x: 10
            y: 200
            width: 120
            value: 0.5
            onMoved: v => shell.moves = [...shell.moves, v]
            onStepped: n => shell.steps += n
        }

        TestCase {
            id: pointer

            when: false
        }

        Timer {
            interval: 400
            running: true
            onTriggered: {
                shell.sizing();
                shell.slider();
                if (shell.failures.length) {
                    for (const f of shell.failures)
                        console.log("components: FAIL: " + f);
                } else {
                    console.log("components: OK (" + shell.checks + " checks)");
                }
                Qt.quit();
            }
        }
    }
}
