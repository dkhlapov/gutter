//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import Quickshell.Io
import qs.pill
import qs.theme
import "lib/config.js" as ConfigLib

// The wiring check (scripts/wiring.sh), for what the unit tests of lib/ cannot reach.
// SectionHost: a section name becomes pill/sections/<Name>Section.qml, and the host says so in fileName, exists,
// target and loadState: "ready" with the component loaded from that file for every section in lib/config.js,
// "none" for a name with no file and for "", "failed" for a file that does not load (the script adds one).
// Theme: ink, text, paper, textOnInk and the accents are the half of palette.json that theme.json names; they follow
// a change of the mode, an invalid half is served from default-palette.json (the valid one stays) and so is a
// missing or invalid theme.json (light). The palette is tests/wiring/palette.json, whose values differ from the
// defaults and between ink and text, so a colour read from the wrong half or the wrong key shows.
// The check changes theme.json and palette.json in the scratch state folder (WIRING_STATE) only.
ShellRoot {
    id: shell

    property var failures: []
    property int checks: 0
    property int step: -1
    property real deadline: 0

    readonly property var palette: JSON.parse(paletteFile.text())
    readonly property var defaults: JSON.parse(defaultFile.text())
    readonly property var light: palette.light
    readonly property var dark: palette.dark
    // The writes go only where the script said, never to a state folder the shell found for itself.
    readonly property bool scratch: Quickshell.env("WIRING_STATE") !== ""
        && Theme.stateDir === Quickshell.env("WIRING_STATE") + "/gutter"

    // Section names: a few spelled out, so the rule is not only checked against itself, then every configured one.
    readonly property var spelled: ({
            music: "MusicSection.qml",
            agents: "AgentsSection.qml",
            notifications: "NotificationsSection.qml"
        })
    readonly property var names: ["nosuch", "", "broken"].concat(
        ConfigLib.SECTIONS.filter(n => spelled[n] === undefined), Object.keys(spelled))

    function fileFor(name: string): string {
        return spelled[name] ?? (name.charAt(0).toUpperCase() + name.slice(1) + "Section.qml");
    }

    // [what, got, wanted] for one section name.
    function hostRows(name: string, host: var): var {
        // Has a file: everything but the two names with none.
        const loaded = name !== "" && name !== "nosuch";
        const file = name === "" ? "" : fileFor(name);
        const rows = [
            [name + ": fileName", host.fileName, file],
            [name + ": exists", host.exists, loaded],
            [name + ": target", host.target, loaded ? file : ""],
            [name + ": loadState", host.loadState, !loaded ? "none" : name === "broken" ? "failed" : "ready"]
        ];
        if (loaded && name !== "broken") {
            const url = host.component ? host.component.url.toString() : "";
            rows.push([name + ": component", url.endsWith("/pill/sections/" + file) ? file : url, file]);
        } else {
            rows.push([name + ": component", host.component, null]);
        }
        return rows;
    }

    function sectionRows(): var {
        let rows = [];
        for (let i = 0; i < names.length; i++) {
            const host = hosts.itemAt(i);
            rows = rows.concat(host ? hostRows(names[i], host) : [[names[i] + ": host", null, "a SectionHost"]]);
        }
        return rows;
    }

    function themeRows(mode: string, half: var): var {
        // Text on an ink plate is the light half's pair, whichever reads on this ink: its paper on the dark ink
        // of light mode, its ink on the cream ink of dark mode.
        return [
            ["mode", Theme.mode, mode],
            ["modeApplied", Theme.modeApplied, true],
            ["ink", String(Theme.ink), half.ink],
            ["paper", String(Theme.paper), half.paper],
            ["text", String(Theme.text), half.text],
            ["textOnInk", String(Theme.textOnInk), mode === "light" ? light.paper : light.ink],
            ["accent.sun", String(Theme.accent.sun), half.accents.sun],
            ["role.active", String(Theme.role.active), half.accents[palette.roles.active]],
            ["role.urgent", String(Theme.role.urgent), half.accents[palette.roles.urgent]]
        ];
    }

    // The fixture has to tell the wrong half, key or role from the right one: in each half ink, paper, text and
    // the accents all differ, the halves differ from each other, and nothing in it is the default palette's.
    function fixtureRows(): var {
        const rows = [];
        const accents = Object.keys(light.accents);
        for (const mode of ["light", "dark"]) {
            const h = palette[mode];
            const d = defaults[mode];
            rows.push([mode + ": ink, paper and text differ", new Set([h.ink, h.paper, h.text]).size, 3]);
            rows.push([mode + ": the accents differ", new Set(Object.values(h.accents)).size, accents.length]);
            for (const key of ["ink", "paper", "text"])
                rows.push([mode + "." + key + " differs from the default", h[key] !== d[key], true]);
            for (const name of accents)
                rows.push([mode + ".accents." + name + " differs from the default",
                    h.accents[name] !== d.accents[name], true]);
            for (const role of ["active", "urgent"]) {
                rows.push([mode + ": role " + role + " colour differs from the default's",
                    h.accents[palette.roles[role]] !== d.accents[defaults.roles[role]], true]);
            }
            rows.push([mode + ": role active and urgent colours differ",
                h.accents[palette.roles.active] !== h.accents[palette.roles.urgent], true]);
        }
        for (const key of ["ink", "paper", "text"])
            rows.push([key + " differs between the halves", light[key] !== dark[key], true]);
        for (const name of accents)
            rows.push(["accents." + name + " differs between the halves",
                light.accents[name] !== dark.accents[name], true]);
        for (const role of ["active", "urgent"])
            rows.push(["roles." + role + " differs from the default",
                palette.roles[role] !== defaults.roles[role], true]);
        return rows;
    }

    // A palette whose dark half has an invalid ink.
    function badDark(): string {
        const p = JSON.parse(paletteFile.text());
        p.dark.ink = "not a colour";
        return JSON.stringify(p);
    }

    // Each step acts, then the check is repeated until its rows all match or three seconds have passed (a watched
    // file takes a moment to be seen).
    readonly property var steps: [
        {
            name: "fixture",
            rows: () => shell.fixtureRows()
        },
        {
            name: "sections",
            rows: () => shell.sectionRows()
        },
        {
            name: "theme light",
            rows: () => shell.themeRows("light", shell.light)
        },
        {
            name: "theme dark",
            act: () => themeWriter.setText('{"version": 1, "mode": "dark"}'),
            rows: () => shell.themeRows("dark", shell.dark)
        },
        {
            name: "theme light again",
            act: () => themeWriter.setText('{"version": 1, "mode": "light"}'),
            rows: () => shell.themeRows("light", shell.light)
        },
        {
            name: "invalid dark half, dark mode",
            act: () => {
                paletteWriter.setText(shell.badDark());
                themeWriter.setText('{"version": 1, "mode": "dark"}');
            },
            rows: () => [
                ["mode", Theme.mode, "dark"],
                ["ink", String(Theme.ink), shell.defaults.dark.ink],
                ["paper", String(Theme.paper), shell.defaults.dark.paper],
                ["text", String(Theme.text), shell.defaults.dark.text],
                // The fixture's light half is valid and stays: its ink (#1a2b3c) is what reads on the default's
                // cream ink.
                ["textOnInk", String(Theme.textOnInk), shell.light.ink],
                ["accent.sun", String(Theme.accent.sun), shell.defaults.dark.accents.sun]
            ]
        },
        {
            name: "invalid dark half, light mode keeps the valid half",
            act: () => themeWriter.setText('{"version": 1, "mode": "light"}'),
            rows: () => shell.themeRows("light", shell.light)
        },
        {
            name: "invalid theme.json",
            act: () => themeWriter.setText('{"version": 1, "mode": "dusk"}'),
            rows: () => [
                ["mode", Theme.mode, "light"],
                ["modeApplied", Theme.modeApplied, false],
                ["ink", String(Theme.ink), shell.light.ink]
            ]
        }
    ]

    function advance(): void {
        step++;
        if (step >= steps.length) {
            finish();
            return;
        }
        if (steps[step].act)
            steps[step].act();
        deadline = Date.now() + 3000;
    }

    function finish(): void {
        if (failures.length) {
            for (const f of failures)
                console.log("wiring: FAIL: " + f);
        } else {
            console.log("wiring: OK (" + checks + " checks)");
        }
        Qt.quit();
    }

    // The rows that do not match, as text; "" when they all do.
    function mismatch(rows: var): string {
        const bad = rows.filter(r => r[1] !== r[2]);
        return bad.map(r => `${r[0]}: got ${r[1]}, wanted ${r[2]}`).join("; ");
    }

    FileView {
        id: paletteFile

        path: Qt.resolvedUrl("palette.json")
        blockLoading: true
    }

    FileView {
        id: defaultFile

        path: Qt.resolvedUrl("theme/default-palette.json")
        blockLoading: true
    }

    // Like `gutter theme apply`, which writes through a temporary file renamed over the real one.
    FileView {
        id: themeWriter

        path: shell.scratch ? Theme.themeStateFile : ""
        // Loaded before the first write, so no read is still running when it starts.
        blockLoading: true
        atomicWrites: true
    }

    FileView {
        id: paletteWriter

        path: shell.scratch ? Theme.stateFile : ""
        blockLoading: true
        atomicWrites: true
    }

    FloatingWindow {
        implicitWidth: 200
        implicitHeight: 100
        color: "white"

        // Hidden, so no section is built, only its file loaded; `screen` is only read by a shown section.
        Repeater {
            id: hosts

            model: shell.names
            delegate: SectionHost {
                required property string modelData

                visible: false
                section: modelData
                screen: null
            }
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (!shell.scratch) {
                shell.failures.push("the state folder is not the scratch one (" + Theme.stateDir
                    + "), nothing was run");
                shell.finish();
                running = false;
                return;
            }
            if (shell.step < 0) {
                shell.advance();
                return;
            }
            const s = shell.steps[shell.step];
            const rows = s.rows();
            const bad = shell.mismatch(rows);
            if (bad === "") {
                shell.checks += rows.length;
            } else if (Date.now() > shell.deadline) {
                shell.failures.push(s.name + ": " + bad);
            } else {
                return;
            }
            shell.advance();
            if (shell.step >= shell.steps.length)
                running = false;
        }
    }
}
