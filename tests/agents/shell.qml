//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import qs.components
import qs.pill
import "pill/sections"
import qs.theme
import "lib/pillState.js" as PillState

// The agents check (scripts/agents.sh): the Agents tab, in the room the open panel gives a section, with every
// card full. Each card's content must lie inside its ink box (below the tabs, inside the outline, and a little
// clear of the lower edge), the cards of a column must be equally tall, a list must show whole rows only, and the
// six cards must lie inside the section, none pushed out below it by another.
ShellRoot {
    id: shell

    property var failures: []
    property int checks: 0

    function cards(item, found) {
        if (item.tabs !== undefined && item.headroom !== undefined)
            found.push(item);
        for (const c of item.children)
            cards(c, found);
        return found;
    }

    // Text, outlined shapes and images paint; a bare Item (such as one that only holds a hidden lamp) does not.
    function paints(item) {
        return item.contentWidth !== undefined && item.elide !== undefined
            || item.border !== undefined && item.color !== undefined
            || item.source !== undefined;
    }

    function name(item) {
        const base = String(item).replace(/\(0x[0-9a-f]+.*$/, "").replace(/_QMLTYPE_\d+/, "");
        return typeof item.text === "string" ? `${base} "${item.text.slice(0, 24)}"` : base;
    }

    // Air kept under the content: a line touching the lower edge reads as cut off.
    readonly property real air: 6

    // A list shows whole rows: each is either inside it or entirely past it.
    function checkList(list, card, label) {
        for (const row of list.contentItem.children) {
            if (!row.visible || row.height <= 0)
                continue;
            const y = row.mapToItem(list, 0, 0).y;
            checks++;
            if (y < list.height - 0.5 && y + row.height > list.height + 0.5)
                failures.push(`${label}: a list row is cut off at ${y.toFixed(1)}+${row.height.toFixed(1)} in a list ${list.height.toFixed(1)} high`);
        }
    }

    // The tabs sit on the box's edge and are clipped at its width: a caption longer than the room is cut off.
    function checkTabs(item, card, label) {
        if (item.caption !== undefined && item.active !== undefined && item.accent !== undefined && item.width > 0) {
            const r = item.mapToItem(card, 0, 0, item.width, item.height);
            checks++;
            if (r.x + r.width > card.width + 0.5)
                failures.push(`${label}: the tab "${item.text}" ends at ${(r.x + r.width).toFixed(1)}, past its box ${card.width.toFixed(1)}`);
        }
        for (const c of item.children)
            checkTabs(c, card, label);
    }

    // The heatmap squares are 12 px: a border as thick as the ink lines (3 px) hides their colour, so theirs is a
    // hairline.
    function checkCells(item, label) {
        if (item.border !== undefined && item.color !== undefined && item.visible && Math.abs(item.width - 12) < 0.5 && Math.abs(item.height - 12) < 0.5) {
            checks++;
            if (item.border.width > 1)
                failures.push(`${label}: a heatmap square has a ${item.border.width} px border, 1 at most`);
        }
        for (const c of item.children)
            checkCells(c, label);
    }

    // Whether a rectangle (in the card's own coordinates) lies inside the card's room.
    function inside(r, card) {
        const ink = Theme.inkWidth;
        const e = 0.5;
        return r.x >= ink - e && r.y >= card.headroom + ink - e && r.x + r.width <= card.width - ink + e && r.y + r.height <= card.height - ink - air + e;
    }

    // Everything that paints under `item`, against the card's room.
    function walk(item, card, label) {
        if (!item.visible || item.opacity === 0)
            return;
        const scrolls = item.contentY !== undefined && item.clip && item.contentItem;
        if (item.width > 0 && item.height > 0 && (paints(item) || scrolls)) {
            const r = item.mapToItem(card, 0, 0, item.width, item.height);
            // A list scrolls what does not fit: what its clip cuts is not overflow. The list itself still has to
            // lie inside the box, or its last row runs over the border.
            for (let a = item.parent; a && a !== card; a = a.parent)
                if (a.clip && a.contentY !== undefined)
                    return;
            checks++;
            if (!inside(r, card))
                failures.push(`${label}: ${name(item)} at ${r.x.toFixed(1)},${r.y.toFixed(1)} ${r.width.toFixed(1)}x${r.height.toFixed(1)} outside its box ${card.width.toFixed(1)}x${card.height.toFixed(1)} (tabs ${card.headroom})`);
        }
        if (scrolls)
            checkList(item, card, label);
        for (const c of item.children)
            walk(c, card, label);
    }

    FloatingWindow {
        id: win

        implicitWidth: PillState.OPEN_W
        implicitHeight: PillState.OPEN_H
        color: "#808080"

        Item {
            id: host

            // The room a section gets in pill/Panel.qml.
            x: Theme.pad
            y: Theme.pad + Theme.pillHeight - Theme.inkWidth
            width: PillState.OPEN_W - 2 * (Theme.inkWidth + Theme.pad)
            height: PillState.OPEN_H - (Theme.pillHeight - Theme.inkWidth) - 2 * (Theme.inkWidth + Theme.pad)

            AgentsSection {
                id: section

                anchors.fill: parent
            }
        }

        Timer {
            interval: 1000
            running: true
            onTriggered: {
                const found = shell.cards(section, []);
                console.log(`agents: ${found.length} cards in ${host.width}x${host.height}`);
                if (found.length !== 6)
                    shell.failures.push(`${found.length} cards, expected 6`);
                // The two cards of a column are as tall as each other, and so are the three columns' cards.
                const heights = found.map(c => c.height);
                shell.checks++;
                if (Math.max(...heights) - Math.min(...heights) > 1.5)
                    shell.failures.push(`the cards are not equally tall: ${heights.map(h => h.toFixed(1)).join(", ")}`);
                for (const card of found) {
                    const label = card.tabs.map(t => t.text).join("/");
                    const r = card.mapToItem(host, 0, 0, card.width, card.height);
                    shell.checks++;
                    console.log(`agents: ${label}: ${r.x.toFixed(1)},${r.y.toFixed(1)} ${r.width.toFixed(1)}x${r.height.toFixed(1)}, content needs ${card.implicitHeight.toFixed(1)}`);
                    if (r.y < -0.5 || r.y + r.height > host.height + 0.5 || r.x < -0.5 || r.x + r.width > host.width + 0.5)
                        shell.failures.push(`${label}: card at ${r.x.toFixed(1)},${r.y.toFixed(1)} ${r.width.toFixed(1)}x${r.height.toFixed(1)} outside the section ${host.width}x${host.height}`);
                    shell.checkTabs(card, card, label);
                    if (label.startsWith("Activity"))
                        shell.checkCells(card, label);
                    for (let i = 0; i < card.content.length; i++)
                        shell.walk(card.content[i], card, label);
                }
                if (shell.failures.length) {
                    for (const f of shell.failures)
                        console.log("agents: FAIL: " + f);
                } else {
                    console.log(`agents: OK (${shell.checks} checks)`);
                }
                // AGENTS_SHOT=<file.png> also saves a picture of the tab.
                const shot = Quickshell.env("AGENTS_SHOT");
                if (shot)
                    host.grabToImage(result => {
                        result.saveToFile(shot);
                        Qt.quit();
                    });
                else
                    Qt.quit();
            }
        }
    }
}
