pragma Singleton

import QtQuick
import Quickshell
import qs.settings
import "../lib/notifications.js" as NotifLib
import "../lib/pillState.js" as StateLib

Singleton {
    id: root

    property string openScreen: ""
    property string section: Settings.sections[0]

    // The screen is locked, or the dry-run preview is up: the same rule as Notifications.screenLocked (one lib
    // function; the singleton itself cannot be read here, Notifications uses PillControl). The panel then stays off
    // the notifications, which show message bodies.
    readonly property bool screenLocked: !NotifLib.bubblesAllowed(Lock.locked, Lock.preview)

    function openOn(screen: string, requested: string): void {
        const landing = StateLib.landing(requested, section, Settings.sections, screenLocked);
        if (landing === null)
            return;
        section = landing;
        openScreen = screen;
    }

    onScreenLockedChanged: {
        if (openScreen !== "" && StateLib.closeOnLock(section, screenLocked))
            close();
    }

    function close(): void {
        openScreen = "";
    }

    function toggle(screen: string, requested: string): void {
        if (openScreen === screen)
            close();
        else
            openOn(screen, requested);
    }

    function shift(delta: int): void {
        const next = StateLib.shifted(section, Settings.sections, delta, screenLocked);
        if (next !== null)
            section = next;
    }

    Connections {
        target: Settings

        function onSectionsChanged(): void {
            const landing = StateLib.landing("", root.section, Settings.sections, root.screenLocked);
            if (landing !== null)
                root.section = landing;
        }
    }
}
