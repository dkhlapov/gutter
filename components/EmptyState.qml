import QtQuick
import qs.theme

// Centred icon and message for missing data; `busy` spins the icon while loading.
// An empty card should say why it is empty and what to do: `hint` is that second line (wraps), `actionText` a
// button for the next step (`action` fires on a click). `accent` puts the icon on an ink-outlined plate of that
// accent instead of bare ink. `compact` lays it out in a row, for a card that is a strip, not a page.
Item {
    id: root

    property string icon
    property alias text: label.text
    property string hint
    property string actionText
    property string actionIcon
    property string accent
    property bool busy: false
    property bool compact: false
    property color ink: Theme.text
    // The widest the title and the hint grow before they wrap.
    property real textWidth: 360

    signal action

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    // The wrapped texts' natural single-line width: a Text's own implicitWidth moves with its width once it wraps.
    TextMetrics {
        id: labelMetrics

        font.family: Theme.font
        font.pixelSize: label.font.pixelSize
        font.bold: label.font.bold
        text: label.text
    }

    TextMetrics {
        id: hintMetrics

        font.family: Theme.font
        font.pixelSize: hintLabel.font.pixelSize
        text: hintLabel.text
    }

    Grid {
        id: layout

        anchors.centerIn: parent
        columns: root.compact ? (root.actionText !== "" ? 3 : 2) : 1
        columnSpacing: Theme.pad
        rowSpacing: 6
        horizontalItemAlignment: root.compact ? Grid.AlignLeft : Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        Item {
            implicitWidth: root.accent !== "" ? plate.width : glyph.width
            implicitHeight: root.accent !== "" ? plate.height : glyph.height

            IconPlate {
                id: plate

                visible: root.accent !== ""
                accent: root.accent || "teal"
                icon: root.icon
                size: 44
            }

            InkIcon {
                id: glyph

                visible: root.accent === ""
                size: 32
                color: root.ink
                icon: root.icon

                RotationAnimator on rotation {
                    running: root.busy && root.visible
                    from: 0
                    to: 360
                    duration: 1200
                    loops: Animation.Infinite
                }
            }
        }

        Column {
            id: texts

            // The wider of the two lines, each centred (or left-aligned, compact) within it.
            width: Math.max(Math.min(Math.ceil(labelMetrics.width) + 2, root.textWidth), root.hint !== "" ? Math.min(Math.ceil(hintMetrics.width) + 2, root.textWidth) : 0)
            spacing: 4

            InkText {
                id: label

                width: texts.width
                horizontalAlignment: root.compact ? Text.AlignLeft : Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 14
                font.bold: root.hint !== ""
                color: root.ink
            }

            InkText {
                id: hintLabel

                visible: root.hint !== ""
                width: texts.width
                horizontalAlignment: root.compact ? Text.AlignLeft : Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.hint
                color: Theme.mutedOn(root.ink, Theme.paper)
            }
        }

        // Room on the right and below for the button's hard shadow.
        Item {
            visible: root.actionText !== ""
            implicitWidth: button.implicitWidth + Theme.shadowOffset
            implicitHeight: button.implicitHeight + Theme.shadowOffset

            InkButton {
                id: button

                icon: root.actionIcon
                text: root.actionText
                accent: root.accent
                onClicked: root.action()
            }
        }
    }
}
