pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/shelf.js" as ShelfLib

// Files held on the shelf, saved to ~/.local/state/gutter/shelf.json. The shelf keeps references, not copies:
// a held file that disappears stays listed as missing until it is removed.
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/gutter`
    property var state: ShelfLib.empty()
    // { path: { size, dir } } for the paths that exist; refreshed by stat.
    property var info: ({})
    property bool loaded: false
    // A drag from another window is over the pill / a tile of the shelf is being dragged out.
    property bool dropping: false
    property bool dragging: false
    readonly property var items: state.items
    readonly property var summary: ShelfLib.summary(state, info)

    // Accepts the URLs of a drop; returns how many files were new or moved to the front.
    function addUrls(urls): int {
        const paths = ShelfLib.pathsFromUrls(urls);
        if (paths.length === 0)
            return 0;
        state = ShelfLib.add(state, paths, Date.now());
        save.restart();
        refresh();
        return paths.length;
    }

    function addPath(path: string): int {
        return addUrls([ShelfLib.fileUrl(path)]);
    }

    function remove(path: string): void {
        state = ShelfLib.remove(state, path);
        save.restart();
    }

    function clear(): void {
        state = ShelfLib.empty();
        save.restart();
    }

    function open(path: string): void {
        Quickshell.execDetached(["xdg-open", path]);
    }

    function reveal(path: string): void {
        Quickshell.execDetached(["xdg-open", ShelfLib.dirName(path)]);
    }

    function refresh(): void {
        if (root.items.length === 0) {
            info = {};
            return;
        }
        stat.run(["stat", "-L", "--printf=%n\\t%s\\t%F\\n", "--"].concat(root.items.map(i => i.path)));
    }

    FileView {
        id: file

        path: `${root.dir}/shelf.json`
        atomicWrites: true
        onLoaded: {
            const parsed = ShelfLib.parse(text());
            if (parsed)
                root.state = parsed;
            else
                console.warn("gutter: shelf.json is not valid, starting empty (the file is kept until the next change)");
            root.loaded = true;
            root.refresh();
        }
        onLoadFailed: err => {
            if (err !== FileViewError.FileNotFound)
                console.warn("gutter: cannot read shelf.json, error", err);
            root.loaded = true;
        }
    }

    // stat exits 1 when some paths are missing but still prints the others.
    QueuedProcess {
        id: stat

        onFinished: text => root.info = ShelfLib.parseStat(text)
    }

    Process {
        id: mkdir

        command: ["mkdir", "-p", root.dir]
        onExited: file.setText(JSON.stringify(root.state, null, 2) + "\n")
    }

    // Changes before the first load finishes would overwrite the saved shelf; they wait for it.
    Timer {
        id: save

        interval: 300
        onTriggered: {
            if (!root.loaded) {
                restart();
                return;
            }
            mkdir.running = true;
        }
    }
}
