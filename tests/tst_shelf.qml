import QtQuick
import QtTest
import "../lib/shelf.js" as S

TestCase {
    name: "Shelf"

    function test_pathFromUrlDecodes() {
        compare(S.pathFromUrl("file:///home/a/My%20File%231.txt"), "/home/a/My File#1.txt");
        compare(S.pathFromUrl("file://localhost/tmp/x"), "/tmp/x");
        compare(S.pathFromUrl("file:///home/a/dir/"), "/home/a/dir");
        // String(Qt.resolvedUrl(...)) keeps a space literal but percent-encodes '#' and '%', so a checkout in a
        // directory named "c#" or "50%" reaches pathFromUrl encoded, and must come out decoded.
        compare(S.pathFromUrl("file:///home/a/My Repo/tools/gutter"), "/home/a/My Repo/tools/gutter");
        compare(S.pathFromUrl("file:///home/a/c%23/tools/gutter"), "/home/a/c#/tools/gutter");
        compare(S.pathFromUrl("file:///home/a/50%25/tools/gutter"), "/home/a/50%/tools/gutter");
    }

    function test_pathFromUrlRejectsOthers() {
        compare(S.pathFromUrl("https://example.com/a.png"), null);
        compare(S.pathFromUrl("file://relative/x"), null);
        compare(S.pathFromUrl("file:///a%09b"), null);
        compare(S.pathFromUrl("file:///a%0Ab"), null);
        compare(S.pathFromUrl("file:///%E0%A4%A"), null);
        compare(S.pathFromUrl("file:///"), null);
    }

    function test_pathsFromUrlsDedupesAndSkipsComments() {
        compare(S.pathsFromUrls(["file:///a", "https://x", "file:///a", "file:///b"]), ["/a", "/b"]);
        compare(S.pathsFromUrls("# list\r\nfile:///a\r\nfile:///b\r\n"), ["/a", "/b"]);
        compare(S.pathsFromUrls(null), []);
    }

    function test_uriListRoundTrips() {
        const paths = ["/home/a/My File#1.txt", "/tmp/ü/x"];
        const text = S.uriList(paths);
        verify(text.endsWith("\r\n"));
        compare(text.split("\r\n")[0], "file:///home/a/My%20File%231.txt");
        compare(S.pathsFromUrls(text), paths);
    }

    function test_names() {
        compare(S.baseName("/a/b/c.tar.gz"), "c.tar.gz");
        compare(S.dirName("/a/b/c.txt"), "/a/b");
        compare(S.dirName("/c.txt"), "/");
        compare(S.extension("/a/B.PNG"), "png");
        compare(S.extension("/a/.bashrc"), "");
        compare(S.extension("/a/noext"), "");
    }

    function test_kindAndIcon() {
        compare(S.kind("/a/x.PNG", false), "image");
        compare(S.kind("/a/x.pdf", false), "pdf");
        compare(S.kind("/a/x.unknown", false), "file");
        compare(S.kind("/a/x.png", true), "folder");
        compare(S.icon("video"), "movie");
        compare(S.icon("nonsense"), "draft");
    }

    function test_humanSize() {
        compare(S.humanSize(0), "0 B");
        compare(S.humanSize(999), "999 B");
        compare(S.humanSize(1500), "1.5 KB");
        compare(S.humanSize(123456), "123 KB");
        compare(S.humanSize(4200000), "4.2 MB");
        compare(S.humanSize(3e9), "3.0 GB");
        compare(S.humanSize(undefined), "0 B");
    }

    function test_addPutsNewestFirstAndMovesDuplicates() {
        let s = S.add(S.empty(), ["/a", "/b"], 1);
        compare(s.items.map(i => i.path), ["/a", "/b"]);
        s = S.add(s, ["/c", "/b"], 2);
        compare(s.items.map(i => i.path), ["/c", "/b", "/a"]);
        compare(s.items[1].added, 2);
    }

    function test_addCapsAtMax() {
        const paths = [];
        for (let i = 0; i < S.MAX_ITEMS + 5; i++)
            paths.push("/f" + i);
        const s = S.add(S.empty(), paths, 1);
        compare(s.items.length, S.MAX_ITEMS);
        compare(s.items[0].path, "/f0");
    }

    function test_removeKeepsOthers() {
        const s = S.remove(S.add(S.empty(), ["/a", "/b"], 1), "/a");
        compare(s.items.map(i => i.path), ["/b"]);
        compare(S.remove(s, "/zzz").items.length, 1);
    }

    function test_parseValidates() {
        compare(S.parse("not json"), null);
        compare(S.parse("[]"), null);
        compare(S.parse("{}"), null);
        const s = S.parse(JSON.stringify({ items: [{ path: "/a", added: 5 }, { path: "rel" }, { path: "/a" }, 7, { path: "/b" }] }));
        compare(s.items, [{ path: "/a", added: 5 }, { path: "/b", added: 0 }]);
    }

    function test_parseStat() {
        const info = S.parseStat("/a/b.txt\t120\tregular file\n/a/dir\t4096\tdirectory\n/a/e\t0\tregular empty file\nbroken line\n");
        compare(info["/a/b.txt"], { size: 120, dir: false });
        compare(info["/a/dir"].dir, true);
        compare(info["/a/e"].size, 0);
        verify(S.missing(info, "/nope"));
        verify(!S.missing(info, "/a/dir"));
    }

    function test_summary() {
        const s = S.add(S.empty(), ["/a", "/d"], 1);
        const info = { "/a": { size: 2000, dir: false }, "/d": { size: 4096, dir: true } };
        compare(S.summary(s, info).text, "2 items · 2.0 KB");
        compare(S.summary(S.empty(), {}).text, "0 items · 0 B");
        compare(S.summary(S.remove(s, "/d"), info).text, "1 item · 2.0 KB");
    }
}
