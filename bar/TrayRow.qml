pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.theme
import qs.services
import qs.components
import "../lib/tray.js" as TrayLib

// One bar cell per tray item. Left click opens the item's menu, right click shows the app (activates it), middle
// click activates it secondarily; see TrayLib.clickAction for items without a menu or with only one. The menu is a caption box below the bar, drawn in `host`
// (the bar's whole surface); Escape, an entry, a click outside the bar or another menu opening closes it.
// Hovering an item shows its tooltip (see Bar). The row takes no width while the tray has no items.
Row {
    id: root

    spacing: Theme.pad

    // The bar: menus are drawn in it and kept inside it, tooltips are shown by it.
    required property Item host

    // The item whose menu is open, or null.
    property var openItem: null
    // Where the open item's cell starts in `host`: the menu's left edge lines up with it.
    property real openX: 0
    // The open item is still in the tray.
    readonly property bool menuShown: openItem !== null && Tray.items.indexOf(openItem) >= 0
    // The menu has something to show: a menu without entries (or one still loading) draws no box.
    readonly property bool menuVisible: menuShown && TrayLib.hasEntries(opener.children?.values ?? [])
    readonly property Item menuItem: menuLoader.item as Item

    visible: Tray.available

    function toggleMenu(item: var, cell: Item): void {
        openItem = openItem === item && menuVisible ? null : item;
        openX = cell.mapToItem(host, 0, 0).x;
    }

    // An item that leaves the tray takes its menu with it: if the same object came back, nothing pops open.
    onMenuShownChanged: {
        if (!menuShown)
            openItem = null;
    }

    // A menu still empty once it has had time to load is given up on: left open, it would pop up by itself when
    // entries arrive later, and the next click would reopen it instead of toggling.
    Timer {
        running: root.menuShown && !root.menuVisible
        interval: 500
        onTriggered: root.openItem = null
    }

    QsMenuOpener {
        id: opener

        menu: root.menuShown ? root.openItem.menu : null
    }

    Repeater {
        // Diffed by item: a status change that leaves the other items alone keeps their cells.
        model: ScriptModel {
            values: Tray.items
        }

        Segment {
            id: cell

            required property var modelData

            accessibleName: Tray.name(cell.modelData)
            contentWidth: Theme.appIconSize
            accent: Theme.roleAccent.active
            down: root.menuVisible && root.openItem === cell.modelData
            tip: TrayLib.tooltip(Tray.name(modelData), modelData.tooltipTitle, modelData.tooltipDescription)
            tipHost: root.host

            TrayIcon {
                anchors.centerIn: parent
                size: Theme.appIconSize
                source: Tray.iconSource(cell.modelData)
                fallback: Tray.iconFallback(cell.modelData)
            }

            onClicked: event => {
                const item = cell.modelData;
                const name = event.button === Qt.MiddleButton ? "middle" : event.button === Qt.RightButton ? "right" : "left";
                const action = TrayLib.clickAction(name, item.onlyMenu, item.hasMenu);
                if (action === "menu")
                    root.toggleMenu(item, cell);
                else {
                    // Calling the item closes whatever menu is open.
                    root.openItem = null;
                    if (action === "secondary")
                        item.secondaryActivate();
                    else
                        item.activate();
                }
            }
        }
    }

    Loader {
        id: menuLoader

        parent: root.host
        z: 2
        active: root.menuVisible
        sourceComponent: InkMenu {
            readonly property real menuY: Theme.pillTop + Theme.pillHeight + Theme.gap
            readonly property var place: TrayLib.placeMenu(root.openX, menuY, implicitWidth, implicitHeight, root.host.width, root.host.height, Theme.pillTop)

            menu: root.openItem?.menu ?? null
            title: root.openItem ? Tray.name(root.openItem) : ""
            keyline: true
            x: place.x
            y: place.y
            width: implicitWidth
            height: place.height
            onDismissed: root.openItem = null
        }
    }
}
