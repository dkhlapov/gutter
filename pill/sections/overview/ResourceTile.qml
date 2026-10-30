import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.components

// One resource as a row: glyph, name, level bar and percentage.
InkBox {
    id: root

    property string icon
    property string label
    property real value // 0..1
    property string accent: "teal"

    Layout.fillWidth: true
    Layout.fillHeight: true
    shadow: false

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.gap
        anchors.rightMargin: Theme.gap
        spacing: 6

        InkIcon {
            icon: root.icon
            size: 16
        }

        InkText {
            text: root.label
            font.bold: true
        }

        LevelBar {
            Layout.fillWidth: true
            Layout.minimumWidth: 10
            accent: root.accent
            value: root.value
        }

        InkText {
            text: `${Math.round(root.value * 100)}%`
            color: Theme.textMuted
        }
    }
}
