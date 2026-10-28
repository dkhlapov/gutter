//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
import QtQuick
import QtTest
import Quickshell
import qs.components
import qs.theme

// The scroll bar and caption check (scripts/scrollbar.sh). InkScrollBar is faded out at rest, shows while the pointer
// is over its list or the list has just scrolled and goes again, is absent when everything fits, keeps its thumb on
// the track for a ListView, a GridView and a list that grows upwards, scrolls the list when its thumb is dragged, its
// track pressed or the wheel turned over it (also when the pointer came to the strip first), and sits beside the rows
// without covering them or moving them while a list's height eases. A CaptionBox with one tab draws a caption that
// ignores clicks, one with two draws tabs that don't.
ShellRoot {
    id: shell

    readonly property int rowHeight: 30
    readonly property int maxRows: 8

    property var failures: []
    property int checks: 0
    property int clicks: 0
    property int pairClicks: 0
    property int easedWidthChanges: 0
    property real wheelFrom: 0

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

    function thumbOf(bar) {
        return find(bar, i => i.border !== undefined && i.width === bar.width);
    }

    // The thumb at the list's two ends, and dragging it there (scrollTo is what a pointer drag calls).
    function ends(bar, flick, name) {
        const thumb = thumbOf(bar);
        const grab = find(bar, i => i.scrollTo !== undefined);
        const last = flick.originY + flick.contentHeight - bar.viewLength;
        expect(bar.needed && thumb && grab, name + ": no bar, thumb or grab area");
        flick.contentY = flick.originY;
        expect(Math.abs(thumb.y) < 1, name + ": the thumb is off the track's start at the list's start");
        flick.contentY = last;
        expect(Math.abs(thumb.y + thumb.height - bar.height) < 1, name + ": the thumb is off the track's end at the list's end");
        flick.contentY = flick.originY;
        grab.scrollTo(bar.height);
        expect(Math.abs(flick.contentY - last) < 1, name + ": dragging the thumb to the end does not scroll to the end");
        grab.scrollTo(0);
        expect(Math.abs(flick.contentY - flick.originY) < 1, name + ": dragging the thumb to the start does not scroll to the start");
    }

    // Nothing has scrolled or been pointed at.
    function atRest() {
        expect(bar.opacity === 0 && !bar.shown, "the bar shows at rest");
        expect(bar.needed, "a long list has no bar");
        expect(!short.needed, "a list that fits has a bar");
        expect(shortBar.reserve === 0, "a list that fits gives up room for a bar");
        // Three rows up to seven: the height eases, the bar and the rows' width do not move.
        shell.easedWidthChanges = 0;
        eased.count = 7;
    }

    // The pointer is over the list, nothing has scrolled: the bar shows, and the wheel scrolls the list over its rows
    // and over the bar's strip.
    function hovering() {
        expect(bar.shown && bar.opacity > 0, "the bar does not fade in while the pointer is over the list");
        expect(shell.easedWidthChanges === 0, "the list's rows changed width while its height eased");
        pointer.mouseWheel(list, 50, 50, 0, -120);
    }

    // A wheel notch starts a glide: the list has moved a little later.
    function wheeled() {
        expect(list.contentY > 0, "the wheel over the rows does not scroll");
        list.cancelFlick();
        shell.wheelFrom = list.contentY;
        pointer.mouseWheel(bar, bar.width / 2, 50, 0, -120);
    }

    function wheeledOverBar() {
        expect(list.contentY > shell.wheelFrom, "the wheel over the bar does not scroll");
        list.cancelFlick();
        list.contentY = 0;
    }

    // The pointer left and the list has not scrolled for a while.
    function leftAlone() {
        expect(!bar.shown, "the bar stays after the pointer left");
        list.contentY = 50;
        expect(bar.shown, "the bar does not show after the list scrolled");
    }

    // Once the bar has faded in.
    function pointing() {
        const thumb = thumbOf(bar);
        // Pressing the track's middle puts the thumb's centre there, a press on the thumb keeps its grip.
        pointer.mouseClick(bar, bar.width / 2, bar.height / 2);
        expect(Math.abs(thumb.y + thumb.height / 2 - bar.height / 2) < 1, "a press on the track does not centre the thumb");
        list.contentY = 0;
        pointer.mousePress(bar, bar.width / 2, 2);
        pointer.mouseMove(bar, bar.width / 2, bar.height);
        pointer.mouseRelease(bar, bar.width / 2, bar.height);
        expect(Math.abs(list.contentY - (list.contentHeight - list.height)) < 1, "dragging the thumb with the pointer does not reach the end");

        expect(bar.x >= list.x + list.width, "the bar covers the list");
        expect(Math.abs(list.width - (rows.width - bar.reserve)) < 0.5, "the list is not narrowed by the bar's reserve");

        ends(bar, list, "list");
        ends(reversedBar, reversed, "list growing upwards");
        ends(gridBar, grid, "grid");
        list.contentY = 0;
    }

    // The pointer came to the strip without crossing the list: the faded bar takes it, shows, and the wheel scrolls.
    function reached() {
        expect(bar.shown && bar.opacity > 0, "the bar does not show when the pointer reaches the strip first");
        pointer.mouseWheel(bar, bar.width / 2, 50, 0, -120);
    }

    function reachedWheel() {
        expect(list.contentY > 0, "the wheel over the strip does not scroll when the pointer reached it first");
        list.cancelFlick();
        list.contentY = 0;
    }

    function captions() {
        const lone = find(single, i => i.caption !== undefined);
        const first = find(pair, i => i.caption !== undefined);
        expect(single.captioned && lone.caption, "a lone tab is not a caption");
        expect(!pair.captioned && !first.caption, "one of two tabs is a caption");
        expect(single.headroom === pair.headroom, "a caption moves the box");
        expect(lone.height === Theme.pillHeight - 2 * Theme.inkWidth, "a caption is not at the resting height");
        expect(first.height > lone.height, "the current tab is not raised over a caption");
        const area = i => find(i, c => c.cursorShape !== undefined);
        pointer.mouseClick(lone, lone.width / 2, lone.height / 2);
        pointer.mouseClick(first, first.width / 2, first.height / 2);
        expect(shell.clicks === 0, "a click on a caption is a tab click");
        expect(shell.pairClicks === 1, "a click on a tab is not a tab click");
        expect(!area(lone).enabled, "a caption takes clicks");
        expect(area(first).enabled, "a tab does not take clicks");
    }

    FloatingWindow {
        implicitWidth: 700
        implicitHeight: 560
        color: "white"

        Item {
            id: rows

            x: 20
            y: 20
            width: 200
            height: 150

            ListView {
                id: list

                anchors.fill: parent
                anchors.rightMargin: bar.reserve
                clip: true
                model: 40
                delegate: Rectangle {
                    required property int index

                    width: list.width
                    height: shell.rowHeight
                    color: index % 2 ? "lightgray" : "white"
                }
            }

            InkScrollBar {
                id: bar

                anchors.top: list.top
                anchors.bottom: list.bottom
                anchors.left: list.right
                anchors.leftMargin: gap
                target: list
            }
        }

        Item {
            x: 240
            y: 20
            width: 200
            height: 150

            ListView {
                id: short

                property alias needed: shortBar.needed

                anchors.fill: parent
                anchors.rightMargin: shortBar.reserve
                model: 3
                delegate: Rectangle {
                    required property int index

                    width: short.width
                    height: shell.rowHeight
                    color: "lightgray"
                }
            }

            InkScrollBar {
                id: shortBar

                anchors.top: short.top
                anchors.bottom: short.bottom
                anchors.left: short.right
                anchors.leftMargin: gap
                target: short
            }
        }

        // The launcher's list: its height eases to the rows it shows, which fit, so the bar says the final height.
        Item {
            x: 460
            y: 20
            width: 200
            height: 250

            ListView {
                id: eased

                property int count: 3

                x: 0
                width: parent.width - easedBar.reserve
                height: Math.min(count, shell.maxRows) * shell.rowHeight
                clip: true
                model: count
                onWidthChanged: shell.easedWidthChanges++
                delegate: Rectangle {
                    required property int index

                    width: eased.width
                    height: shell.rowHeight
                    color: "lightgray"
                }

                Behavior on height {
                    Anim {
                        duration: 400
                    }
                }
            }

            InkScrollBar {
                id: easedBar

                anchors.top: eased.top
                anchors.bottom: eased.bottom
                anchors.left: eased.right
                anchors.leftMargin: gap
                viewLength: Math.min(eased.count, shell.maxRows) * shell.rowHeight
                target: eased
            }
        }

        CaptionBox {
            id: single

            x: 20
            y: 190
            width: 200
            height: 150
            tabs: [{ text: "One", accent: "sun" }]
            currentTab: 0
            onTabClicked: shell.clicks++
        }

        CaptionBox {
            id: pair

            x: 240
            y: 190
            width: 200
            height: 150
            tabs: [{ text: "One", accent: "sun" }, { text: "Two", accent: "teal" }]
            currentTab: 0
            onTabClicked: shell.pairClicks++
        }

        // A list that grows upwards (its origin is not zero) and a grid.
        Item {
            x: 20
            y: 360
            width: 200
            height: 150

            ListView {
                id: reversed

                anchors.fill: parent
                anchors.rightMargin: reversedBar.reserve
                clip: true
                verticalLayoutDirection: ListView.BottomToTop
                model: 40
                delegate: Rectangle {
                    required property int index

                    width: reversed.width
                    height: shell.rowHeight
                    color: index % 2 ? "lightgray" : "white"
                }
            }

            InkScrollBar {
                id: reversedBar

                anchors.top: reversed.top
                anchors.bottom: reversed.bottom
                anchors.left: reversed.right
                anchors.leftMargin: gap
                target: reversed
            }
        }

        Item {
            x: 240
            y: 360
            width: 200
            height: 150

            GridView {
                id: grid

                anchors.fill: parent
                anchors.rightMargin: gridBar.reserve
                clip: true
                cellWidth: Math.floor(width / 2)
                cellHeight: 60
                model: 60
                delegate: Rectangle {
                    required property int index

                    width: grid.cellWidth
                    height: grid.cellHeight
                    color: index % 2 ? "lightgray" : "white"
                }
            }

            InkScrollBar {
                id: gridBar

                anchors.top: grid.top
                anchors.bottom: grid.bottom
                anchors.left: grid.right
                anchors.leftMargin: gap
                target: grid
            }
        }

        TestCase {
            id: pointer

            when: false
        }

        // The steps, each after the last has had time to show: at rest, pointer over the list, a wheel notch over the
        // rows, a wheel notch over the bar's strip, pointer away for longer than the bar lingers, the list scrolled
        // and the bar faded in, the pointer away again, the pointer reaching the strip without crossing the list,
        // and a wheel notch there.
        Timer {
            id: step

            property int n: 0
            readonly property var steps: [
                { wait: 300, run: () => shell.atRest() },
                { wait: 20, run: () => pointer.mouseMove(list, 50, 50) },
                { wait: 500, run: () => shell.hovering() },
                { wait: 300, run: () => shell.wheeled() },
                { wait: 300, run: () => shell.wheeledOverBar() },
                { wait: 20, run: () => pointer.mouseMove(single, 100, 100) },
                { wait: 1300, run: () => shell.leftAlone() },
                { wait: 400, run: () => {
                        shell.pointing();
                        shell.captions();
                        pointer.mouseMove(single, 100, 100);
                    } },
                { wait: 1500, run: () => {
                        shell.expect(!bar.shown, "the bar stays after the list stopped");
                        pointer.mouseMove(bar, bar.width / 2, 50);
                    } },
                { wait: 400, run: () => shell.reached() },
                { wait: 300, run: () => shell.reachedWheel() }
            ]

            interval: steps[0].wait
            running: true
            repeat: true
            onTriggered: {
                steps[n].run();
                n++;
                if (n < steps.length) {
                    interval = steps[n].wait;
                    return;
                }
                running = false;
                if (shell.failures.length) {
                    for (const f of shell.failures)
                        console.log("scrollbar: FAIL: " + f);
                } else {
                    console.log("scrollbar: OK (" + shell.checks + " checks)");
                }
                Qt.quit();
            }
        }
    }
}
