pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/wallpaper.js" as WallpaperLib

// The wallpaper path, read from $XDG_STATE_HOME/gutter/wallpaper (one absolute image path as text) and
// reloaded live. Without the file (a first run) there is no wallpaper: an empty path means "no usable wallpaper",
// and the view shows its paper fill until `gutter wall set` writes one.
// The state folder is created at start and the watch is attached again once it exists: a FileView whose folder
// was missing when it opened never sees the file appear later, so a first `gutter wall set` would otherwise
// need a restart.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    // "" when neither XDG_STATE_HOME nor HOME is set: there is then no state file to read.
    readonly property string stateDir: WallpaperLib.stateDir(Quickshell.env("XDG_STATE_HOME"), root.home)
    readonly property string stateFile: stateDir ? `${stateDir}/wallpaper` : ""

    // Absolute path of the image to show, or "".
    property string path: ""

    // The first read of the file has happened; it applies at once, later ones may wait for `confirm`.
    property bool firstRead: false
    // What the last non-empty problem was, so a watch that fires again with the same text stays quiet.
    property string lastWarning: ""
    // True while a re-read is under way to confirm an empty or unparsable change.
    property bool rechecking: false

    function warnOnce(message: string): void {
        if (message === lastWarning)
            return;
        lastWarning = message;
        if (message !== "")
            console.warn(`gutter: wallpaper: ${message}`);
    }

    // text is null when the file does not exist. A read that is not the first and gives nothing
    // usable (an external write truncates before it writes) is held back until `confirm` re-reads it,
    // so a half-written file neither flashes the paper fill nor logs a warning.
    function apply(text: var, confirmed: bool): void {
        const parsed = WallpaperLib.parsePath(text, root.home);
        if (parsed === "" && firstRead && !confirmed) {
            confirm.restart();
            return;
        }
        firstRead = true;
        confirm.stop();
        root.path = parsed;
        if (parsed !== "")
            warnOnce("");
        else if (text === null)
            warnOnce(`${root.stateFile} is missing, using the paper fill`);
        else
            warnOnce(`${root.stateFile} has no absolute path, using the paper fill`);
    }

    // Makes sure the state folder exists, then opens the file again if it could not be read before:
    // a watch set up while the folder was missing never attaches. Path "" first makes FileView drop it.
    Process {
        id: startMkdir

        command: ["mkdir", "-p", "--", root.stateDir]
        onExited: code => {
            if (code !== 0) {
                console.warn(`gutter: wallpaper: cannot create ${root.stateDir}, a wallpaper set later needs a restart`);
                return;
            }
            if (!file.loaded) {
                file.path = "";
                file.path = root.stateFile;
            }
        }
    }

    Component.onCompleted: {
        if (stateDir === "")
            console.warn("gutter: wallpaper: neither XDG_STATE_HOME nor HOME is set, using the paper fill");
        else
            startMkdir.running = true;
    }

    Timer {
        id: confirm

        interval: 150
        onTriggered: {
            root.rechecking = true;
            file.reload();
        }
    }

    FileView {
        id: file

        path: root.stateFile
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onSaveFailed: err => console.warn(`gutter: wallpaper: cannot write ${root.stateFile} (${err})`)
        onLoaded: {
            const confirmed = root.rechecking;
            root.rechecking = false;
            root.apply(text(), confirmed);
        }
        onLoadFailed: err => {
            const confirmed = root.rechecking;
            root.rechecking = false;
            if (err === FileViewError.FileNotFound) {
                root.apply(null, confirmed);
                return;
            }
            // Unreadable is not missing: show the paper fill, and the next read applies at once.
            root.firstRead = true;
            confirm.stop();
            root.path = "";
            root.warnOnce(`cannot read ${root.stateFile} (error ${err}), using the paper fill`);
        }
    }
}
