import QtQuick
import QtTest
import "../lib/mixer.js" as M
import "../lib/palette.js" as P

TestCase {
    name: "Mixer"

    function node(id, props, extra) {
        return Object.assign({ id, name: "n" + id, description: "", properties: props }, extra);
    }

    function test_describesPlaybackStream() {
        const a = M.describe(node(7, { "media.class": "Stream/Output/Audio", "application.name": "Firefox", "media.name": "Lofi stream", "application.icon-name": "firefox" }));
        compare(a, { id: 7, app: "Firefox", title: "Lofi stream", icon: "firefox" });
    }

    function test_ignoresOtherNodes() {
        compare(M.describe(node(1, { "media.class": "Audio/Sink", "application.name": "x" })), null);
        compare(M.describe(node(2, { "media.class": "Stream/Input/Audio", "application.name": "x" })), null);
        compare(M.describe(node(3, {})), null);
        compare(M.describe(null), null);
    }

    function test_titleSameAsAppIsDropped() {
        const a = M.describe(node(4, { "media.class": "Stream/Output/Audio", "application.name": "mpv", "media.name": "MPV" }));
        compare(a.title, "");
    }

    function test_nameFallbacksAndIcon() {
        const a = M.describe(node(5, { "media.class": "Stream/Output/Audio" }, { description: "Some App" }));
        compare(a.app, "Some App");
        compare(a.icon, "some app");
        const b = M.describe(node(6, { "media.class": "Stream/Output/Audio", "application.process.binary": "vlc" }, { name: "VLC" }));
        compare(b.icon, "vlc");
        compare(M.describe(node(8, { "media.class": "Stream/Output/Audio" }, { name: "" })), null);
    }

    function test_appsAreSortedAndFiltered() {
        const out = M.apps([
            node(3, { "media.class": "Stream/Output/Audio", "application.name": "mpv" }),
            node(2, { "media.class": "Audio/Sink" }),
            node(9, { "media.class": "Stream/Output/Audio", "application.name": "Firefox" }),
            node(5, { "media.class": "Stream/Output/Audio", "application.name": "Firefox" })
        ]);
        compare(out.map(a => a.id), [5, 9, 3]);
    }

    function test_playbackKeepsNodes() {
        const a = node(3, { "media.class": "Stream/Output/Audio", "application.name": "mpv" });
        const b = node(9, { "media.class": "Stream/Output/Audio", "application.name": "Firefox" });
        const out = M.playback([a, node(2, { "media.class": "Audio/Sink" }), b]);
        compare(out.length, 2);
        verify(out[0] === b && out[1] === a);
    }

    function test_playbackOrderMatchesApps() {
        const nodes = [
            node(9, { "media.class": "Stream/Output/Audio", "application.name": "mpv" }),
            node(5, { "media.class": "Stream/Output/Audio", "application.name": "Firefox" }),
            node(2, { "media.class": "Stream/Output/Audio", "application.name": "mpv" }),
            node(7, { "media.class": "Stream/Output/Audio", "application.name": "Firefox" })
        ];
        compare(M.playback(nodes).map(n => n.id), [5, 7, 2, 9]);
        compare(M.playback(nodes).map(n => n.id), M.apps(nodes).map(a => a.id));
    }

    function test_stripAccentsSkipTheMasterAccent() {
        const accents = ["navy", "teal", "magenta", "coral"];
        compare(M.stripAccent(0, accents), "navy");
        compare(M.stripAccent(1, accents), "magenta");
        compare(M.stripAccent(2, accents), "coral");
        compare(M.stripAccent(3, accents), "navy");
        for (let i = 0; i < 12; i++)
            verify(M.stripAccent(i, accents) !== M.MASTER_ACCENT);
    }

    function test_stripAccentsOfTheRealPalette() {
        compare(M.stripAccent(1, P.ACCENTS), "magenta");
        for (let i = 0; i <= 20; i++)
            verify(M.stripAccent(i, P.ACCENTS) !== "teal");
    }
}
