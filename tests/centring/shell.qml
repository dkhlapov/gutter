//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import qs.pill.sections
import qs.pill.sections.overview
import qs.services
import qs.theme

// The centring check (scripts/centring.sh): in the overview's media card and in the music section, the buttons of
// the transport (without their hard shadow) are centred on the progress bar above them, with and without the
// shuffle and repeat buttons.
ShellRoot {
    id: shell

    property var failures: []
    property int checks: 0

    // The first item under `item` (itself included) that `matches`.
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

    // Centre of `item` across the window, and the left and right edges of the group of buttons.
    function centreX(item) {
        return item.mapToItem(null, item.width / 2, 0).x;
    }

    function check(name, root) {
        const bar = find(root, i => i.thumbSize !== undefined);
        const transport = find(root, i => i.playSize !== undefined);
        if (!bar || !transport) {
            failures.push(name + ": no " + (bar ? "transport" : "progress bar"));
            return;
        }
        // The visible buttons: those of the group that are shown. The group's own width counts only these.
        const buttons = (transport.group ?? transport).children.filter(c => c.visible);
        const left = Math.min(...buttons.map(c => c.mapToItem(null, 0, 0).x));
        const right = Math.max(...buttons.map(c => c.mapToItem(null, c.width, 0).x));
        const off = (left + right) / 2 - centreX(bar);
        checks++;
        console.log("centring: " + name + ": " + buttons.length + " buttons, offset " + off.toFixed(2) + " px");
        if (Math.abs(off) > 0.5)
            failures.push(name + ": buttons are " + off.toFixed(2) + " px off the progress bar's centre");
    }

    FloatingWindow {
        id: win

        implicitWidth: 1000
        implicitHeight: 700
        color: "white"

        MediaHero {
            id: hero

            x: 20
            y: 20
            width: 420
            height: 260
        }

        MusicSection {
            id: music

            x: 20
            y: 300
            width: 960
            height: 380
        }

        Timer {
            interval: 600
            running: true
            onTriggered: {
                shell.check("overview", hero);
                for (const [shuffle, loop] of [[false, false], [true, false], [false, true], [true, true]]) {
                    Media.canShuffle = shuffle;
                    Media.canLoop = loop;
                    shell.check("music shuffle=" + shuffle + " repeat=" + loop, music);
                }
                if (shell.failures.length) {
                    for (const f of shell.failures)
                        console.log("centring: FAIL: " + f);
                } else {
                    console.log("centring: OK (" + shell.checks + " checks)");
                }
                Qt.quit();
            }
        }
    }
}
