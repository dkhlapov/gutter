import QtQuick
import QtTest
import "../lib/clipboard.js" as C

TestCase {
    name: "Clipboard"

    function b64(s) {
        // Test-side encoder for UTF-8 strings.
        const bytes = [];
        for (const ch of s) {
            const cp = ch.codePointAt(0);
            if (cp < 0x80)
                bytes.push(cp);
            else if (cp < 0x800)
                bytes.push(0xc0 | (cp >> 6), 0x80 | (cp & 0x3f));
            else if (cp < 0x10000)
                bytes.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
            else
                bytes.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
        }
        const T = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let out = "";
        for (let i = 0; i < bytes.length; i += 3) {
            const n = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0);
            out += T[(n >> 18) & 63] + T[(n >> 12) & 63] + (i + 1 < bytes.length ? T[(n >> 6) & 63] : "=") + (i + 2 < bytes.length ? T[n & 63] : "=");
        }
        return out;
    }

    function test_decodesUtf8() {
        compare(C.utf8(C.decodeBase64("aGVsbG8=")), "hello");
        compare(C.utf8(C.decodeBase64(b64("héllo wörld — ✓ 😀"))), "héllo wörld — ✓ 😀");
        compare(C.utf8(C.decodeBase64(b64("line1\nline2\ttab"))), "line1\nline2\ttab");
    }

    function test_invalidUtf8BecomesReplacement() {
        compare(C.utf8([0x61, 0xff, 0x62]), "a�b");
        compare(C.utf8([0x61, 0xe2, 0x82]), "a�");
        compare(C.utf8([0xc0, 0x80]), "��");
    }

    function test_parseLine() {
        compare(C.parseLine("t " + b64("hi there\n")), { kind: "text", text: "hi there\n" });
        compare(C.parseLine("i /home/x/clipboard/abc.png\n"), { kind: "image", path: "/home/x/clipboard/abc.png" });
        compare(C.parseLine("t " + b64("   ")), null);
        compare(C.parseLine("x nope"), null);
        compare(C.parseLine(""), null);
    }

    function item(text) {
        return { kind: "text", text };
    }

    function test_addNewestFirstAndDedupe() {
        let r = C.add([], item("a"), 100);
        r = C.add(r.items, item("b"), 200);
        compare(r.items.map(i => i.text), ["b", "a"]);
        const idA = r.items[1].id;
        r = C.add(r.items, item("a"), 300);
        compare(r.items.map(i => i.text), ["a", "b"]);
        compare(r.items[0].id, idA);
        compare(r.items[0].t, 300);
        compare(r.evicted.length, 0);
    }

    function test_idsAreUnique() {
        let r = C.add([], item("a"), 100);
        r = C.add(r.items, item("b"), 100);
        verify(r.items[0].id !== r.items[1].id);
    }

    function test_limitEvictsOldestUnpinned() {
        let items = [];
        for (let i = 0; i < 5; i++)
            items = C.add(items, item("n" + i), i, 3).items;
        compare(items.map(i => i.text), ["n4", "n3", "n2"]);
        const r = C.add(items, item("n5"), 9, 3);
        compare(r.evicted.map(i => i.text), ["n2"]);
    }

    function test_pinnedStayAndDoNotCount() {
        let items = C.add([], item("keep"), 1, 2).items;
        items = C.togglePin(items, items[0].id);
        for (let i = 0; i < 4; i++)
            items = C.add(items, item("n" + i), 10 + i, 2).items;
        compare(items.map(i => i.text), ["keep", "n3", "n2"]);
        // Copying a pinned item again keeps its pin and its place in front.
        const r = C.add(items, item("keep"), 99, 2);
        compare(r.items[0].text, "keep");
        verify(r.items[0].pinned);
        compare(r.items.length, 3);
    }

    function test_removeAndClear() {
        let items = C.add([], item("a"), 1).items;
        items = C.add(items, item("b"), 2).items;
        items = C.togglePin(items, items[1].id);
        const c = C.clear(items);
        compare(c.items.map(i => i.text), ["a"]);
        compare(c.evicted.map(i => i.text), ["b"]);
        const r = C.remove(items, items[0].id);
        compare(r.items.length, 1);
        compare(r.evicted.length, 1);
        compare(C.remove(items, "nope").evicted.length, 0);
    }

    function test_filter() {
        let items = C.add([], item("Hello World"), 1).items;
        items = C.add(items, { kind: "image", path: "/x.png" }, 2).items;
        compare(C.filter(items, "").length, 2);
        compare(C.filter(items, "  world").length, 1);
        compare(C.filter(items, "zzz").length, 0);
    }

    function test_type() {
        compare(C.type(item("https://example.com/a?b=1")), "link");
        compare(C.type(item("www.example.com")), "link");
        compare(C.type(item("see https://example.com")), "text");
        compare(C.type(item("#a1b2c3")), "colour");
        compare(C.type(item("a1b2c3")), "text");
        compare(C.type(item("#12")), "text");
        compare(C.type(item("#abc")), "colour");
        compare(C.type(item("#AABBCCDD")), "colour");
        compare(C.type(item("#abcde")), "text");
        compare(C.type(item("abc")), "text");
        compare(C.type(item("  #abc  ")), "colour");
        compare(C.type({ kind: "image", path: "/x.png" }), "image");
        compare(C.colour(item("#FFAA00")), "#FFAA00");
        compare(C.colour(item("plain")), "");
    }

    function test_previewAndMeta() {
        compare(C.preview("  a\n\n  b\tc  "), "a b c");
        compare(C.preview("x".repeat(300), 10), "xxxxxxxxx…");
        compare(C.meta(item("abc")), "3 chars");
        compare(C.meta(item("a")), "1 char");
        compare(C.meta(item("a\nbc")), "2 lines · 4 chars");
        compare(C.meta({ kind: "image", path: "/x" }), "Image");
    }

    function test_age() {
        compare(C.age(0, 10000), "now");
        compare(C.age(0, 120000), "2 min");
        compare(C.age(0, 3 * 3600000), "3 h");
        compare(C.age(0, 2 * 86400000), "2 d");
        compare(C.age(5000, 1000), "now");
    }

    function test_saveRoundTrip() {
        let items = C.add([], item("a"), 1).items;
        items = C.add(items, { kind: "image", path: "/x.png" }, 2).items;
        items = C.togglePin(items, items[1].id);
        const back = C.parse(JSON.stringify(C.serialize(items)));
        compare(back, items);
    }

    function test_parseToleratesJunk() {
        compare(C.parse("not json"), null);
        compare(C.parse("{}"), []);
        compare(C.parse(JSON.stringify({ items: [null, { id: "1", kind: "text", text: "", t: 1 }, { id: "2", kind: "text", text: "ok", t: 2 }, { id: "3", kind: "text", text: "ok", t: 3 }, { id: "4", kind: "bogus", t: 4 }] })).map(i => i.text), ["ok"]);
    }
}
