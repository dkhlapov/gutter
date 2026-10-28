.pragma library

// Browsers report every tab with sound (videos, calls) and playerctld mirrors whichever player is active,
// so only dedicated players (Spotify, Deezer, ...) reach the pill. Zen shows up as "Mozilla zen" / "zen".
// Electron apps sit on org.mpris.MediaPlayer2.chromium.* names but give their own identity, so the bus
// name only rules out Firefox forks and playerctld.
var BROWSERS = /\b(firefox|zen|librewolf|floorp|waterfox|mullvad browser|tor browser|chrome|google-chrome|chromium|brave|brave-browser|vivaldi|opera|microsoft-edge|edge|epiphany|gnome web|falkon|qutebrowser|midori|plasma-browser-integration)\b/i;
var BROWSER_BUS = /^org\.mpris\.MediaPlayer2\.(firefox|librewolf|floorp|waterfox|playerctld)\b/;

function isMusicPlayer(p) {
    if (BROWSER_BUS.test(String(p.dbusName ?? "")))
        return false;
    return ![p.identity, p.desktopEntry].some(s => BROWSERS.test(String(s ?? "")));
}

// A manually chosen player wins unless it is paused while another one plays.
function pick(players, manualId) {
    if (players.length === 0)
        return -1;
    const manual = players.findIndex(p => p.id === manualId);
    const playing = players.findIndex(p => p.isPlaying);
    if (manual !== -1 && (players[manual].isPlaying || playing === -1))
        return manual;
    if (playing !== -1)
        return playing;
    return manual !== -1 ? manual : 0;
}

// The player the media keys act on: the one the UI shows (activeId) while it plays, else any player that is playing
// (a browser tab, say: the pill hides browsers but the keys never did), else the shown one, else the first. `players`
// is every Mpris player, browsers included; returns an index into it, -1 for none.
function pickKeyTarget(players, activeId) {
    if (!players || players.length === 0)
        return -1;
    const active = activeId ? players.findIndex(p => p.id === activeId) : -1;
    if (active !== -1 && players[active].isPlaying)
        return active;
    const playing = players.findIndex(p => p.isPlaying);
    if (playing !== -1)
        return playing;
    return active !== -1 ? active : 0;
}

function trackKey(title, artist) {
    return title ? `${artist}\u0000${title}` : "";
}

// Empty keys (metadata flicker) never replace the last track, so the same track is not announced twice.
function announce(lastKey, key, isPlaying, sinceStartMs) {
    if (!key)
        return { announce: false, lastKey };
    return { announce: key !== lastKey && isPlaying && sinceStartMs > 2000, lastKey: key };
}

// MprisLoopState values: None 0, Track 1, Playlist 2. Off → whole playlist → one track → off.
function nextLoop(state) {
    return state === 0 ? 2 : state === 2 ? 1 : 0;
}
