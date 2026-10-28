import QtQuick
import QtTest
import "../lib/palette.js" as P

TestCase {
    name: "Palette"
    readonly property string good: JSON.stringify({ version: 1, source: "", ink: "#0e0d0e", paper: "#fbf6d3",
        accents: { navy: "#224969", teal: "#22a5a6", magenta: "#8e3fa0", coral: "#e2492f", sun: "#f6d14b", lime: "#a3d23a", pink: "#e8739d" },
        roles: { active: "sun", urgent: "coral", focusBorder: "teal", ok: "lime", special: "magenta", muted: "navy" } })

    function variant(f) { const o = JSON.parse(good); f(o); return JSON.stringify(o); }

    readonly property var acc: ({ navy: "#224969", teal: "#22a5a6", magenta: "#8e3fa0", coral: "#e2492f", sun: "#f6d14b", lime: "#a3d23a", pink: "#e8739d" })
    readonly property var roleMap: ({ active: "sun", urgent: "coral", focusBorder: "teal", ok: "lime", special: "magenta", muted: "navy" })
    readonly property string goodV2: JSON.stringify({ version: 2, source: "", roles: roleMap,
        light: { ink: "#0e0d0e", paper: "#fbf6d3", text: "#0e0d0e", accents: acc },
        dark:  { ink: "#fbf6d3", paper: "#26232b", text: "#fbf6d3", accents: acc } })

    function variantV2(f) { const o = JSON.parse(goodV2); f(o); return JSON.stringify(o); }

    function test_good() {
        const r = P.parse(good);
        compare(r.error, "");
        compare(r.palette.light.accents.teal, "#22a5a6");
        compare(r.palette.roles.active, "sun");
    }
    function test_rejects_whole_file() {
        const bad = [
            "not json",
            variant(o => o.version = 3),
            variant(o => delete o.accents.pink),
            variant(o => o.accents.sun = "#ffff"),
            variant(o => o.roles.ok = "olive"),
            variant(o => o.ink = 12),
            variant(o => o.accents.extra = "#000000"),
            variant(o => delete o.roles.ok),
            variant(o => o.roles.bogus = "sun")
        ];
        for (let i = 0; i < bad.length; i++) {
            const r = P.parse(bad[i]);
            verify(r.palette === null, "case " + i + " is rejected");
            verify(r.error !== "", "case " + i + " has an error");
            verify(/^[A-Za-z0-9_.]+: .+/.test(r.error), "case " + i + " error format: " + r.error);
        }
    }
    function test_missing_and_unknown_role_name_the_role() {
        compare(P.parse(variant(o => delete o.roles.ok)).error.indexOf("roles.ok"), 0);
        compare(P.parse(variant(o => o.roles.bogus = "sun")).error.indexOf("roles.bogus"), 0);
    }
    function test_hex_is_lowercased() {
        const r = P.parse(variant(o => { o.ink = "#0E0D0E"; o.accents.coral = "#E2492F"; }));
        compare(r.error, "");
        compare(r.palette.light.ink, "#0e0d0e");
        compare(r.palette.light.accents.coral, "#e2492f");
    }
    function test_error_message_names_the_field() {
        verify(P.parse(variant(o => o.roles.ok = "olive")).error.indexOf("roles.ok") !== -1);
    }
    function test_v2_good() { const r = P.parse(goodV2); compare(r.error, ""); compare(r.palette.dark.paper, "#26232b") }
    function test_v2_rejects() {
        for (const [f, err] of [[o => delete o.dark, "dark: must be an object"],
                                [o => o.dark.text = "x", "dark.text: must be a #rrggbb colour"],
                                [o => delete o.light.accents.sun, "light.accents.sun: must be a #rrggbb colour"],
                                [o => o.version = 3, "version: must be 1 or 2"]])
            compare(P.parse(variantV2(f)).error, err)
    }
    function test_v1_loads_as_light_with_default_dark() {
        const r = P.parse(good)                       // the existing v1 sample
        compare(r.palette.light.text, "#0e0d0e"); compare(r.palette.dark, null)
        const d = P.parse(goodV2).palette
        compare(P.pick(r.palette, "dark", d).paper, "#26232b")
        compare(P.pick(r.palette, "light", d).paper, "#fbf6d3")
    }
    function test_pick_unknown_mode_is_light() { const d = P.parse(goodV2).palette; compare(P.pick(d, "dusk", d).paper, "#fbf6d3") }
    function test_v2_bad_dark_half_keeps_light() {
        for (const [f, err] of [[o => o.dark.text = "x", "dark.text: must be a #rrggbb colour"],
                                [o => delete o.dark, "dark: must be an object"]]) {
            const r = P.parse(variantV2(f))
            compare(r.error, err)
            verify(r.palette !== null, err + " keeps a palette")
            compare(r.palette.dark, null)
            compare(r.palette.light.paper, "#fbf6d3")
            compare(r.palette.roles.ok, "lime")
        }
    }
    function test_v2_bad_light_half_keeps_dark() {
        const r = P.parse(variantV2(o => delete o.light.accents.sun))
        compare(r.error, "light.accents.sun: must be a #rrggbb colour")
        compare(r.palette.light, null)
        compare(r.palette.dark.paper, "#26232b")
    }
    function test_v2_bad_half_is_filled_from_defaults() {
        const d = P.parse(goodV2).palette
        const r = P.parse(variantV2(o => { o.dark.paper = "nope"; o.light.paper = "#ffffff" })).palette
        compare(P.pick(r, "dark", d).paper, "#26232b")
        compare(P.pick(r, "light", d).paper, "#ffffff")
    }
    function test_v2_rejects_whole_file_when_more_is_wrong() {
        for (const [f, err] of [[o => { delete o.dark; delete o.light }, "light: must be an object"],
                                [o => { o.dark.text = "x"; o.roles.ok = "olive" }, "dark.text: must be a #rrggbb colour"],
                                [o => { o.dark.text = "x"; o.source = 3 }, "source: must be a string"]]) {
            const r = P.parse(variantV2(f))
            compare(r.error, err)
            compare(r.palette, null)
        }
    }
    function test_pick_carries_roles_source_and_dark_text() {
        const d = P.parse(variantV2(o => o.source = "/w.png")).palette
        const a = P.pick(d, "dark", d)
        compare(a.text, "#fbf6d3"); compare(a.source, "/w.png"); compare(a.roles.urgent, "coral")
    }
    function test_theme_file() {
        compare(P.parseThemeFile('{"version":1,"mode":"dark"}'), { mode: "dark", error: "" })
        compare(P.parseThemeFile('{"version":1,"mode":"light"}'), { mode: "light", error: "" })
        for (const [text, err] of [["nope", "file: not valid JSON"],
                                   ["[]", "file: not a JSON object"],
                                   ['{"version":2,"mode":"dark"}', "version: must be 1"],
                                   ['{"version":1,"mode":"dusk"}', 'mode: must be "light" or "dark"'],
                                   ['{"version":1}', 'mode: must be "light" or "dark"']])
            compare(P.parseThemeFile(text), { mode: "light", error: err })
    }
    function test_on_ink() {
        // Text on an ink plate is black or cream (the light ink or paper), whichever reads on the current ink.
        const d = P.parse(goodV2).palette
        compare(P.textOnInk(d.light.ink, d.light), "#fbf6d3")    // light: cream on black lines
        compare(P.textOnInk(d.dark.ink, d.light), "#0e0d0e")     // dark: black on cream lines
    }
    function test_dark_lines_are_cream() {
        const d = P.parse(goodV2).palette
        compare(P.pick(d, "dark", d).ink, "#fbf6d3")
        compare(P.pick(d, "dark", d).text, "#fbf6d3")
    }
    function test_text_on_accent_is_one_colour_per_mode() {
        // The default palette's two accent sets: every light accent carries black, every (deepened) dark one cream.
        const light = { ink: "#0e0d0e", paper: "#fbf6d3" }
        const lightAcc = { navy: "#5780a3", teal: "#22a5a6", magenta: "#aa5bbd", coral: "#e2492f", sun: "#f6d14b", lime: "#a3d23a", pink: "#e8739d" }
        const darkAcc = { navy: "#41739d", teal: "#007d7e", magenta: "#a745be", coral: "#d92600", sun: "#9b6400", lime: "#5b7a00", pink: "#c53b75" }
        for (const name of P.ACCENTS) {
            compare(P.onAccents(lightAcc, light)[name], "#0e0d0e", name)
            compare(P.onAccents(darkAcc, light)[name], "#fbf6d3", name)
        }
    }
    function test_contrast() {
        fuzzyCompare(P.contrast("#000000", "#ffffff"), 21, 0.01);
        fuzzyCompare(P.contrast("#224969", "#0e0d0e"), 2.1, 0.1);
    }
    function test_text_on() {
        compare(P.textOn("#224969", "#0e0d0e", "#fbf6d3"), "#fbf6d3");
        compare(P.textOn("#8e3fa0", "#0e0d0e", "#fbf6d3"), "#fbf6d3");
        compare(P.textOn("#f6d14b", "#0e0d0e", "#fbf6d3"), "#0e0d0e");
        compare(P.textOn("#22a5a6", "#0e0d0e", "#fbf6d3"), "#0e0d0e");
        compare(P.textOn("#e2492f", "#0e0d0e", "#fbf6d3"), "#0e0d0e");
        compare(P.textOn("#a3d23a", "#0e0d0e", "#fbf6d3"), "#0e0d0e");
        compare(P.textOn("#e8739d", "#0e0d0e", "#fbf6d3"), "#0e0d0e");
    }
    function test_shadowColourInk() {
        const d = P.parse(goodV2).palette
        compare(P.shadowColour(P.pick(d, "light", d), "ink"), "#0e0d0e")
        compare(P.shadowColour(P.pick(d, "dark", d), "ink"), "#fbf6d3")
    }
    function test_shadowColourAccent() {
        const d = P.parse(goodV2).palette
        compare(P.shadowColour(P.pick(d, "light", d), "coral"), acc.coral)
    }
    function test_shadowColourRole() {
        let d = P.parse(goodV2).palette
        compare(P.shadowColour(P.pick(d, "dark", d), "focusBorder"), acc.teal)
        d = P.parse(variantV2(o => o.roles.focusBorder = "pink")).palette
        compare(P.shadowColour(P.pick(d, "dark", d), "focusBorder"), acc.pink)
    }
    function test_shadowColourUnknownIsTeal() {
        const d = P.parse(goodV2).palette
        compare(P.shadowColour(P.pick(d, "light", d), "chartreuse"), acc.teal)
    }
    function test_keylineIsZeroWithoutOffset() {
        compare(P.shadowKeyline(2, 0), 0)
        compare(P.shadowKeyline(2, 3), 2)
        compare(P.shadowKeyline(0, 5), 0)
    }
}
