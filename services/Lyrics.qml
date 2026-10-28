pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/lyrics.js" as LyricsLib

// Synced lyrics for the track Media tells us about (Media.lyricsTrack calls setTrack/clearTrack), from
// lrclib.net (the exact match, then its search by title and artist). The answer is cached in
// <state>/gutter/lyrics/<name>.json (a miss as {}), read before any request; a network failure is not cached, so
// the next time the track is set it is asked again. Until the answer for the current track is in, and for every
// answer without synced lyrics, `lyrics` is empty: a line of another track is never shown.
Singleton {
    id: root

    // The lines of the current track: { time (seconds), text }.
    property var lines: []
    readonly property var lyrics: lines.map(l => l.text)
    readonly property bool hasLyrics: lines.length > 0

    readonly property string dir: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/gutter/lyrics`
    // A request that hangs gives up after this long.
    readonly property int timeoutMs: 8000

    // The current track's cache name and the generation counter. A plain object, not properties: setTrack runs
    // inside Media's lyricsTrack binding, which must not read anything it writes (so `lines` is only ever
    // assigned there, never read). Every setTrack to another
    // track and every clearTrack bumps gen, and an answer for an older gen is dropped.
    readonly property var memo: ({ key: "", gen: 0 })

    function indexForTime(seconds: real): int {
        return LyricsLib.indexForTime(lines, seconds);
    }

    function setTrack(artist: string, title: string, album: string, length: real): void {
        if (!artist && !title) {
            clearTrack();
            return;
        }
        // A length of 0 (the player reports none) is part of the key and leaves the duration out of the request.
        const key = LyricsLib.cacheName(artist, title, album, length);
        if (key === memo.key)
            return;
        memo.key = key;
        const gen = ++memo.gen;
        lines = [];
        readCache(key, gen, () => lookup(artist, title, album, length, key, gen));
    }

    function clearTrack(): void {
        memo.key = "";
        memo.gen++;
        lines = [];
    }

    // Shows the cached answer, or calls `miss` when there is none (no file, or one that is not JSON).
    function readCache(key: string, gen: int, miss: var): void {
        readerComponent.createObject(root, { path: `${dir}/${key}.json`, done: text => {
            if (gen !== memo.gen)
                return;
            const cached = LyricsLib.fromCache(text);
            if (cached === null)
                miss();
            else
                lines = cached;
        } });
    }

    function writeCache(key: string, text: string): void {
        // The text travels as an argument (limit 131072 bytes, up to 3 per UTF-16 unit): skip a freak answer.
        if (text.length > 40000)
            return;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && printf "%s" "$2" > "$1/$3.tmp" && mv "$1/$3.tmp" "$1/$3.json"', "sh", dir, text, key]);
    }

    // The lookup: lrclib's exact match first; when that finds nothing (a 404, or no synced lyrics), its search by
    // title and artist, taking the entry whose duration is closest to the track's. The final outcome, found or
    // not, is cached; a failure anywhere is not, so the track is asked again next time.
    function lookup(artist: string, title: string, album: string, length: real, key: string, gen: int): void {
        request(LyricsLib.url(artist, title, album, length), gen, (status, text) => {
            if (!LyricsLib.wantsSearch(status, text)) {
                settled(LyricsLib.settle(status, text), status, key, gen);
                return;
            }
            // Nothing to search for once the track has changed.
            if (gen !== memo.gen)
                return;
            request(LyricsLib.searchUrl(artist, title), gen, (status2, text2) => {
                settled(LyricsLib.settleSearch(status2, text2, length), status2, key, gen);
            });
        });
    }

    // `r` is { lines, cache } from LyricsLib.settle or settleSearch.
    function settled(r: var, status: int, key: string, gen: int): void {
        if (r.cache !== null)
            writeCache(key, r.cache);
        else if (gen === memo.gen)
            console.warn(`gutter: lyrics: no usable answer (HTTP ${status})`);
        // The track changed (or was cleared) while this was in flight.
        if (gen === memo.gen)
            lines = r.lines;
    }

    // One GET; `done(status, text)` runs once, with status 0 when the request hung past the watchdog.
    function request(url: string, gen: int, done: var): void {
        const xhr = new XMLHttpRequest();
        // Settled once: by the response or by the watchdog, whichever comes first.
        let finished = false;
        const watchdog = watchdogComponent.createObject(root);
        watchdog.triggered.connect(() => {
            watchdog.destroy();
            if (finished)
                return;
            finished = true;
            xhr.abort();
            if (gen === memo.gen)
                console.warn("gutter: lyrics: request timed out");
            done(0, "");
        });
        watchdog.start();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || finished)
                return;
            finished = true;
            watchdog.stop();
            watchdog.destroy();
            done(xhr.status, xhr.responseText);
        };
        xhr.open("GET", url);
        xhr.setRequestHeader("User-Agent", "Gutter shell (lrclib client)");
        xhr.send();
    }

    // One `cat` per lookup; an absent file reads as empty text.
    Component {
        id: readerComponent

        Process {
            id: reader

            required property string path
            required property var done

            command: ["sh", "-c", '[ -f "$1" ] && cat "$1"; true', "sh", path]
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    reader.done(text);
                    reader.destroy();
                }
            }
        }
    }

    Component {
        id: watchdogComponent

        Timer {
            interval: root.timeoutMs
        }
    }
}
