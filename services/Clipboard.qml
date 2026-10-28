pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/clipboard.js" as ClipLib
import "../lib/shelf.js" as ShelfLib

// Clipboard history. scripts/clipboard-watch.sh (wl-paste --watch) prints one line per copy; the list is
// saved to ~/.local/state/gutter/clipboard/history.json (directory mode 700, with the copied images).
// Created at start-up (shell.qml) so copies are collected while the panel is closed.
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/gutter/clipboard`
    readonly property string script: ShelfLib.pathFromUrl(Qt.resolvedUrl("../scripts/clipboard-watch.sh")) ?? ""
    property var items: []
    property bool loaded: false
    // history.json is being read again (see the restart timer).
    property bool reloading: false
    // wl-paste is not installed.
    property bool missing: false
    property string selectedId: ""
    // The item the Clipboard tab shows large: the one last hovered, else the newest.
    readonly property var selected: items.find(i => i.id === selectedId) ?? items[0] ?? null
    property real now: Date.now()

    function capture(entry: var): void {
        if (!entry)
            return;
        apply(ClipLib.add(items, entry, Date.now()));
    }

    function togglePin(id: string): void {
        items = ClipLib.togglePin(items, id);
        save.restart();
    }

    function remove(id: string): void {
        apply(ClipLib.remove(items, id));
    }

    function clear(): void {
        apply(ClipLib.clear(items));
    }

    // Puts an item back on the clipboard; the watcher then moves it to the top of the list.
    function copy(item: var): void {
        if (!item)
            return;
        if (item.kind === "image")
            Quickshell.execDetached(["sh", "-c", "exec wl-copy --type image/png < \"$1\"", "sh", item.path]);
        else
            Quickshell.execDetached(["wl-copy", "--", item.text]);
    }

    function apply(result: var): void {
        items = result.items;
        for (const gone of result.evicted)
            if (gone.kind === "image" && gone.path.indexOf(dir + "/") === 0)
                Quickshell.execDetached(["rm", "-f", gone.path]);
        save.restart();
    }

    FileView {
        id: file

        path: `${root.dir}/history.json`
        atomicWrites: true
        printErrors: false
        onLoaded: {
            const parsed = ClipLib.parse(text());
            if (parsed)
                root.items = parsed;
            else
                console.warn("gutter: clipboard history.json is not valid JSON, starting empty (the file is kept until the next copy)");
            root.loaded = true;
            root.reloading = false;
        }
        onLoadFailed: {
            root.loaded = true;
            root.reloading = false;
        }
    }

    // Started once the saved list is loaded, so the first copy cannot overwrite it. After an exit it waits for
    // the restart timer (waiting), which is why running is a binding and never assigned.
    Process {
        id: watcher

        property int lastCode: 0
        property bool waiting: false

        command: [root.script, root.dir]
        running: root.loaded && !root.reloading && !root.missing && !waiting
        stdout: SplitParser {
            onRead: line => root.capture(ClipLib.parseLine(line))
        }
        onExited: code => {
            lastCode = code;
            if (code === 127) {
                root.missing = true;
            } else {
                waiting = true;
                restart.start();
            }
        }
    }

    Timer {
        id: restart

        // 75: another shell holds the watcher (or took it over); look again later in case it is gone.
        interval: watcher.lastCode === 75 ? 30000 : 3000
        onTriggered: {
            if (watcher.lastCode === 75) {
                // The other shell has been saving the history meanwhile: start from its list, not from ours.
                root.reloading = true;
                file.reload();
            }
            watcher.waiting = false;
        }
    }

    // Not before the saved list is loaded, and not while it is read again: a stale list would overwrite the
    // file. An edit made in the few milliseconds of a reload is dropped by it.
    Timer {
        id: save

        interval: 400
        onTriggered: {
            if (!root.loaded || root.reloading) {
                save.restart(); // not restart(): that id is the watcher's timer
                return;
            }
            file.setText(JSON.stringify(ClipLib.serialize(root.items), null, 2) + "\n");
        }
    }

    Timer {
        running: root.items.length > 0
        repeat: true
        interval: 30000
        onTriggered: root.now = Date.now()
    }
}
