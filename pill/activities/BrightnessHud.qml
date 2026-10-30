import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.theme
import "../../lib/glyphs.js" as Glyphs

// Same shape as the volume HUD, on a sun tab so the two are told apart.
RowLayout {
    id: root

    // The Theme.accent name of the pill's label tab for this HUD.
    required property string accent

    spacing: Theme.gap

    InkIcon {
        icon: Glyphs.glyph("light_mode")
        size: Theme.glyphSize
        Layout.preferredWidth: 24
        horizontalAlignment: Text.AlignHCenter
    }

    InkSlider {
        accessibleName: "Brightness"
        Layout.preferredWidth: 190
        interactive: false
        accent: root.accent
        value: Math.max(0, Brightness.focusedLevel)
    }

    InkText {
        Layout.preferredWidth: 52
        horizontalAlignment: Text.AlignRight
        text: Brightness.focusedLevel < 0 ? "–" : `${Math.round(Brightness.focusedLevel * 100)}%`
        font.bold: true
        font.pixelSize: Theme.textSize
    }
}
