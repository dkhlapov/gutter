pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../lib/tray.js" as TrayLib

// The status-notifier items apps put in the tray, minus the ones that ask to stay hidden (Passive).
// Quickshell does not say whether a watcher exists, so `available` is "at least one item is showing": the tray
// row hides itself when it is false.
Singleton {
    id: root

    readonly property var items: SystemTray.items.values.filter(i => i.status !== Status.Passive)
    readonly property bool available: items.length > 0

    // What to call `item`: its title, else its tooltip title, else the name of the desktop entry its icon is named
    // after, else "" (never the id: it is something like DISCORD_STATUS_ICON_1). Reading the entry list makes a
    // binding look again once the entries have loaded.
    function name(item: var): string {
        const loaded = DesktopEntries.applications.values.length > 0;
        const icon = TrayLib.iconName(item.icon ?? "");
        const entry = loaded && icon !== "" ? DesktopEntries.heuristicLookup(icon)?.name : "";
        return TrayLib.firstName([item.title, item.tooltipTitle, entry]);
    }

    // What to hand an IconImage for `item`. An icon named "<file>?path=<dir>" (Steam's) is the app's own private
    // file: "<file>.png" in that directory first, since the icon theme's same-named icon can be a recolourable SVG
    // that Qt draws as a solid black blob; `iconFallback` is the theme lookup, then the bare file, for when that
    // file is not there.
    function iconSource(item: var): string {
        const icon = item.icon;
        const parts = TrayLib.iconParts(icon);
        if (parts === null)
            return icon;
        return Qt.resolvedUrl(`${parts.path}/${parts.name}.png`);
    }

    function iconFallback(item: var): string {
        const parts = TrayLib.iconParts(item.icon);
        if (parts === null)
            return item.icon;
        const themed = Quickshell.iconPath(parts.name, true);
        return themed ? themed : Qt.resolvedUrl(`${parts.path}/${parts.name}`);
    }
}
