import QtQuick
import QtTest
import "../lib/glyphs.js" as G
import "../lib/weather.js" as W
import "../lib/shelf.js" as S
import "../lib/volume.js" as V
import "../lib/keys.js" as K

TestCase {
    name: "Glyphs"

    // Every icon name WeatherLib.icon can return, for every code the lib knows, day and night, and for a
    // code it does not know (which falls back to "air").
    function returnedNames() {
        const names = {};
        const codes = Object.keys(W.ICONS).map(Number).concat([-1, 4, 999]);
        for (const code of codes) {
            for (const day of [true, false])
                names[W.icon(code, day)] = true;
        }
        return Object.keys(names);
    }

    function test_everyWeatherNameHasAGlyph() {
        const names = returnedNames();
        verify(names.length >= 10, "expected the lib to return many names, got " + names.length);
        for (const name of names)
            verify(G.has(name), "no glyph for " + name);
    }

    // Every icon name ShelfLib.icon can return, plus the one the shelf tile asks for when a file is gone.
    function shelfNames() {
        return Object.keys(S.ICONS).map(k => S.icon(k)).concat(["unknown_document"]);
    }

    function test_everyShelfNameHasAGlyph() {
        const names = shelfNames();
        verify(names.length >= 9, "expected the shelf to name many icons, got " + names.length);
        for (const name of names) {
            verify(G.has(name), "no glyph for " + name);
            const g = G.glyph(name);
            const cp = g.codePointAt(0);
            compare(g.length, 2, name);
            verify(cp >= 0xf0000 && cp <= 0xffffd, name);
            verify(g !== G.FALLBACK, name);
        }
    }

    function test_shelfKindsAreDistinct() {
        const seen = {};
        for (const k of Object.keys(S.ICONS)) {
            const g = G.glyph(S.icon(k));
            verify(!seen[g], `${k} shares its glyph with ${seen[g]}`);
            seen[g] = k;
        }
    }

    // Every icon name VolumeLib.icon can return, over the volume range and muted or not, each a distinct
    // plane-15 glyph.
    function volumeNames() {
        const names = {};
        for (const v of [0, 0.01, 0.3, 0.49, 0.5, 1, 1.5])
            for (const muted of [false, true])
                names[V.icon(v, muted)] = true;
        return Object.keys(names);
    }

    function test_everyVolumeNameHasAGlyph() {
        const names = volumeNames();
        compare(names.length, 4);
        const seen = {};
        for (const name of names) {
            verify(G.has(name), "no glyph for " + name);
            const g = G.glyph(name);
            const cp = g.codePointAt(0);
            verify(cp >= 0xf0000 && cp <= 0xffffd, name);
            verify(g !== G.FALLBACK, name);
            verify(!seen[g], `${name} shares its glyph with ${seen[g]}`);
            seen[g] = name;
        }
    }

    // Every icon name KeysLib.icon can return (the keys HUD), each a distinct plane-15 glyph. The names the
    // activity views and the notification history write out in QML are scanned from the source by
    // tests/test_glyph_usage.py.
    function keysNames() {
        const names = {};
        for (const kind of Object.keys(K.NAMES))
            for (const on of [false, true])
                names[K.icon(kind, on)] = true;
        return Object.keys(names);
    }

    function test_everyKeysNameHasAGlyph() {
        const names = keysNames();
        compare(names.length, 3);
        const seen = {};
        for (const name of names) {
            verify(G.has(name), "no glyph for " + name);
            const g = G.glyph(name);
            const cp = g.codePointAt(0);
            verify(cp >= 0xf0000 && cp <= 0xffffd, name);
            verify(g !== G.FALLBACK, name);
            verify(!seen[g], `${name} shares its glyph with ${seen[g]}`);
            seen[g] = name;
        }
    }

    function test_nightVariantsAreDistinct() {
        verify(G.glyph("clear_night") !== G.glyph("clear_day"));
        verify(G.glyph("partly_cloudy_night") !== G.glyph("partly_cloudy_day"));
    }

    // One private-use code point each (a Nerd Font glyph), never the fallback.
    function test_glyphsAreSingleCodePoints() {
        for (const name of returnedNames()) {
            const g = G.glyph(name);
            compare(g.length, 1, name);
            verify(g.charCodeAt(0) >= 0xe000 && g.charCodeAt(0) <= 0xf8ff, name);
            verify(g !== G.FALLBACK, name);
        }
    }

    function test_unknownNameFallsBack() {
        compare(G.glyph("no_such_icon"), G.FALLBACK);
        compare(G.glyph(""), G.FALLBACK);
        compare(G.glyph(undefined), G.FALLBACK);
        verify(!G.has("no_such_icon"));
    }

    // Names are table keys, not object properties.
    function test_inheritedPropertiesAreNotNames() {
        compare(G.glyph("constructor"), G.FALLBACK);
        compare(G.glyph("toString"), G.FALLBACK);
        verify(!G.has("__proto__"));
    }
}
