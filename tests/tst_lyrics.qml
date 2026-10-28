import QtQuick
import QtTest
import "../lib/lyrics.js" as L

TestCase {
    name: "Lyrics"

    function test_parseLrcSimple() {
        compare(L.parseLrc("[00:12.34]hello\n[01:02.50]world"), [{ time: 12.34, text: "hello" }, { time: 62.5, text: "world" }]);
    }

    function test_parseLrcSeveralStampsOnOneLine() {
        compare(L.parseLrc("[00:10.00][00:20.50]la"), [{ time: 10, text: "la" }, { time: 20.5, text: "la" }]);
    }

    function test_parseLrcSortsByTime() {
        const lines = L.parseLrc("[00:20.00]b\n[00:10.00]a\n[00:20.00]c");
        compare(lines.map(l => l.text), ["a", "b", "c"]);
    }

    function test_parseLrcOffsetShiftsTimes() {
        // LRC convention: a positive offset is subtracted (lines come earlier), a negative one added.
        compare(L.parseLrc("[offset:500]\n[00:10.00]a"), [{ time: 9.5, text: "a" }]);
        compare(L.parseLrc("[offset:+500]\n[00:10.00]a"), [{ time: 9.5, text: "a" }]);
        compare(L.parseLrc("[00:10.00]a\n[offset:-250]"), [{ time: 10.25, text: "a" }]);
    }

    function test_parseLrcIgnoresTags() {
        compare(L.parseLrc("[ar:Queen]\n[ti:Song]\n[by:me]\n[00:01.00]x"), [{ time: 1, text: "x" }]);
    }

    function test_parseLrcKeepsEmptyText() {
        compare(L.parseLrc("[00:01.00]a\n[00:05.00]\n[00:09.00]b"), [{ time: 1, text: "a" }, { time: 5, text: "" }, { time: 9, text: "b" }]);
    }

    function test_parseLrcStampVariants() {
        // No fraction, three-digit fraction, CRLF, surrounding whitespace.
        compare(L.parseLrc("[00:03]a\r\n[00:04.123] b \r\n"), [{ time: 3, text: "a" }, { time: 4.123, text: "b" }]);
        compare(L.parseLrc("[00:04.5]x"), [{ time: 4.5, text: "x" }]);
    }

    function test_parseLrcBadInput() {
        compare(L.parseLrc(""), []);
        compare(L.parseLrc(undefined), []);
        compare(L.parseLrc("no stamps at all\njust text"), []);
    }

    function test_indexForTime() {
        const lines = L.parseLrc("[00:10.00]a\n[00:20.00]b\n[00:30.00]c");
        compare(L.indexForTime(lines, 0), -1);
        compare(L.indexForTime(lines, 9.99), -1);
        compare(L.indexForTime(lines, 10), 0);
        compare(L.indexForTime(lines, 19.99), 0);
        compare(L.indexForTime(lines, 20), 1);
        compare(L.indexForTime(lines, 300), 2);
        compare(L.indexForTime([], 5), -1);
        compare(L.indexForTime(null, 5), -1);
    }

    function test_urlEncodesAndRounds() {
        const u = L.url("A B", "T", "", 200.4);
        verify(u.indexOf("https://lrclib.net/api/get?") === 0);
        verify(u.indexOf("artist_name=A%20B") >= 0);
        verify(u.indexOf("track_name=T") >= 0);
        verify(u.indexOf("duration=200") >= 0);
        verify(u.indexOf("duration=200.") < 0);
        verify(L.url("a", "t", "", 200.5).indexOf("duration=201") >= 0);
        verify(L.url("AC/DC & co", "t", "Al#bum", 10).indexOf("artist_name=AC%2FDC%20%26%20co") >= 0);
        verify(L.url("a", "t", "Al#bum", 10).indexOf("album_name=Al%23bum") >= 0);
    }

    function test_parseResponse() {
        compare(L.parseResponse('{"syncedLyrics":"[00:01.00]hi"}'), [{ time: 1, text: "hi" }]);
        compare(L.parseResponse('{"instrumental":true,"syncedLyrics":"[00:01.00]hi"}'), []);
        compare(L.parseResponse("{"), []);
        compare(L.parseResponse('{"plainLyrics":"x"}'), []);
        compare(L.parseResponse('{"syncedLyrics":""}'), []);
        compare(L.parseResponse('{"syncedLyrics":null}'), []);
        compare(L.parseResponse("{}"), []);
        compare(L.parseResponse("[]"), []);
        compare(L.parseResponse("null"), []);
        compare(L.parseResponse(""), []);
        compare(L.parseResponse(undefined), []);
    }

    function test_cacheNameIsSafeAndStable() {
        const n = L.cacheName("AC/DC", "Back In Black", "Back In Black", 255.2);
        compare(n, L.cacheName("AC/DC", "Back In Black", "Back In Black", 254.9));
        verify(n.indexOf("/") < 0);
        verify(/^[a-z0-9._=~()!*'-]+$/.test(n), n);
        compare(n, n.toLowerCase());
        verify(L.cacheName("a", "b", "", 1) !== L.cacheName("a", "b", "", 2));
        verify(L.cacheName("a", "b", "c", 1) !== L.cacheName("a", "bc", "", 1));
        verify(L.cacheName("Кино", "Группа крови", "", 1) !== L.cacheName("Кино", "Звезда", "", 1));
        verify(n !== "." && n !== "..");
    }

    function test_cacheNameIsShort() {
        const n = L.cacheName("x".repeat(400), "y".repeat(400), "", 1);
        verify(n.length <= 200, String(n.length));
        verify(n !== L.cacheName("x".repeat(400), "y".repeat(399) + "z", "", 1));
    }

    function test_settle() {
        // A 200 is cached as received and parsed.
        let r = L.settle(200, '{"syncedLyrics":"[00:01.00]hi"}');
        compare(r.lines, [{ time: 1, text: "hi" }]);
        compare(r.cache, '{"syncedLyrics":"[00:01.00]hi"}');
        // Instrumental and plain-only answers are real answers: cached, no lines.
        r = L.settle(200, '{"instrumental":true}');
        compare(r.lines, []);
        compare(r.cache, '{"instrumental":true}');
        r = L.settle(200, '{"plainLyrics":"x"}');
        compare(r.lines, []);
        compare(r.cache, '{"plainLyrics":"x"}');
        // 404 is a miss, cached as {}.
        r = L.settle(404, '{"statusCode":404}');
        compare(r.lines, []);
        compare(r.cache, "{}");
        // Malformed 200 and failures are not cached.
        r = L.settle(200, "<html>");
        compare(r.lines, []);
        compare(r.cache, null);
        for (const status of [0, 500, 503, 429]) {
            r = L.settle(status, "");
            compare(r.lines, []);
            compare(r.cache, null);
        }
    }

    function test_fromCache() {
        compare(L.fromCache('{"syncedLyrics":"[00:01.00]hi"}'), [{ time: 1, text: "hi" }]);
        compare(L.fromCache("{}"), []);
        // A corrupt cache file is no answer at all.
        compare(L.fromCache("{"), null);
        compare(L.fromCache(""), null);
        compare(L.fromCache(undefined), null);
    }

    // A player without a length (Quickshell would report the position): no duration in the URL, a stable name.
    function test_unknownLengthLeavesDurationOut() {
        verify(L.url("a", "t", "", 0).indexOf("duration") < 0);
        verify(L.url("a", "t", "al", 0).indexOf("album_name=al") >= 0);
        compare(L.cacheName("a", "t", "", 0), L.cacheName("a", "t", "", 0.2));
        verify(L.cacheName("a", "t", "", 0) !== L.cacheName("a", "t", "", 200));
    }

    function test_searchUrl() {
        compare(L.searchUrl("AC/DC", "T & U"), "https://lrclib.net/api/search?track_name=T%20%26%20U&artist_name=AC%2FDC");
    }

    function results() {
        return JSON.stringify([
            { duration: 100, syncedLyrics: null, plainLyrics: "x" },
            { duration: 205, syncedLyrics: "[00:01.00]far" },
            { duration: 201, syncedLyrics: "[00:01.00]near" },
            { duration: 198, syncedLyrics: "" },
            { duration: 203, syncedLyrics: "[00:01.00]mid" }
        ]);
    }

    function test_pickSearchClosestDurationWins() {
        compare(L.pickSearchResult(results(), 200).syncedLyrics, "[00:01.00]near");
        compare(L.pickSearchResult(results(), 205).syncedLyrics, "[00:01.00]far");
    }

    function test_pickSearchIgnoresEntriesWithoutSyncedLyrics() {
        compare(L.pickSearchResult(results(), 100), null);
        compare(L.pickSearchResult(JSON.stringify([{ duration: 1, plainLyrics: "x" }, { instrumental: true, syncedLyrics: "[00:01.00]x", duration: 1 }]), 1), null);
    }

    function test_pickSearchRejectsFarOffDurations() {
        compare(L.pickSearchResult(JSON.stringify([{ duration: 211, syncedLyrics: "[00:01.00]x" }]), 200), null);
        compare(L.pickSearchResult(JSON.stringify([{ duration: 210, syncedLyrics: "[00:01.00]x" }]), 200).duration, 210);
        // No duration on the entry while the length is known: cannot be matched.
        compare(L.pickSearchResult(JSON.stringify([{ syncedLyrics: "[00:01.00]x" }]), 200), null);
    }

    function test_pickSearchWithoutLengthTakesFirstSynced() {
        compare(L.pickSearchResult(results(), 0).syncedLyrics, "[00:01.00]far");
    }

    function test_pickSearchNone() {
        compare(L.pickSearchResult("[]", 200), null);
        compare(L.pickSearchResult("{}", 200), null);
        compare(L.pickSearchResult("<html>", 200), null);
        compare(L.pickSearchResult("null", 0), null);
        compare(L.pickSearchResult("", 0), null);
    }

    function test_wantsSearch() {
        verify(L.wantsSearch(404, '{"statusCode":404}'));
        verify(L.wantsSearch(200, '{"plainLyrics":"x"}'));
        verify(L.wantsSearch(200, '{"syncedLyrics":""}'));
        verify(!L.wantsSearch(200, '{"syncedLyrics":"[00:01.00]hi"}'));
        verify(!L.wantsSearch(200, '{"instrumental":true}'));
        verify(!L.wantsSearch(200, "<html>"));
        for (const status of [0, 429, 500, 503])
            verify(!L.wantsSearch(status, ""));
    }

    function test_settleSearch() {
        let r = L.settleSearch(200, results(), 200);
        compare(r.lines, [{ time: 1, text: "near" }]);
        compare(L.fromCache(r.cache), [{ time: 1, text: "near" }]);
        // No match is a miss, cached as {}.
        r = L.settleSearch(200, "[]", 200);
        compare(r.lines, []);
        compare(r.cache, "{}");
        // A failure or a page that is not JSON is not an answer.
        for (const [status, text] of [[0, ""], [500, "[]"], [429, ""], [200, "<html>"]]) {
            r = L.settleSearch(status, text, 200);
            compare(r.lines, []);
            compare(r.cache, null);
        }
    }

    function test_offsetIsAppliedOnceAndTheLineChangesAtItsStamp() {
        // From an lrclib answer to the highlighted line: the offset moves the stamps once, and there is no lookahead.
        const lines = L.parseResponse(JSON.stringify({ syncedLyrics: "[offset:500]\n[00:10.00]a\n[00:20.00]b" }));
        compare(L.indexForTime(lines, 9.49), -1);
        compare(L.indexForTime(lines, 9.5), 0);
        compare(L.indexForTime(lines, 19.49), 0);
        compare(L.indexForTime(lines, 19.5), 1);
    }
}
