import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.theme
import "../../lib/glyphs.js" as Glyphs
import "../../lib/keys.js" as KeysLib

// The keys HUD: the key's glyph (a padlock, shut while the lock is on; a keyboard for a layout switch) and what
// changed, on a label tab of its own (see ActivityView). The layout shows its name, a lock key ON or OFF.
RowLayout {
    id: root

    // "layout", "caps" or "num".
    required property string kind
    readonly property bool lock: kind !== "layout"
    readonly property bool on: kind === "caps" ? LockKeys.caps : LockKeys.num

    spacing: Theme.gap

    InkIcon {
        icon: Glyphs.glyph(KeysLib.icon(root.kind, root.on))
        size: Theme.glyphSize
        Layout.preferredWidth: 24
        horizontalAlignment: Text.AlignHCenter
    }

    InkText {
        Layout.fillWidth: true
        // The name elides before it makes the pill wider than the screen's share for it.
        Layout.maximumWidth: 260
        text: root.lock ? KeysLib.name(root.kind) : KbLayout.layout
        elide: Text.ElideRight
        font.bold: true
        font.pixelSize: Theme.textSize
    }

    InkText {
        visible: root.lock
        text: root.on ? "ON" : "OFF"
        font.bold: true
        font.pixelSize: Theme.textSize
    }
}
