.pragma library
.import "glyphs.js" as Glyphs

// Nerd Font glyphs for the status row's chips. The volume ones come from glyphs.js, the same as the pill's volume
// HUD. Wi-Fi off and wired use Material Design glyphs (U+F05AA, U+F0200): the Font Awesome 5 ones the plan listed
// (U+F6AC, U+F6FF) are not in JetBrainsMono Nerd Font v3 and drew as empty boxes.

// Muted, then the three levels. A cell reserves the widest of them, so it does not change width with the volume.
var VOLUME_ICONS = ["volume_off", "volume_mute", "volume_down", "volume_up"].map(Glyphs.glyph);

function volumeIcon(volume, muted) {
    if (muted || volume <= 0)
        return VOLUME_ICONS[0];
    if (volume < 0.34)
        return VOLUME_ICONS[1];
    if (volume < 0.67)
        return VOLUME_ICONS[2];
    return VOLUME_ICONS[3];
}

function micIcon(muted) {
    return muted ? "" : "";
}

// `wired` is optional: a cable shows the network-wired glyph whatever the Wi-Fi strength.
function wifiIcon(strength, connected, wired) {
    if (wired)
        return "󰈀";
    return connected ? "" : "󰖪";
}

// Bluetooth off, on with nothing connected, on with a device connected (Material Design glyphs).
function bluetoothIcon(powered, connectedCount) {
    if (!powered)
        return "󰂲";
    return connectedCount > 0 ? "󰂱" : "󰂯";
}

// The Bluetooth cell's label: nothing unless a device is connected, then its name for one device, else the count.
function bluetoothText(powered, names) {
    if (!powered || names.length === 0)
        return "";
    return names.length === 1 ? names[0] : String(names.length);
}

// The Bluetooth cell's tooltip body: the state, then the connected devices' names.
function bluetoothTip(powered, names) {
    if (!powered)
        return "Off";
    if (names.length === 0)
        return "On, no devices connected";
    return "Connected: " + names.join(", ");
}

// The network cell's tooltip body.
function wifiTip(connected, wired, ssid, strength) {
    if (!connected)
        return "Not connected";
    if (wired)
        return "Wired";
    return `${ssid}, signal ${strength}%`;
}

// Two letters for a layout name; the common ones are fixed so they read as the usual codes
// ("Swedish" is SE, not SW).
function kbShort(layoutName) {
    if (!layoutName)
        return "--";
    if (layoutName.startsWith("Swedish"))
        return "SE";
    if (layoutName.startsWith("Russian"))
        return "RU";
    if (layoutName === "English (US)")
        return "US";
    return layoutName.slice(0, 2).toUpperCase();
}

function percent(v) {
    return Math.max(0, Math.min(100, Math.round(v * 100))) + "%";
}

// The active layout of the main keyboard in `hyprctl devices -j` output, else the first keyboard's; "" when
// the output has no keyboards or is not JSON.
function mainLayout(devicesJson) {
    let keyboards;
    try {
        keyboards = JSON.parse(devicesJson).keyboards;
    } catch (e) {
        return "";
    }
    if (!Array.isArray(keyboards) || keyboards.length === 0)
        return "";
    const main = keyboards.find(k => k.main) ?? keyboards[0];
    return main.active_keymap ?? "";
}

// The keyboard-layout state after a refresh: `prev` (the last good name, "" before the first) is kept when
// the refresh gave nothing, and `available` says whether this refresh found a keyboard.
function layoutState(prev, devicesJson) {
    const name = mainLayout(devicesJson);
    return { layout: name === "" ? prev : name, available: name !== "" };
}
