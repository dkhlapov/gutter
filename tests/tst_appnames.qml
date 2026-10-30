import QtQuick
import QtTest
import "../lib/appnames.js" as A

TestCase {
    name: "AppNames"

    function test_known() {
        compare(A.displayName("com.anthropic.claude"), "Claude");
        compare(A.displayName("COM.ANTHROPIC.CLAUDE"), "Claude");
        compare(A.displayName("org.telegram.desktop"), "Telegram");
        compare(A.displayName("gutter"), "Gutter");
    }

    function test_reverseDns() {
        compare(A.displayName("org.gnome.Calculator"), "Calculator");
        compare(A.displayName("com.github.wwmm.easyeffects"), "Easyeffects");
        compare(A.displayName("io.github.some.app"), "Some");
    }

    function test_inheritedKeysAreNotNames() {
        compare(A.displayName("constructor"), "Constructor");
        compare(A.displayName("toString"), "toString");
    }

    function test_plain() {
        compare(A.displayName("firefox"), "Firefox");
        compare(A.displayName("deezer-desktop"), "Deezer Desktop");
        compare(A.displayName("Discord"), "Discord");
        compare(A.displayName("Google Chrome"), "Google Chrome");
        compare(A.displayName(""), "");
        compare(A.displayName(null), "");
    }
}
