pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.settings
import "../lib/palette.js" as PaletteLib

// The only reader of palette.json. Components read colours and tokens from here and nowhere else.
// palette.json has a light and a dark half; theme.json (written only by `gutter theme apply`) names the mode on
// screen, and the colours served are that mode's half. A half is applied whole: if palette.json is missing or
// invalid every colour comes from default-palette.json, and if one half of it is invalid that half does.
// Text drawn on paper is `text`; outlines, borders and ink plates are `ink` (black in light mode, cream in dark).
// The state folder is created at start and the watch is attached again once it exists: a FileView whose folder
// was missing when it opened never sees the file appear later, so a first `gutter palette regen` would
// otherwise need a restart.
Singleton {
    id: root

    // "" when neither XDG_STATE_HOME nor HOME is set: there is then no state file to read.
    readonly property string stateDir: {
        const base = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") ? Quickshell.env("HOME") + "/.local/state" : "");
        return base ? `${base}/gutter` : "";
    }
    readonly property string stateFile: stateDir ? `${stateDir}/palette.json` : ""
    readonly property string themeStateFile: stateDir ? `${stateDir}/theme.json` : ""

    // Same values as theme/default-palette.json. Only used when that file cannot be read or parsed.
    readonly property var lastResort: ({
            source: "",
            light: {
                ink: "#0e0d0e",
                paper: "#fbf6d3",
                text: "#0e0d0e",
                accents: {
                    navy: "#5780a3",
                    teal: "#22a5a6",
                    magenta: "#aa5bbd",
                    coral: "#e2492f",
                    sun: "#f6d14b",
                    lime: "#a3d23a",
                    pink: "#e8739d"
                }
            },
            dark: {
                ink: "#e4dfbd",
                paper: "#151e26",
                text: "#e4dfbd",
                accents: {
                    navy: "#41739d",
                    teal: "#007d7e",
                    magenta: "#a745be",
                    coral: "#d92600",
                    sun: "#9b6400",
                    lime: "#5b7a00",
                    pink: "#c53b75"
                }
            },
            roles: {
                active: "sun",
                urgent: "coral",
                focusBorder: "teal",
                ok: "lime",
                special: "magenta",
                muted: "navy"
            }
        })

    // default-palette.json parsed once, or lastResort (per half). One stable object, so reapplying it is a no-op.
    readonly property var defaultParsed: {
        const result = PaletteLib.parse(defaultFile.text());
        if (result.error)
            console.error(`gutter: palette: default-palette.json: ${result.error}`);
        if (!result.palette)
            return lastResort;
        const p = result.palette;
        if (!p.light)
            p.light = lastResort.light;
        if (!p.dark)
            p.dark = lastResort.dark;
        return p;
    }

    // Shape tokens
    readonly property int inkWidth: 3
    // The hard shadow's offset and the paper line round the outer surfaces' shadows (InkBox's keyline), from the
    // shadow.offset and shadow.keyline settings.
    readonly property int shadowOffset: Settings.shadow.offset
    readonly property int shadowKeyline: PaletteLib.shadowKeyline(Settings.shadow.keyline, Settings.shadow.offset)
    readonly property real halftoneDot: 1.4
    readonly property real halftoneGrid: 7
    // The height of every top-bar pill (workspace, tray, status, theme and power cells, the island), ink and
    // keyline included. A glyph-only cell is a square of this size; a cell with text or icons is this high with
    // equal padding left and right.
    readonly property int pillHeight: 38
    // The bar's text, its glyphs and the app icons in its cells.
    readonly property int textSize: 15
    readonly property int glyphSize: 18
    readonly property int appIconSize: 24
    // The smallest size of text that carries information (a time, a unit, an axis label); InkText's default.
    readonly property int textMin: 13
    // Gap above the resting pill. The pill floats with as much room below it (shadow to window) as above, for
    // a window alone on its workspace, which gets a 20 px gaps_out from the workspace rules in hypr/gutter/rules.lua
    // (gaps_outer_alone in hypr/gutter/vars.lua). Other windows use the general gaps_out (gaps_outer, 10), and a
    // user file loaded after it, such as HyprMod's hyprland-gui.lua with its 35, overrides that general value only,
    // not the single-window rule.
    readonly property int pillTop: 14
    readonly property int windowGap: 20
    readonly property int gap: 8
    readonly property int pad: 10
    // Vertical room a text plate (LabelTab's patch over its halftone) leaves above and below the text.
    readonly property int platePad: 1
    readonly property int animMs: 150
    readonly property string font: "JetBrainsMono Nerd Font"

    readonly property list<string> accentNames: PaletteLib.ACCENTS

    // The palette file as parsed (both halves): the default until palette.json parses.
    property var parsed: root.defaultParsed
    // The mode on screen, "light" or "dark", from theme.json; light while it is missing or invalid.
    property string mode: "light"
    // True only while theme.json exists and is valid, i.e. a mode has been applied (ThemeMode applies at once
    // when it is false).
    property bool modeApplied: false
    // The colours in use: the half of parsed for the current mode, a missing half coming from the default.
    readonly property var applied: PaletteLib.pick(parsed, mode, defaultParsed)

    // Outlines, borders, frames, ink plates: black in light mode, soft cream on the night page.
    readonly property color ink: applied.ink
    readonly property color paper: applied.paper
    // Text and glyphs drawn on paper. Equal to ink in both modes today (black; soft cream at night); kept as its own
    // key so text and lines can differ.
    readonly property color text: applied.text
    // Secondary text on paper (a date, a unit, a caption): the text colour softened toward paper, opaque, and never
    // below 4.5:1 on it. Drawn as a colour, not as reduced opacity, so it stays legible on any surface it lands on.
    readonly property color textMuted: PaletteLib.mutedText(applied)

    // Secondary text in `ink` on `surface` (a tile's fill, an accent plate): ink softened toward the surface, never
    // below 4.5:1 on it. Text on an accent plate often has little contrast to spare (the palette's own text-on-accent
    // pairs are 4.5:1 to 6.5:1 in dark mode), so where nothing softer clears 4.5:1 it stays whole.
    function mutedOn(ink: color, surface: color): color {
        return PaletteLib.mutedText({ text: `${ink}`, paper: `${surface}` });
    }
    // The shadow.color setting: the ink, an accent or a role, in the current mode's half. Teal by default, since
    // an ink shadow vanishes over a dark wallpaper or window.
    readonly property color shadow: PaletteLib.shadowColour(applied, Settings.shadow.color)
    readonly property string source: applied.source
    readonly property var accent: applied.accents
    readonly property var role: {
        const r = {};
        for (const name of PaletteLib.ROLES)
            r[name] = applied.accents[applied.roles[name]];
        return r;
    }
    // The accent each role is drawn in, for Theme.on[roleAccent.<role>].
    readonly property var roleAccent: applied.roles
    // The light half whatever the mode: its ink (black) and paper (cream) are the two colours text on an accent
    // or an ink plate is drawn in, in both modes.
    readonly property var lightHalf: PaletteLib.pick(parsed, "light", defaultParsed)
    // Text on an ink plate: cream on the black lines of light mode, black on the soft cream lines of dark mode.
    readonly property color textOnInk: PaletteLib.textOnInk(applied.ink, lightHalf)
    // Text on each of the current accents: black or cream, whichever contrasts more. The palette makes that one
    // colour per mode (tools/palette.py): black on every light accent, cream on every dark one.
    readonly property var on: PaletteLib.onAccents(applied.accents, lightHalf)

    // The last warning printed, so a watch that fires twice for one edit (or a repeated absence) warns once.
    // Cleared by a successful load. theme.json keeps its own, so the two files' warnings do not reset each other.
    property string lastWarning: ""
    property string lastModeWarning: ""

    function warnPalette(message: string): void {
        if (message !== lastWarning) {
            lastWarning = message;
            console.warn(message);
        }
    }

    function useDefault(reason: string): void {
        warnPalette(`gutter: palette: ${reason}, using default`);
        if (parsed !== defaultParsed)
            parsed = defaultParsed;
    }

    function useLight(reason: string): void {
        const message = `gutter: theme: ${reason}, using light`;
        if (message !== lastModeWarning) {
            lastModeWarning = message;
            console.warn(message);
        }
        modeApplied = false;
        mode = "light";
    }

    Component.onCompleted: {
        if (stateDir === "") {
            useDefault("neither XDG_STATE_HOME nor HOME is set");
            useLight("neither XDG_STATE_HOME nor HOME is set");
        } else {
            // The first read of theme.json blocks, so mode and modeApplied are right before anything is drawn:
            // no light flash for a dark user, and ThemeMode never mistakes "not read yet" for "missing".
            themeFile.text();
            mkdir.running = true;
        }
    }

    // FileView does not create parent directories.
    Process {
        id: mkdir

        command: ["mkdir", "-p", "--", root.stateDir]
        onExited: code => {
            if (code !== 0) {
                console.warn("gutter: palette: cannot create the state folder, a palette or theme written later needs a restart");
                return;
            }
            // A file that loaded needed an existing folder, so its watch is fine. Otherwise open it again now
            // that the folder is there; setting the path to "" first is what makes FileView drop the old watch.
            if (!paletteFile.loaded) {
                paletteFile.path = "";
                paletteFile.path = root.stateFile;
            }
            if (!themeFile.loaded) {
                themeFile.path = "";
                themeFile.path = root.themeStateFile;
            }
        }
    }

    FileView {
        id: defaultFile

        path: Qt.resolvedUrl("default-palette.json")
        blockLoading: true
    }

    FileView {
        id: paletteFile

        path: root.stateFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const result = PaletteLib.parse(text());
            if (!result.palette) {
                root.useDefault(result.error);
                return;
            }
            // One invalid half: keep the valid one, pick serves the other from the default.
            if (result.error)
                root.warnPalette(`gutter: palette: ${result.error}, using the default ${result.palette.light ? "dark" : "light"} half`);
            else
                root.lastWarning = "";
            root.parsed = result.palette;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                root.useDefault("no palette.json");
            else
                root.useDefault(`cannot read palette.json (error ${err})`);
        }
    }

    FileView {
        id: themeFile

        path: root.themeStateFile
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const result = PaletteLib.parseThemeFile(text());
            if (result.error) {
                root.useLight(`theme.json: ${result.error}`);
                return;
            }
            root.lastModeWarning = "";
            root.mode = result.mode;
            root.modeApplied = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                root.useLight("no theme.json");
            else
                root.useLight(`cannot read theme.json (error ${err})`);
        }
    }
}
