.pragma library

// The libs name icons after Material Symbols (WeatherLib.icon returns "rainy", "clear_night", ShelfLib.icon
// returns "folder", "movie", VolumeLib.icon returns "volume_up", ...). Gutter draws Nerd Font glyphs, so this
// one table maps those names; views call glyph() and never switch on a name themselves. Two families, both
// from JetBrainsMono Nerd Font: weather is Weather Icons (U+E3xx), everything else is Material Design Icons
// (plane 15, U+F0000 and up).
// Add a row here when a lib function starts returning a new name; tests/tst_glyphs.qml walks every name
// WeatherLib.icon, ShelfLib.icon, VolumeLib.icon and KeysLib.icon can return, and tests/test_glyph_usage.py
// scans the QML for the names written out in Glyphs.glyph(...) calls; both fail on a name without a row.
var TABLE = {
    clear_day: "\ue30d", // weather-day_sunny
    clear_night: "\ue32b", // weather-night_clear
    partly_cloudy_day: "\ue302", // weather-day_cloudy
    partly_cloudy_night: "\ue37e", // weather-night_alt_cloudy
    cloud: "\ue312", // weather-cloudy
    foggy: "\ue313", // weather-fog
    rainy: "\ue318", // weather-rain
    cloudy_snowing: "\ue31a", // weather-snow
    snowing_heavy: "\ue35e", // weather-snow_wind
    thunderstorm: "\ue31d", // weather-thunderstorm
    air: "\ue31e", // weather-windy
    folder: "\u{f024b}", // md-folder
    image: "\u{f02e9}", // md-image
    movie: "\u{f0381}", // md-movie
    music_note: "\u{f0387}", // md-music_note
    picture_as_pdf: "\u{f0226}", // md-file_pdf_box
    folder_zip: "\u{f06eb}", // md-folder_zip
    code: "\u{f0174}", // md-code_tags
    description: "\u{f0219}", // md-file_document
    draft: "\u{f0214}", // md-file
    unknown_document: "\u{f086f}", // md-file_question: a held file that is gone
    volume_up: "\u{f057e}", // md-volume_high
    volume_down: "\u{f0580}", // md-volume_medium
    volume_mute: "\u{f057f}", // md-volume_low: the speaker with no waves: volume at 0 (pill HUD) or low (status row)
    volume_off: "\u{f075f}", // md-volume_mute: the speaker crossed out, muted
    // Activities and HUDs (timer, agent, notification, brightness and keys views; the notification history).
    alarm: "\u{f0020}", // md-alarm
    timer: "\u{f13ab}", // md-timer
    timer_play: "\u{f1ae0}", // md-timer_play: the stopwatch runs
    timer_pause: "\u{f1ade}", // md-timer_pause
    check: "\u{f012c}", // md-check
    speed: "\u{f04c5}", // md-speedometer: a plan limit crossed
    front_hand: "\u{f0a4f}", // md-hand_front_right: a session needs you
    progress_activity: "\u{f06c4}", // md-asterisk: a session works (it turns)
    priority_high: "\u{f0205}", // md-exclamation: a critical notification
    notifications: "\u{f009a}", // md-bell
    close: "\u{f0156}", // md-close: dismiss a notification bubble
    reply: "\u{f045a}", // md-reply: answer a notification
    send: "\u{f048a}", // md-send: send a reply
    do_not_disturb: "\u{f009b}", // md-bell_off: the history section's do-not-disturb toggle
    delete_sweep: "\u{f05e9}", // md-delete_sweep: clear the notification history
    light_mode: "\u{f05a8}", // md-white_balance_sunny: the brightness HUD
    keyboard: "\u{f030c}", // md-keyboard: the keys HUD, a layout switch
    lock: "\u{f033e}", // md-lock: the keys HUD, Caps Lock or Num Lock on
    lock_open: "\u{f033f}" // md-lock_open: the keys HUD, Caps Lock or Num Lock off
};

// nf-weather-na: a name the table does not know.
var FALLBACK = "\ue374";

function has(name) {
    return Object.prototype.hasOwnProperty.call(TABLE, name);
}

function glyph(name) {
    return has(name) ? TABLE[name] : FALLBACK;
}
