pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/config.js" as ConfigLib

Singleton {
    id: root

    readonly property string base: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    readonly property string dir: `${base}/gutter`
    property var values: ConfigLib.defaults()
    // Set by the first successful load or the first-run seed; from then on a missing file never gets anything written over it.
    property bool loadedOnce: false
    // True from the first-run write until it is saved or fails, so only the seed is logged and reloaded, not a migration rewrite.
    property bool seeding: false

    readonly property bool openOnHover: values.openOnHover
    readonly property int hoverDelay: values.hoverDelay
    readonly property bool hideInFullscreen: values.hideInFullscreen
    readonly property string idleContent: values.idleContent
    readonly property bool opensActivity: values.opensActivity
    readonly property int width: values.width
    readonly property bool gestures: values.gestures
    readonly property bool notifications: values.notifications
    readonly property var sections: values.sections
    readonly property var weather: values.weather
    readonly property var theme: values.theme
    readonly property var shadow: values.shadow
    readonly property var launcher: values.launcher
    readonly property var lockscreen: values.lockscreen
    readonly property var worldClocks: values.worldClocks

    // Logs the seed once. When the folder already existed the watch's reload can arrive before `saved`, so onLoaded calls it too.
    function seedDone(): void {
        if (!seeding)
            return;
        seeding = false;
        console.info(`gutter: wrote default config to ${dir}/config.json`);
    }

    FileView {
        id: file

        path: `${root.dir}/config.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const result = ConfigLib.parse(text());
            if (!result) {
                console.warn("gutter: config.json is not valid JSON, keeping previous settings");
                return;
            }
            result.warnings.forEach(w => console.warn("gutter:", w));
            root.values = result.config;
            root.loadedOnce = true;
            root.seedDone();
            // The write triggers one more load, which finds the current configVersion and changes nothing.
            if (result.rewrite)
                setText(ConfigLib.serialize(result.rewrite));
        }
        onSaved: {
            if (!root.seeding)
                return;
            root.seedDone();
            // A watch set up while the folder was missing never sees the file: reload rebuilds it.
            reload();
        }
        onSaveFailed: err => {
            console.warn(`gutter: cannot write ${path} (error ${err})`);
            // Only a failed seed reloads, to rebuild the watch so a file created by hand is still seen. A failed
            // migration rewrite must not: its load would write again.
            if (!root.seeding)
                return;
            root.seeding = false;
            reload();
        }
        // Only a first run gets a file written: one that goes missing later (moved away, or an editor
        // that deletes before it writes) keeps the current settings rather than being overwritten.
        onLoadFailed: err => {
            if (err !== FileViewError.FileNotFound)
                return;
            if (root.loadedOnce)
                console.warn("gutter: config.json is gone, keeping the current settings");
            else
                mkdir.running = true;
        }
    }

    Process {
        id: mkdir

        command: ["mkdir", "-p", "--", root.dir]
        // The first run writes the defaults, which `values` already holds, so it counts as loaded: a later
        // delete keeps the settings instead of seeding again.
        onExited: code => {
            if (code !== 0) {
                console.warn(`gutter: cannot create ${root.dir}, config.json not seeded`);
                return;
            }
            root.loadedOnce = true;
            root.seeding = true;
            file.setText(ConfigLib.firstRun());
        }
    }
}
