pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/tools.js" as ToolsLib

// Notes in tabs, saved to ~/.local/state/gutter/scratchpad.json half a second after the last change.
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/gutter`
    property var state: ToolsLib.notesEmpty()
    property bool loaded: false
    readonly property var notes: state.notes
    readonly property int current: state.current
    readonly property bool full: notes.length >= ToolsLib.MAX_NOTES

    function title(index: int): string {
        return ToolsLib.notesTitle(notes[index]?.text ?? "", index);
    }

    function edit(index: int, text: string): void {
        if (notes[index]?.text === text)
            return;
        state = ToolsLib.notesSetText(state, index, text);
        save.restart();
    }

    function add(): void {
        state = ToolsLib.notesAdd(state);
        save.restart();
    }

    function remove(index: int): void {
        state = ToolsLib.notesRemove(state, index);
        save.restart();
    }

    function select(index: int): void {
        state = ToolsLib.notesSelect(state, index);
        save.restart();
    }

    FileView {
        id: file

        path: `${root.dir}/scratchpad.json`
        atomicWrites: true
        onLoaded: {
            const parsed = ToolsLib.notesParse(text());
            if (parsed)
                root.state = parsed;
            else
                console.warn("gutter: scratchpad.json is not valid JSON, starting empty (the file is kept until the next edit)");
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err !== FileViewError.FileNotFound)
                console.warn("gutter: cannot read scratchpad.json, error", err);
            root.loaded = true;
        }
    }

    Process {
        id: mkdir

        command: ["mkdir", "-p", root.dir]
        onExited: file.setText(JSON.stringify(root.state, null, 2) + "\n")
    }

    // Edits before the first load finishes would overwrite the saved notes; they wait for it.
    Timer {
        id: save

        interval: 500
        onTriggered: {
            if (!root.loaded) {
                restart();
                return;
            }
            mkdir.running = true;
        }
    }
}
