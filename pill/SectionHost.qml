import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import qs.components

// Shows the body of one panel section: pill/sections/<Name>Section.qml. Sections are added by dropping a file
// in; nothing here lists them. A name with no file shows "coming soon"; a file that fails to load is logged
// and shows "section failed to load".
//
// Convention for sections: declare `property ShellScreen screen` (not `required`) and read it null-safely.
// It is assigned once the Loader has created the section, so it is null until then, and stays live after.
Item {
    id: root

    required property string section
    required property ShellScreen screen

    readonly property string fileName: section ? section.charAt(0).toUpperCase() + section.slice(1) + "Section.qml" : ""
    // The folder listing is what decides existence, so a missing file is never confused with a broken one.
    // FolderListModel does not watch a folder created after the shell started, so while a visible section has
    // no file the folder is listed again every second (see the timer below); a file added later is picked up.
    readonly property bool exists: {
        files.count;
        if (files.status !== FolderListModel.Ready || fileName === "")
            return false;
        for (let i = 0; i < files.count; i++) {
            if (files.get(i, "fileName") === fileName)
                return true;
        }
        return false;
    }

    // The file to load, or "" when there is none. Handlers watch this one value: `fileName` and `exists` change
    // separately, and a handler on either could run while the other is still stale.
    readonly property string target: exists ? fileName : ""

    // "none": no file; "loading"; "ready": `component` is set; "failed": the file exists but would not load.
    property string loadState: "none"
    property var component: null
    // The component the last reload asked for; an answer for any other (a file replaced while loading) is stale.
    property var pending: null

    function settle(c: var): void {
        if (c !== pending)
            return;
        if (c.status === Component.Ready) {
            component = c;
            loadState = "ready";
        } else if (c.status === Component.Error) {
            console.warn("gutter: section", section, c.errorString());
            loadState = "failed";
        }
    }

    function reload(): void {
        component = null;
        pending = null;
        if (target === "") {
            loadState = "none";
            return;
        }
        loadState = "loading";
        const c = Qt.createComponent(Qt.resolvedUrl("sections/" + target));
        pending = c;
        if (c.status === Component.Loading)
            c.statusChanged.connect(() => root.settle(c));
        else
            settle(c);
    }

    onTargetChanged: reload()
    Component.onCompleted: reload()

    FolderListModel {
        id: files

        folder: Qt.resolvedUrl("sections")
        nameFilters: ["*Section.qml"]
        showDirs: false
    }

    // FolderListModel only watches a folder that existed when it started: for one created afterwards it stays
    // Ready with no entries, and never sees the file. So while a visible section has no file, list again.
    Timer {
        running: root.visible && root.fileName !== "" && !root.exists
        interval: 1000
        repeat: true
        onTriggered: {
            files.folder = "";
            files.folder = Qt.resolvedUrl("sections");
        }
    }

    Loader {
        id: loader

        anchors.fill: parent
        // Sections (and the services they reference) only exist while the panel is shown.
        active: root.visible && root.loadState === "ready"
        sourceComponent: root.component
    }

    Binding {
        target: loader.item
        property: "screen"
        value: root.screen
        when: loader.item !== null && "screen" in loader.item
    }

    InkText {
        anchors.centerIn: parent
        visible: root.loadState === "none" || root.loadState === "failed"
        text: root.loadState === "failed" ? "section failed to load" : "coming soon"
    }
}
