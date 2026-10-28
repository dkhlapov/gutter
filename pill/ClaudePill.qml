import QtQuick
import QtQuick.Layouts
import qs.components
import qs.theme
import "../lib/sidePills.js" as SidePills

// The Claude pill's content, and nothing more: the agent's icon and, while it works, the time it has worked
// and a blinking dot; while it waits for you, the icon in coral and "waiting".
RowLayout {
    id: root

    // { kind, elapsed } (lib/sidePills.js, agent), kept while the pill folds away.
    property var model: ({ kind: "working", elapsed: -1 })
    // Whether the pill shows: the dot only blinks then.
    property bool active: false
    readonly property bool waiting: model.kind === "waiting"
    readonly property string label: SidePills.agentLabel(model)

    anchors.verticalCenter: parent.verticalCenter
    x: Theme.pad
    width: parent.width - 2 * Theme.pad
    spacing: Theme.gap

    InkIcon {
        // The Claude mark, cod-claude (Nerd Fonts 3.4 and later; not in the Material set lib/glyphs.js maps).
        icon: "\uec82"
        size: Theme.glyphSize
        color: root.waiting ? Theme.accent.coral : Theme.accent.magenta
    }

    InkText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: text !== ""
        text: root.label
        font.bold: true
        font.pixelSize: Theme.textSize
        elide: Text.ElideRight
    }

    // Working: a lamp that blinks, on and off, not faded (like the one on the Agents tab's Claude card).
    Rectangle {
        id: lamp

        property bool lit: true

        Layout.preferredWidth: 10
        Layout.preferredHeight: 10
        visible: !root.waiting
        opacity: lit ? 1 : 0
        color: Theme.accent.magenta
        border.color: Theme.ink
        border.width: Theme.inkWidth - 1

        Timer {
            running: root.active && !root.waiting
            repeat: true
            interval: 700
            onTriggered: lamp.lit = !lamp.lit
            onRunningChanged: lamp.lit = true
        }
    }
}
