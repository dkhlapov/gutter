.pragma library

var NOTCH = 120;

// The vertical part of a wheel event's `angleDelta` ({ x, y }): y when the event is vertical or diagonal with
// y at least as big as x, else 0. A horizontal or mostly horizontal event is not a vertical step.
function vertical(angleDelta) {
    return Math.abs(angleDelta.y) >= Math.abs(angleDelta.x) ? angleDelta.y : 0;
}

// Hi-res wheels and touchpads send fractions of a notch: whole notches become steps and the
// remainder is kept for the next event. Turning the other way drops the remainder, so a reversal
// never jumps.
function accumulate(rest, delta) {
    const r = (rest > 0 && delta < 0) || (rest < 0 && delta > 0) ? delta : rest + delta;
    const steps = Math.trunc(r / NOTCH) + 0; // + 0 turns -0 into 0
    return { rest: r - steps * NOTCH, steps };
}
