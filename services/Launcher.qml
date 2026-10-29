pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.settings
import "../lib/launcher.js" as LauncherLib
import "../lib/commands.js" as Commands
import "../lib/power.js" as PowerLib

// The launcher window's state and what it does: the query, the ranked rows (apps, or slash commands), launching an
// app, running a command, and the session screen. The window itself lives in launcher/; this is everything behind it.
// With `dryRun` set (GUTTER_LAUNCHER_DRY_RUN=1 at start, or `gutter launcherDryRun true` over IPC) apps and commands
// are only logged and recorded in `lastDryRun`, so the launcher can be tried without starting or changing anything.
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/gutter`

    // The monitor whose launcher is open, "" when it is closed. One launcher at a time.
    property string screen: ""
    // "launcher" (search box and rows) or "session" (the tiles of the session actions).
    property string mode: "launcher"
    property string query: ""
    property int selected: 0
    // The name of the command waiting for a second activation, "" for none.
    property string confirming: ""
    property bool dryRun: Quickshell.env("GUTTER_LAUNCHER_DRY_RUN") === "1"
    // The last action a dry run would have taken, for checks.
    property string lastDryRun: ""

    // { id: { count, last } }, saved to launcher.json.
    property var usage: ({})
    property bool loaded: false

    readonly property var parsed: LauncherLib.parse(query)
    readonly property var apps: DesktopEntries.applications.values.filter(e => !e.noDisplay).map(e => ({
                id: e.id,
                name: e.name,
                genericName: e.genericName,
                comment: e.comment,
                icon: e.icon,
                keywords: Array.from(e.keywords),
                command: Array.from(e.command),
                workingDirectory: e.workingDirectory,
                runInTerminal: e.runInTerminal
            }))
    readonly property var commands: Commands.list(Settings.sections, Power.entries)
    readonly property var results: parsed.mode === "apps" ? LauncherLib.rank(apps, parsed.text, usage, Date.now(), 50).map(appRow) : Commands.match(commands, parsed.text).map(commandRow)

    onQueryChanged: resetSelection()
    onModeChanged: resetSelection()

    function resetSelection(): void {
        selected = 0;
        confirming = "";
    }

    function appRow(app: var): var {
        return {
            kind: "app",
            key: app.id,
            title: app.name,
            subtitle: app.genericName || "",
            iconName: app.icon,
            app: app
        };
    }

    function commandRow(m: var): var {
        return {
            kind: "command",
            key: m.command.name,
            title: m.ready ? "/" + m.command.name : Commands.usage(m.command),
            subtitle: m.command.description,
            glyph: m.command.glyph,
            ready: m.ready,
            command: m.command,
            arg: m.arg
        };
    }

    // The monitor to use when none is focused (the focused name is empty): the first one.
    function screenOr(name: string): string {
        return name !== "" ? name : (Quickshell.screens[0]?.name ?? "");
    }

    function open(screenName: string, newMode: string): void {
        query = "";
        selected = 0;
        confirming = "";
        mode = newMode;
        PillControl.close();
        Power.menuScreen = "";
        Power.refresh();
        screen = screenOr(screenName);
    }

    function close(): void {
        screen = "";
        confirming = "";
    }

    function toggle(screenName: string, newMode: string): void {
        if (screen === screenOr(screenName) && mode === newMode)
            close();
        else
            open(screenName, newMode);
    }

    function setQuery(text: string): void {
        query = text;
    }

    function move(delta: int): void {
        if (mode !== "launcher")
            return;
        const n = results.length;
        if (n === 0)
            return;
        selected = (((selected + delta) % n) + n) % n;
    }

    // Tab: fills the selected row in, keeping what was typed as its argument.
    function complete(): void {
        if (mode !== "launcher")
            return;
        if (selected < 0 || selected >= results.length)
            return;
        const row = results[selected];
        if (row.kind === "app")
            query = row.app.name;
        else
            query = "/" + row.command.name + (row.command.arg !== "" ? " " + row.arg : "");
    }

    // Escape: drops a command waiting for its confirmation, else closes.
    function cancel(): void {
        if (confirming !== "")
            confirming = "";
        else
            close();
    }

    function activate(): void {
        // The session screen has no list: its tiles go through choose().
        if (mode !== "launcher")
            return;
        if (selected < 0 || selected >= results.length)
            return;
        const row = results[selected];
        if (row.kind === "app")
            launch(row.app);
        else if (row.ready)
            runCommand(row.command, row.arg);
    }

    // A session tile: the command by name, as if it had been typed. A command that needs an argument cannot be
    // chosen without one (a timer would start with 0 minutes).
    function choose(name: string): void {
        const command = commands.find(c => c.name === name);
        if (command && command.arg === "")
            runCommand(command, "");
    }

    function launch(app: var): void {
        close();
        const argv = LauncherLib.appCommand(app, Settings.launcher.terminal);
        // An app that cannot start is not a launch: it leaves the history alone.
        if (argv.length === 0)
            return;
        // A dry run leaves the real history alone.
        if (!dryRun) {
            usage = LauncherLib.bump(usage, app.id, Date.now());
            save.restart();
        }
        const cwd = app.workingDirectory;
        run(`app:${JSON.stringify(argv)}`, () => {
            console.info(`gutter: launcher: ${JSON.stringify(argv)}`);
            Quickshell.execDetached(cwd ? {
                command: argv,
                workingDirectory: cwd
            } : {
                command: argv
            });
        });
    }

    function runCommand(command: var, arg: string): void {
        if (command.confirm) {
            const step = PowerLib.choose({
                id: command.name,
                confirm: command.confirm
            }, confirming);
            confirming = step.confirming;
            if (!step.run)
                return;
        }
        const type = command.run.type;
        const value = command.run.value;
        if (type === "session") {
            query = "";
            mode = "session";
            return;
        }
        const from = screen;
        close();
        switch (type) {
        case "power":
            run(`power:${value}`, () => Power.run(value));
            break;
        case "theme":
            run(`theme:${value}`, () => value === "toggle" ? ThemeMode.toggle() : ThemeMode.set(value));
            break;
        case "dnd":
            run("dnd", () => Notifications.toggleDnd());
            break;
        case "clear":
            run("clear", () => Notifications.clear());
            break;
        case "mute":
            run("mute", () => Audio.toggleMute());
            break;
        case "timer":
            run(`timer:${Number(arg)}`, () => Timers.startTimer(Number(arg)));
            break;
        case "stopwatch":
            run("stopwatch", () => Timers.toggleStopwatch());
            break;
        case "open":
            run(`open:${value}`, () => PillControl.openOn(from, value));
            break;
        }
    }

    // The one place an action happens, so a dry run catches every one.
    function run(description: string, fn: var): void {
        if (dryRun) {
            lastDryRun = description;
            console.info(`gutter: launcher (dry run): ${description}`);
            return;
        }
        fn();
    }

    FileView {
        id: file

        path: `${root.dir}/launcher.json`
        atomicWrites: true
        onLoaded: {
            const parsedUsage = LauncherLib.parseUsage(text(), Date.now());
            if (parsedUsage)
                root.usage = parsedUsage;
            else
                console.warn("gutter: launcher.json is not valid, starting empty (the file is kept until the next launch)");
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err !== FileViewError.FileNotFound)
                console.warn("gutter: cannot read launcher.json, error", err);
            root.loaded = true;
        }
    }

    Process {
        id: mkdir

        command: ["mkdir", "-p", root.dir]
        onExited: file.setText(LauncherLib.serializeUsage(root.usage) + "\n")
    }

    // A launch before the first load finishes would overwrite the saved history; it waits for it.
    Timer {
        id: save

        interval: 1000
        onTriggered: {
            if (!root.loaded) {
                restart();
                return;
            }
            mkdir.running = true;
        }
    }
}
