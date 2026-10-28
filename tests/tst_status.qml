import QtQuick
import QtTest
import "../lib/status.js" as St

TestCase {
    name: "Status"

    // The same Material Design glyphs as the pill's volume HUD (lib/glyphs.js).
    function test_volume_icon() {
        compare(St.volumeIcon(0.5, true), "\u{f075f}");
        compare(St.volumeIcon(0, false), "\u{f075f}");
        compare(St.volumeIcon(0.2, false), "\u{f057f}");
        compare(St.volumeIcon(0.5, false), "\u{f0580}");
        compare(St.volumeIcon(1.2, false), "\u{f057e}");
    }

    // The status row reserves the widest of VOLUME_ICONS, so every glyph volumeIcon returns must be in it.
    function test_volume_icons_list_every_glyph() {
        for (const muted of [false, true]) {
            for (let v = -0.5; v <= 1.5; v += 0.01)
                verify(St.VOLUME_ICONS.indexOf(St.volumeIcon(v, muted)) >= 0, `volume ${v}, muted ${muted}`);
        }
        compare(new Set(St.VOLUME_ICONS).size, St.VOLUME_ICONS.length);
    }

    function test_volume_icon_boundaries() {
        compare(St.volumeIcon(0.33, false), "\u{f057f}");
        compare(St.volumeIcon(0.34, false), "\u{f0580}");
        compare(St.volumeIcon(0.66, false), "\u{f0580}");
        compare(St.volumeIcon(0.67, false), "\u{f057e}");
    }

    function test_mic_icon() {
        compare(St.micIcon(true), "");
        compare(St.micIcon(false), "");
    }

    function test_wifi_icon() {
        compare(St.wifiIcon(80, false), "󰖪");
        compare(St.wifiIcon(0, false), "󰖪");
        compare(St.wifiIcon(80, true), "");
        compare(St.wifiIcon(0, true), "");
        compare(St.wifiIcon(0, true, true), "󰈀");
    }

    function test_bluetooth_icon_has_a_glyph_per_state() {
        compare(St.bluetoothIcon(false, 0), "󰂲");
        compare(St.bluetoothIcon(false, 2), "󰂲");
        compare(St.bluetoothIcon(true, 0), "󰂯");
        compare(St.bluetoothIcon(true, 1), "󰂱");
    }

    function test_bluetooth_text_never_shows_zero() {
        compare(St.bluetoothText(false, []), "");
        compare(St.bluetoothText(true, []), "");
        compare(St.bluetoothText(false, ["Buds"]), "");
        compare(St.bluetoothText(true, ["Buds"]), "Buds");
        compare(St.bluetoothText(true, ["Buds", "Mouse"]), "2");
    }

    function test_bluetooth_tip() {
        compare(St.bluetoothTip(false, []), "Off");
        compare(St.bluetoothTip(true, []), "On, no devices connected");
        compare(St.bluetoothTip(true, ["Buds"]), "Connected: Buds");
        compare(St.bluetoothTip(true, ["Buds", "Mouse"]), "Connected: Buds, Mouse");
    }

    function test_wifi_tip() {
        compare(St.wifiTip(false, false, "", 0), "Not connected");
        compare(St.wifiTip(true, true, "", 100), "Wired");
        compare(St.wifiTip(true, false, "Home", 72), "Home, signal 72%");
    }

    function test_kb_short() {
        compare(St.kbShort("Swedish (no dead keys)"), "SE");
        compare(St.kbShort("Swedish"), "SE");
        compare(St.kbShort("Russian"), "RU");
        compare(St.kbShort("English (US)"), "US");
        compare(St.kbShort("German"), "GE");
        compare(St.kbShort(""), "--");
        compare(St.kbShort(undefined), "--");
    }

    function test_percent() {
        compare(St.percent(0.456), "46%");
        compare(St.percent(1.3), "100%");
        compare(St.percent(-1), "0%");
        compare(St.percent(0), "0%");
    }

    function test_main_layout() {
        const json = JSON.stringify({ keyboards: [
            { name: "a", main: false, active_keymap: "Swedish (no dead keys)" },
            { name: "b", main: true, active_keymap: "Russian" }
        ] });
        compare(St.mainLayout(json), "Russian");
    }

    function test_main_layout_falls_back_to_first() {
        const json = JSON.stringify({ keyboards: [
            { name: "a", main: false, active_keymap: "Swedish" },
            { name: "b", main: false, active_keymap: "Russian" }
        ] });
        compare(St.mainLayout(json), "Swedish");
    }

    function test_main_layout_bad_input() {
        compare(St.mainLayout(""), "");
        compare(St.mainLayout("not json"), "");
        compare(St.mainLayout("{}"), "");
        compare(St.mainLayout('{"keyboards":[]}'), "");
    }

    function test_layout_state_takes_the_new_layout() {
        const json = '{"keyboards":[{"name":"a","main":true,"active_keymap":"Russian"}]}';
        compare(JSON.stringify(St.layoutState("Swedish", json)), '{"layout":"Russian","available":true}');
    }

    function test_layout_state_keeps_the_last_good_layout() {
        compare(JSON.stringify(St.layoutState("Swedish", "")), '{"layout":"Swedish","available":false}');
        compare(JSON.stringify(St.layoutState("Swedish", '{"keyboards":[]}')), '{"layout":"Swedish","available":false}');
        compare(JSON.stringify(St.layoutState("", "oops")), '{"layout":"","available":false}');
    }
}
