.pragma library

// What to call an application whose only name is an id: a window class (`com.anthropic.claude`,
// `org.telegram.desktop`, `firefox`) or the name a notification sender gave. A few ids read badly even tidied,
// so they are listed; the rest lose their reverse-DNS prefix and read as words.
var KNOWN = {
    "com.anthropic.claude": "Claude",
    "gutter": "Gutter",
    "org.telegram.desktop": "Telegram",
    "telegramdesktop": "Telegram",
    "dev.zed.zed": "Zed",
    "code-oss": "VS Code",
    "code": "VS Code",
    "org.mozilla.firefox": "Firefox",
    "kitty": "Kitty",
    "org.gnome.nautilus": "Files",
    "org.kde.dolphin": "Files"
};

// Trailing segments that name nothing: `org.telegram.desktop` is Telegram, not Desktop.
var GENERIC = /^(desktop|app|client|gui|main|stable)$/i;
var DOMAIN = /^(com|org|net|io|dev|app|de|fr|uk|ru|me|so|co)$/i;

function words(s) {
    return s.replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim().replace(/(^|\s)(\S)/g, (m, sp, c) => sp + c.toUpperCase());
}

// The name to show for `id`; an empty or missing id gives "".
function displayName(id) {
    const raw = typeof id === "string" ? id.trim() : "";
    if (raw === "")
        return "";
    const key = raw.toLowerCase();
    if (Object.prototype.hasOwnProperty.call(KNOWN, key))
        return KNOWN[key];
    const parts = raw.split(".").filter(p => p !== "");
    if (parts.length >= 3 && DOMAIN.test(parts[0])) {
        let i = parts.length - 1;
        while (i > 1 && GENERIC.test(parts[i]))
            i--;
        return words(parts[i]);
    }
    // Already a name with a capital or a space (Discord, "Google Chrome"): the sender's spelling stands.
    if (/[A-Z ]/.test(raw))
        return raw;
    return words(raw);
}
