pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../lib/players.js" as PlayersLib
import "../lib/position.js" as PositionLib
import "../lib/activities.js" as ActLib

Singleton {
    id: root

    property string manualId: ""
    readonly property var players: Mpris.players.values.filter(p => PlayersLib.isMusicPlayer(p))
    readonly property MprisPlayer active: {
        const i = PlayersLib.pick(players.map(p => ({ id: p.dbusName, isPlaying: p.isPlaying })), manualId);
        return i < 0 ? null : players[i];
    }
    // What the media keys act on: the shown player while it plays, else any playing one (a browser tab, which the pill
    // hides but the keys always controlled), else the shown one, else the first.
    readonly property MprisPlayer keyTarget: {
        const all = Mpris.players.values;
        const i = PlayersLib.pickKeyTarget(all.map(p => ({ id: p.dbusName, isPlaying: p.isPlaying })), active?.dbusName ?? "");
        return i < 0 ? null : all[i];
    }
    readonly property bool playing: active?.isPlaying ?? false
    readonly property string title: active?.trackTitle ?? ""
    readonly property string artist: active?.trackArtist ?? ""
    readonly property string album: active?.trackAlbum ?? ""
    readonly property string artUrl: active?.trackArtUrl ?? ""
    // 0 when the player does not report a length: Quickshell then returns the position, which would change the
    // lyrics track every second.
    readonly property real length: active?.lengthSupported ? active.length : 0
    // Not MprisPlayer.position: Quickshell only re-reads it when the player pauses or resumes, so after a track
    // change it keeps counting from the old track's position. This is extrapolated from our own anchor, which a
    // read of the D-Bus Position property sets (see resync, lib/position.js).
    readonly property real position: PositionLib.positionAt(anchor, now, playing, length)
    readonly property string trackKey: PlayersLib.trackKey(title, artist)
    readonly property bool canShuffle: active?.shuffleSupported ?? false
    readonly property bool shuffle: active?.shuffle ?? false
    readonly property bool canLoop: active?.loopSupported ?? false
    readonly property int loopState: active?.loopState ?? 0
    // The Lyrics singleton only fetches for the track it is told about. Bindings re-run when any read
    // property changes, so a new track or player re-targets the lyrics.
    readonly property string lyricsTrack: {
        if (active)
            Lyrics.setTrack(artist, title, album, length);
        else
            Lyrics.clearTrack();
        return trackKey;
    }
    readonly property var cava: Cava

    property var anchor: ({ seconds: 0, atMs: Date.now() })
    // The wall clock as of the last tick; what position is extrapolated to.
    property real now: Date.now()
    property string lastKey: ""
    readonly property real startedAt: Date.now()

    function select(id: string): void {
        manualId = id;
    }

    function togglePlaying(): void {
        if (active?.canTogglePlaying)
            active.togglePlaying();
    }

    function next(): void {
        if (active?.canGoNext)
            active.next();
    }

    function previous(): void {
        if (active?.canGoPrevious)
            active.previous();
    }

    function stop(): void {
        if (active?.canControl)
            active.stop();
    }

    function keyToggle(): void {
        if (keyTarget?.canTogglePlaying)
            keyTarget.togglePlaying();
    }

    function keyNext(): void {
        if (keyTarget?.canGoNext)
            keyTarget.next();
    }

    function keyPrevious(): void {
        if (keyTarget?.canGoPrevious)
            keyTarget.previous();
    }

    function keyStop(): void {
        if (keyTarget?.canControl)
            keyTarget.stop();
    }

    function seek(seconds: real): void {
        // Without a known length there is nothing to clamp to (every seek would go to 0).
        if (active?.canSeek && length > 0) {
            const to = Math.max(0, Math.min(length, seconds));
            active.position = to;
            anchor = PositionLib.anchorFrom(to, Date.now(), Date.now());
            now = Date.now();
            settle.left = 1;
            settle.restart();
        }
    }

    // Reads the player's real position into the anchor. One read at a time; one asked for while another runs is
    // done right after it.
    function resync(): void {
        if (!active)
            return;
        if (reader.running) {
            reader.again = true;
            return;
        }
        reader.player = active.dbusName;
        reader.sentAt = Date.now();
        reader.command = ["busctl", "--user", "get-property", active.dbusName, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Position"];
        reader.running = true;
    }

    // A new track or player starts at 0 until the read says otherwise.
    function anchorAndResync(seconds: real): void {
        anchor = PositionLib.anchorFrom(seconds, Date.now(), Date.now());
        now = Date.now();
        resync();
        // Some players announce the new track before they reset the position.
        settle.left = 3;
        settle.restart();
    }

    function toggleShuffle(): void {
        if (canShuffle)
            active.shuffle = !active.shuffle;
    }

    function cycleLoop(): void {
        if (canLoop)
            active.loopState = PlayersLib.nextLoop(active.loopState);
    }

    onTrackKeyChanged: {
        const s = PlayersLib.announce(lastKey, trackKey, playing, Date.now() - startedAt);
        lastKey = s.lastKey;
        if (s.announce)
            Activities.show("track", ActLib.PRIORITY.trackChange, 4000, "music");
        anchorAndResync(0);
    }

    // A pause or resume re-reads at once.
    onPlayingChanged: {
        resync();
    }

    onActiveChanged: {
        anchorAndResync(0);
        if (!active)
            Activities.hide("track");
    }

    // MPRIS does not push position updates: move the clock while playing, and re-anchor on the player's real
    // position every few seconds (the extrapolation drifts, and a seek by the player's own UI sends no signal).
    Timer {
        running: root.playing
        interval: 500
        repeat: true
        onTriggered: root.now = Date.now()
    }

    Timer {
        running: root.playing
        interval: 3000
        repeat: true
        onTriggered: root.resync()
    }

    // The follow-up reads after a track change or a seek: a player may go on reporting the old position for a
    // second or so (measured: Deezer in a browser, about 1 s after a skip).
    Timer {
        id: settle

        property int left: 0

        interval: 700
        repeat: true
        onTriggered: {
            root.resync();
            if (--left <= 0)
                stop();
        }
    }

    Process {
        id: reader

        property string player: ""
        property real sentAt: 0
        property bool again: false

        stdout: StdioCollector {
            onStreamFinished: {
                const s = PositionLib.parseBusctl(text);
                // The player that answered is still the shown one.
                if (s !== null && reader.player === root.active?.dbusName) {
                    root.anchor = PositionLib.anchorFrom(s, reader.sentAt, Date.now());
                    root.now = Date.now();
                }
            }
        }
        onExited: {
            if (again) {
                again = false;
                root.resync();
            }
        }
    }
}
