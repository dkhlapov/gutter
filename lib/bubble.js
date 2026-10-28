.pragma library

// The shape of SpeechBubble, apart from the drawing: where its tail's tip sits and which points are on the balloon.

// The tip's x along the top edge: `tailX` (0..1) of the width, kept `pad` clear of the corners, the tail's base
// and the outline (`lineWidth`, centred on the edge) included.
function tailCentre(width, tailX, tailHalfBase, lineWidth, pad) {
    const lo = lineWidth / 2 + tailHalfBase + pad;
    const hi = width - lineWidth / 2 - tailHalfBase - pad;
    return Math.max(lo, Math.min(hi, tailX * width));
}

// Whether (x, y), from the bubble's top left, is on the balloon: the body below the tail's height, or inside the
// tail's triangle (tip at the top, base on the body's top edge), but not the empty corners beside the tail.
function contains(x, y, width, height, tailHeight, centre, tailHalfBase) {
    if (x < 0 || x > width || y < 0 || y > height)
        return false;
    if (y >= tailHeight)
        return true;
    return Math.abs(x - centre) <= tailHalfBase * y / tailHeight;
}
