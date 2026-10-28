import QtQuick
import QtTest
import "../lib/players.js" as P

TestCase {
    name: "Players"

    // Review focus 2: no players at all.
    function test_pickNone() {
        compare(P.pick([], ""), -1);
    }

    function test_pickPlayingOverFirst() {
        compare(P.pick([{ id: "a", isPlaying: false }, { id: "b", isPlaying: true }], ""), 1);
    }

    function test_manualWinsWhenPlayingOrNothingPlays() {
        const ps = [{ id: "a", isPlaying: false }, { id: "b", isPlaying: false }];
        compare(P.pick(ps, "b"), 1);
        compare(P.pick([{ id: "a", isPlaying: true }, { id: "b", isPlaying: true }], "b"), 1);
    }

    function test_playingBeatsPausedManual() {
        compare(P.pick([{ id: "a", isPlaying: true }, { id: "b", isPlaying: false }], "b"), 0);
    }

    function test_browsersAreNotMusicPlayers() {
        verify(!P.isMusicPlayer({ identity: "Mozilla zen", desktopEntry: "zen", dbusName: "org.mpris.MediaPlayer2.firefox.instance_1_632" }));
        verify(!P.isMusicPlayer({ identity: "Mozilla zen", desktopEntry: "zen", dbusName: "org.mpris.MediaPlayer2.playerctld" }));
        verify(!P.isMusicPlayer({ identity: "Chromium", desktopEntry: "chromium", dbusName: "org.mpris.MediaPlayer2.chromium.instance42" }));
        verify(P.isMusicPlayer({ identity: "Spotify", desktopEntry: "spotify", dbusName: "org.mpris.MediaPlayer2.spotify" }));
        // Electron apps sit on a chromium.* bus name but name themselves.
        verify(P.isMusicPlayer({ identity: "Deezer", desktopEntry: "deezer-desktop", dbusName: "org.mpris.MediaPlayer2.chromium.instance7" }));
    }

    function test_manualGoneFallsBack() {
        compare(P.pick([{ id: "a", isPlaying: false }], "zzz"), 0);
    }

    function test_trackKey() {
        compare(P.trackKey("", "Artist"), "");
        verify(P.trackKey("Song", "A") !== P.trackKey("Song", "B"));
    }

    function test_announceNewTrackWhilePlaying() {
        compare(P.announce("x", "y", true, 5000), { announce: true, lastKey: "y" });
    }

    function test_noAnnounceDuringStartupOrPaused() {
        compare(P.announce("", "y", true, 500).announce, false);
        compare(P.announce("x", "y", false, 5000).announce, false);
        compare(P.announce("x", "y", false, 5000).lastKey, "y");
    }

    // Review focus 3: title flickers empty during a track change.
    function test_flickerDoesNotReannounce() {
        let s = P.announce("x", "", true, 5000);
        compare(s, { announce: false, lastKey: "x" });
        s = P.announce(s.lastKey, "x", true, 5100);
        compare(s.announce, false);
    }

    // MprisLoopState: None = 0, Track = 1, Playlist = 2. The button cycles off → all → one → off.
    function test_nextLoop() {
        compare(P.nextLoop(0), 2);
        compare(P.nextLoop(2), 1);
        compare(P.nextLoop(1), 0);
    }

    // Media keys: the shown player while it plays, else anything playing (a browser), else the shown one, else the first.
    function test_pickKeyTarget() {
        const all = [{ id: "browser", isPlaying: true }, { id: "spotify", isPlaying: false }, { id: "other", isPlaying: false }];
        compare(P.pickKeyTarget(all, "spotify"), 0); // paused music player, playing browser tab
        compare(P.pickKeyTarget([{ id: "browser", isPlaying: true }, { id: "spotify", isPlaying: true }], "spotify"), 1);
        compare(P.pickKeyTarget([{ id: "browser", isPlaying: false }, { id: "spotify", isPlaying: false }], "spotify"), 1);
        compare(P.pickKeyTarget(all, ""), 0);
        compare(P.pickKeyTarget(all, "gone"), 0);
        compare(P.pickKeyTarget([{ id: "a", isPlaying: false }, { id: "b", isPlaying: true }], ""), 1);
        compare(P.pickKeyTarget([{ id: "a", isPlaying: false }, { id: "b", isPlaying: false }], ""), 0);
        compare(P.pickKeyTarget([], "a"), -1);
        compare(P.pickKeyTarget(null, ""), -1);
    }
}
