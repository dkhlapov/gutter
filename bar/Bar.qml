pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.theme
import qs.services
import qs.components

// One monitor's bar at the top right: the tray, the status cells, the sun/moon cell and the power button, each in
// its own ink box at the pill's height, with the menus and tooltips they open below them. Fills its window; only
// the row of boxes and an open menu take input (see BarWindow).
Item {
    id: root

    required property ShellScreen screen

    readonly property string screenName: screen?.name ?? ""
    readonly property bool powerOpen: Power.menuScreen === screenName && screenName !== ""
    readonly property bool menuOpen: tray.menuVisible || powerOpen
    readonly property Item boxItem: box
    readonly property Item menuItem: tray.menuVisible ? tray.menuItem : powerOpen ? powerLoader.item as Item : null
    // The row's width with the room to its right, for the window.
    readonly property real needWidth: box.implicitWidth + Theme.pillTop

    // The cell whose tooltip shows, and the one the pointer rests on waiting for it.
    property Segment tipCell: null
    property Segment restingCell: null

    function closeMenus(): void {
        tray.openItem = null;
        if (powerOpen)
            Power.menuScreen = "";
    }

    // Called by a Segment with a tooltip as the pointer enters or leaves it: the tooltip shows after a short rest.
    function hoverTip(cell: Segment, on: bool): void {
        if (on) {
            restingCell = cell;
            tipCell = null;
            tipDelay.restart();
        } else {
            if (restingCell === cell) {
                restingCell = null;
                tipDelay.stop();
            }
            if (tipCell === cell)
                tipCell = null;
        }
    }

    // One menu at a time: a tray menu opening closes the power menu, and the other way round.
    Connections {
        target: tray

        function onMenuVisibleChanged(): void {
            if (tray.menuVisible && root.powerOpen)
                Power.menuScreen = "";
        }
    }
    onPowerOpenChanged: {
        if (powerOpen)
            tray.openItem = null;
    }

    Timer {
        id: tipDelay

        interval: 500
        onTriggered: root.tipCell = root.restingCell
    }

    // Each cell is its own ink box; the spacing leaves room for each box's shadow on its right.
    Row {
        id: box

        x: root.width - Theme.pillTop - width
        y: Theme.pillTop
        height: Theme.pillHeight
        spacing: Theme.pad

        TrayRow {
            id: tray

            host: root
        }

        StatusRow {
            host: root
            screenName: root.screenName
        }

        ThemeCell {
            tipHost: root
        }

        Segment {
            icon: "\u{f0425}" // md-power
            accent: "coral"
            down: root.powerOpen
            onClicked: Power.toggleMenu(root.screenName)
        }
    }

    // A tray item's, a status cell's or the sun/moon cell's tooltip, under its cell and kept inside the bar's right
    // margin.
    Tip {
        id: tip

        readonly property var info: root.tipCell?.tip ?? null
        readonly property real cellX: root.tipCell ? root.tipCell.mapToItem(root, 0, 0).x + root.tipCell.width / 2 : 0

        visible: info !== null && !root.menuOpen
        title: info?.title ?? ""
        body: info?.body ?? ""
        x: Math.max(0, Math.min(cellX - width / 2, root.width - Theme.pillTop - width))
        y: box.y + box.height + Theme.gap
        z: 3
    }

    Loader {
        id: powerLoader

        active: root.powerOpen
        z: 2
        sourceComponent: PowerMenu {
            x: root.width - Theme.pillTop - width
            y: box.y + box.height + Theme.gap
            onDismissed: Power.menuScreen = ""
        }
    }
}
