//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import qs.bar
import qs.services
import qs.theme

// The pills check (scripts/pills.sh): every pill of the top bars is Theme.pillHeight high, and the ones that hold
// only a glyph or an icon are squares. It builds the top-right bar (tray, status, theme and power cells) with
// every status cell shown, and workspace cells in each state: empty, active, special, with one app, with more
// apps than fit. It also checks that the tray's cells survive a fresh array of the same items.
ShellRoot {
    id: shell

    property var failures: []
    property int checks: 0

    function walk(item, visit) {
        visit(item);
        for (const child of item.children)
            walk(child, visit);
    }

    function check(name, item, square) {
        const w = item.width, h = item.height;
        checks++;
        console.log("pills: " + name + ": " + w.toFixed(1) + " x " + h.toFixed(1));
        if (h !== Theme.pillHeight)
            failures.push(name + ": " + h + " px high, not " + Theme.pillHeight);
        if (square && w !== h)
            failures.push(name + ": a square cell is " + w + " x " + h);
        if (!square && w <= h)
            failures.push(name + ": a cell with text or apps is no wider than high (" + w + " x " + h + ")");
        return item.mapToItem(null, 0, 0).y;
    }

    FloatingWindow {
        id: win

        implicitWidth: 1500
        implicitHeight: 260
        color: "white"

        Bar {
            id: bar

            width: 1500
            height: 140
            screen: Quickshell.screens[0]
        }

        Row {
            id: workspaces

            x: 14
            y: 150
            spacing: Theme.pad

            Repeater {
                model: [
                    { id: 1, label: "1", state: "empty", accent: "sun", apps: [] },
                    { id: 2, label: "2", state: "active", accent: "teal", apps: [] },
                    { id: 3, label: "3", state: "occupied", accent: "lime", apps: ["foot"] },
                    { id: 4, label: "4", state: "active", accent: "pink", apps: ["foot", "firefox"] },
                    { id: 5, label: "5", state: "urgent", accent: "coral", apps: ["a", "b", "c", "d", "e", "f"] },
                    { id: -98, label: "music", name: "special:music", state: "empty", accent: "magenta", apps: [] },
                    { id: -99, label: "term", name: "special:term", state: "occupied", accent: "magenta", apps: ["foot"] }
                ]

                WorkspaceCell {
                    required property var modelData

                    cell: modelData
                }
            }
        }

        Timer {
            interval: 800
            running: true
            onTriggered: {
                KbLayout.available = true;
                KbLayout.layout = "Swedish";
                const ys = [];
                const segments = [];
                const cells = [];
                shell.walk(win.contentItem, item => {
                    if (!item.visible)
                        return;
                    if (item.implicitContentWidth !== undefined)
                        segments.push(item);
                    else if (item.tabWidth !== undefined && item.cell !== undefined)
                        cells.push(item);
                });
                for (const s of segments)
                    ys.push(shell.check("cell " + (s.text || s.icon || "icon") + (s.text === "" ? " (glyph)" : ""), s, s.text === ""));
                if (segments.length < 8)
                    shell.failures.push("only " + segments.length + " top-right cells shown, expected 9 (2 tray, volume, mic, layout, network, Bluetooth, theme, power)");
                if (new Set(ys).size > 1)
                    shell.failures.push("the top-right cells are not on one line: " + ys.join(", "));

                const wsYs = [];
                for (const c of cells)
                    wsYs.push(shell.check("workspace " + c.cell.label, c, c.summary.apps.length === 0));
                if (cells.length !== 7)
                    shell.failures.push(cells.length + " workspace cells shown, expected 7");
                if (new Set(wsYs).size > 1)
                    shell.failures.push("the workspace cells are not on one line: " + wsYs.join(", "));

                // A status change in the tray gives the row a fresh array of the same items: their cells must stay.
                const trayCells = () => {
                    const found = [];
                    shell.walk(win.contentItem, item => {
                        if (item.modelData !== undefined && item.implicitContentWidth !== undefined)
                            found.push(item);
                    });
                    return found;
                };
                const before = trayCells();
                Tray.items = Tray.items.filter(() => true);
                const after = trayCells();
                shell.checks++;
                console.log("pills: tray cells after a fresh items array: " + before.length + " -> " + after.length);
                if (before.length !== 2 || after.length !== 2 || before.some((c, i) => c !== after[i]))
                    shell.failures.push("the tray's cells were rebuilt by a fresh array of the same items");

                if (shell.failures.length) {
                    for (const f of shell.failures)
                        console.log("pills: FAIL: " + f);
                } else {
                    console.log("pills: OK (" + shell.checks + " checks)");
                }
                Qt.quit();
            }
        }
    }
}
