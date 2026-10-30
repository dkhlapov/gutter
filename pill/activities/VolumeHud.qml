import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.theme
import "../../lib/glyphs.js" as Glyphs
import "../../lib/volume.js" as VolumeLib

// The volume HUD: a coral label tab (the island shows it at its start, see Collapsed), the speaker, the level and its
// percentage. Muted keeps the level but draws it as solid ink and says MUTED.
RowLayout {
    id: root

    // The Theme.accent name of the pill's label tab for this HUD.
    required property string accent

    spacing: Theme.gap

    InkIcon {
        icon: Glyphs.glyph(VolumeLib.icon(Audio.volume, Audio.muted))
        size: Theme.glyphSize
        // The speaker glyphs differ in width; this keeps the slider from moving between them.
        Layout.preferredWidth: 24
        horizontalAlignment: Text.AlignHCenter
    }

    InkSlider {
        accessibleName: "Volume"
        Layout.preferredWidth: 190
        interactive: false
        accent: root.accent
        muted: Audio.muted
        value: Audio.volume
    }

    InkText {
        Layout.preferredWidth: 52
        horizontalAlignment: Text.AlignRight
        text: Audio.muted ? "MUTED" : `${Math.round(Audio.volume * 100)}%`
        font.bold: true
        font.pixelSize: Theme.textSize
    }
}
