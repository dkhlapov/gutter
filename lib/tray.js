.pragma library

// Some tray items name their icon as "<file>?path=<dir>": the file sits in a private theme directory.
// Returns { name, path } with the bare file name and that directory, or null for any other icon string.
function iconParts(icon) {
    const at = icon.indexOf("?path=");
    if (at < 0)
        return null;
    const name = icon.slice(0, at);
    return { name: name.slice(name.lastIndexOf("/") + 1), path: icon.slice(at + "?path=".length) };
}

// The icon theme name an item's `icon` string stands for: without the "image://icon/" prefix, a "?path=<dir>"
// tail, a directory in front or an image extension ("" when there is no icon, or the image is not a themed one).
function iconName(icon) {
    // Pixmap items (image://qsimage/...) have no theme name.
    if (/^image:\/\/(?!icon\/)/.test(icon))
        return "";
    const parts = iconParts(icon);
    const name = parts !== null ? parts.name : icon.replace(/^image:\/\/icon\//, "");
    return name.slice(name.lastIndexOf("/") + 1).replace(/\.(png|svg|xpm)$/i, "");
}

// The first of `candidates` that is not blank (trimmed), else "". Items send undefined, null or "" for what they
// lack.
function firstName(candidates) {
    for (const c of candidates) {
        const text = c ? String(c).trim() : "";
        if (text !== "")
            return text;
    }
    return "";
}

// Where a menu of `height` x `width` goes inside a panel of boundW x boundH: its left edge at `anchorX` but
// pulled back so it, and `margin` for its shadow, stay inside the right edge; top at `y`. When it is taller
// than the room left below `y` (less `margin`), `height` is cut to that room and `scrolls` is true.
// The room is never negative, and the left edge never goes past 0.
function placeMenu(anchorX, y, width, height, boundW, boundH, margin) {
    const x = Math.max(0, Math.min(anchorX, boundW - width - margin));
    const room = Math.max(0, boundH - y - margin);
    return { x, y, height: Math.min(height, room), scrolls: height > room };
}

// What a click on a tray button does: "menu" opens the item's menu, "activate" / "secondary" call the item.
// `button` is "left", "middle" or "right". Left click opens the menu and right click shows the app (activates
// it); an item without a menu is activated by either, and one that only has a menu opens it on either.
function clickAction(button, onlyMenu, hasMenu) {
    if (button === "middle")
        return "secondary";
    if (!hasMenu)
        return "activate";
    return button === "left" || onlyMenu ? "menu" : "activate";
}

// True when `entries` (menu entries with isSeparator) hold anything to click: a menu of nothing, or of separators
// only, is not worth a box.
function hasEntries(entries) {
    return entries.some(e => !e.isSeparator);
}

// A tooltip's description as plain text: items may send markup (bold, line breaks, entities).
function plainText(markup) {
    return String(markup)
        .replace(/<br\s*\/?>/gi, "\n")
        .replace(/<[^>]*>/g, "")
        .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'")
        .replace(/&amp;/g, "&")
        .trim();
}

// What the hover tooltip shows for an item: { title, body }, title "" when there is only a name to show, or
// null when the item gives nothing at all. `name` is the item's own (see Tray.name); the tooltip title is its
// tooltip title, else that name.
function tooltip(name, tooltipTitle, tooltipDescription) {
    name = firstName([tooltipTitle, name]);
    const body = plainText(tooltipDescription || "");
    if (body === "" || body === name)
        return name === "" ? null : { title: "", body: name };
    return { title: name, body: body };
}
