.pragma library

// The playback position Media shows. Quickshell's MprisPlayer.position is extrapolated from the last position it
// read and is only re-read when the player pauses or resumes: after a track change it keeps counting from the
// OLD track's position (measured: 84 s -> 100 s while the player was at 0 s -> 16 s), and over a track it
// drifts by a fraction of a second. So Media keeps its own anchor { seconds, atMs } and re-reads the D-Bus
// Position property into it. Times are seconds (anchors: wall-clock milliseconds), as in Mpris.

// The anchor for a reply to a read of Position. The player's value is as of about when it answered, which is
// halfway between the request and the reply.
function anchorFrom(seconds, requestedAtMs, repliedAtMs) {
    return { seconds, atMs: (requestedAtMs + repliedAtMs) / 2 };
}

// The position at `nowMs`: the anchor plus the time since, while playing; the anchor itself while paused. Never
// before the anchor (a clock step back), never past `length` seconds when it is known (> 0).
function positionAt(anchor, nowMs, playing, length) {
    let s = anchor.seconds;
    if (playing)
        s += Math.max(0, nowMs - anchor.atMs) / 1000;
    if (length > 0 && s > length)
        s = length;
    return Math.max(0, s);
}

// Seconds from the text `busctl --user get-property ... Position` prints ("x 59279759", microseconds), null
// when it is anything else (the player went away, an error message, a negative or missing number).
function parseBusctl(text) {
    const m = /^\s*x\s+(\d+)\s*$/.exec(String(text ?? ""));
    return m ? Number(m[1]) / 1e6 : null;
}
