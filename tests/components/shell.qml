//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
import QtQuick
import QtTest
import Quickshell
import qs.bar
import qs.components
import qs.theme
import "lib/workspaces.js" as WorkspaceLib

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
        expect(area.grabOffset === undefined && area.wheelRest === undefined
            && slide.grabOffset === undefined && slide.wheelRest === undefined, "the slider's grab and wheel state is public");

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

        // A drag from off the handle's centre keeps the grip: the value follows the cursor's travel, not its position.
        shell.moves = [];
        pointer.mousePress(slide, centre + 5, 11);
        pointer.mouseMove(slide, centre + 25, 11);
        pointer.mouseRelease(slide, centre + 25, 11);
        const dragged = slide.value + 20 / slide.travel;
        expect(shell.moves.length === 2 && Math.abs(shell.moves[0] - slide.value) < 1e-9
            && Math.abs(shell.moves[1] - dragged) < 1e-9, "a drag from off the handle's centre loses its grip: " + JSON.stringify(shell.moves));
    }

    // The workspace bar's cells and their app icons are updated in place when the workspaces change: the same items
    // stay, only their content moves (a rebuild would flash the bar and drop a hover).
    function cellItems() {
        const out = [];
        const walk = item => {
            if (item.tabWidth !== undefined && item.cell !== undefined)
                out.push(item);
            for (const child of item.children)
                walk(child);
        };
        walk(wsBar);
        return out;
    }

    function appIcons(cellItem) {
        const out = [];
        const walk = item => {
            if (item.appId !== undefined)
                out.push(item);
            for (const child of item.children)
                walk(child);
        };
        walk(cellItem);
        return out;
    }

    function workspaceBar() {
        const cell = (id, apps, state) => ({ id, label: String(id), state, accent: "sun", apps });
        wsBar.cells = [cell(1, ["foot"], "occupied"), cell(2, [], "empty"), cell(-98, ["a", "b"], "active")];
        const before = cellItems();
        const foot = appIcons(before[0]);
        expect(foot.length === 1 && foot[0].appId === "foot", "a box draws an icon per app: " + foot.length);
        expect(before.length === 3, "the bar draws a box per cell: " + before.length);

        // The same workspaces with a window more on the first and a new state on the second.
        wsBar.cells = [cell(1, ["foot", "firefox"], "occupied"), cell(2, [], "urgent"), cell(-98, ["a", "b"], "active")];
        const after = cellItems();
        expect(after.length === 3 && after.every((c, i) => c === before[i]), "a change rebuilds the bar's boxes");
        const icons = appIcons(after[0]);
        expect(icons.length === 2 && icons[0] === foot[0] && icons[1].appId === "firefox", "a window opened rebuilds the box's icons");
        expect(after[1].cell.state === "urgent", "a box does not follow its cell: " + after[1].cell.state);
        expect(after[0].summary.apps.length === 2, "a box does not show a window opened: " + after[0].summary.apps.length);

        // A special workspace closing drops its box and the others stay.
        wsBar.cells = [cell(1, ["foot", "firefox"], "occupied"), cell(2, [], "urgent")];
        const fewer = cellItems();
        expect(fewer.length === 2 && fewer[0] === before[0] && fewer[1] === before[1], "a closed workspace rebuilds the other boxes: " + fewer.length);
    }

    // The same against a real ListModel, which hands objects back with their keys in another order: a list that
    // has not changed sets no row.
    function syncReal() {
        let changed = 0;
        realModel.dataChanged.connect(() => changed++);
        const cell = (id, state) => ({ id, label: String(id), state, accent: "sun", apps: ["foot"] });
        WorkspaceLib.syncList(realModel, [cell(1, "empty"), cell(2, "active")], "cell");
        const filled = changed;
        WorkspaceLib.syncList(realModel, [cell(1, "empty"), cell(2, "active")], "cell");
        expect(changed === filled, "an unchanged list sets rows of a real ListModel: " + (changed - filled));
        WorkspaceLib.syncList(realModel, [cell(1, "empty"), cell(2, "urgent")], "cell");
        expect(changed === filled + 1 && realModel.get(1).cell.state === "urgent", "a changed row is not set alone: " + (changed - filled));
    }

    // A wheel turn of `delta` (120 is a notch); the steps it made.
    function wheelSteps(delta) {
        shell.steps = 0;
        pointer.mouseWheel(slide, 60, 11, 0, delta);
        return shell.steps;
    }

    // Hi-res wheels send fractions of a notch: they add up to whole steps, and turning the other way drops what was
    // left over, so a reversal never jumps (the remainder is the slider's own state, lib/wheel.js).
    function wheelRemainder() {
        expect(wheelSteps(30) === 0, "30 of a notch steps");
        expect(wheelSteps(90) === 1, "30 and 90 do not make a step");
        expect(wheelSteps(100) === 0, "100 of a notch steps");
        expect(wheelSteps(-30) === 0, "reversing steps");
        expect(wheelSteps(-90) === -1, "the old remainder was not dropped on reversal, or -30 and -90 do not make a step");
        expect(wheelSteps(-20) === 0, "the remainder after a step was kept as a whole notch");
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

        ListModel {
            id: realModel

            dynamicRoles: true
        }

        WorkspaceBar {
            id: wsBar

            x: 150
            y: 100
            visible: false
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
                shell.wheelRemainder();
                shell.workspaceBar();
                shell.syncReal();
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
