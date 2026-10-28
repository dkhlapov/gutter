pragma Singleton

import QtQuick
import Quickshell

// Stand-in for services/Tray.qml in the pills check: two items without a menu. `items` is writable so the
// check can hand the row a fresh array.
Singleton {
    property var items: [item("one"), item("two")]
    readonly property bool available: true

    function item(id: string): var {
        return {
            id: id,
            title: id,
            tooltipTitle: "",
            tooltipDescription: "",
            icon: "",
            onlyMenu: false,
            hasMenu: false,
            menu: null,
            activate: () => {},
            secondaryActivate: () => {}
        };
    }

    function name(item: var): string {
        return item.title;
    }

    function iconSource(item: var): string {
        return "";
    }

    function iconFallback(item: var): string {
        return "";
    }
}
