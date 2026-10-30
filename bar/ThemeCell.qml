import QtQuick
import qs.theme
import qs.services

// The sun/moon cell: a sun in light mode, a moon in dark mode (the wanted mode, so a flip shows at once). A
// click flips; resting on it names the next switch. The bar sets tipHost.
Segment {
    accessibleName: "Theme"
    icon: ThemeMode.mode === "light" ? "\u{f0599}" : "\u{f0594}" // md-weather-sunny, md-weather-night
    accent: Theme.roleAccent.active
    tip: ({
            title: "",
            body: ThemeMode.tip
        })
    onClicked: ThemeMode.toggle()
}
