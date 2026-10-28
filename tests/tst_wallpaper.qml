import QtQuick
import QtTest
import "../lib/wallpaper.js" as W

TestCase {
    name: "Wallpaper"
    function test_state_dir() {
        compare(W.stateDir("/x/state", "/home/u"), "/x/state/gutter");
        compare(W.stateDir("/x/state", ""), "/x/state/gutter");
        compare(W.stateDir("", "/home/u"), "/home/u/.local/state/gutter");
        compare(W.stateDir(undefined, "/home/u"), "/home/u/.local/state/gutter");
        compare(W.stateDir("", ""), "");
        compare(W.stateDir(undefined, undefined), "");
        compare(W.stateDir(null, null), "");
    }
    function test_parse_path() {
        compare(W.parsePath("/a/b.jpg\n", "/home/u"), "/a/b.jpg");
        compare(W.parsePath("  ~/w.png ", "/home/u"), "/home/u/w.png");
        compare(W.parsePath("w.png", "/home/u"), "");
        compare(W.parsePath("", "/home/u"), "");
    }
    function test_parse_path_messy() {
        compare(W.parsePath("/a/b.jpg\r\n\n", "/home/u"), "/a/b.jpg");
        compare(W.parsePath("\n\n/a b/c.jpg\n", "/home/u"), "/a b/c.jpg");
        compare(W.parsePath("~", "/home/u"), "");
        compare(W.parsePath("~/", "/home/u"), "");
        compare(W.parsePath("~/w.png", ""), "");
        compare(W.parsePath("~user/w.png", "/home/u"), "");
        compare(W.parsePath("./w.png", "/home/u"), "");
        compare(W.parsePath("   \n", "/home/u"), "");
        compare(W.parsePath(null, "/home/u"), "");
        compare(W.parsePath(undefined, "/home/u"), "");
    }
}
