.pragma library

// The geometry of a scroll bar (components/InkScrollBar.qml), all lengths along the scrolling axis.
// `view` is the visible length, `content` the whole, `pos` how far the view has scrolled (contentY - originY),
// `track` the bar's length and `min` the shortest thumb (a long list would shrink it to nothing).

// True when there is something to scroll to.
function needed(view, content) {
    return view > 0 && content > view + 0.5;
}

// The thumb's length and its offset from the track's start, kept inside the track while the list overshoots.
function thumb(view, content, pos, track, min) {
    if (!needed(view, content))
        return { length: track, offset: 0 };
    const length = Math.min(track, Math.max(min, track * view / content));
    const range = content - view;
    const offset = (track - length) * Math.max(0, Math.min(1, pos / range));
    return { length, offset };
}

// The scroll position that puts the thumb's start at `offset`: the inverse of thumb().
function posAt(view, content, offset, track, min) {
    const t = thumb(view, content, 0, track, min);
    const free = track - t.length;
    if (!needed(view, content) || free <= 0)
        return 0;
    return (content - view) * Math.max(0, Math.min(1, offset / free));
}
