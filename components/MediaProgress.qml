import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import "../lib/format.js" as Format

ColumnLayout {
    id: root

    property color accent: Theme.accent.pink

    spacing: 2

    SeekBar {
        id: bar

        Layout.fillWidth: true
        accent: root.accent
        position: Media.position
        length: Media.length
        interactive: Media.length > 0
        onSeek: seconds => Media.seek(seconds)
    }

    RowLayout {
        Layout.fillWidth: true

        InkText {
            text: Format.duration(bar.dragging ? bar.fraction * Media.length : Media.position)
            font.pixelSize: 12
        }

        Item {
            Layout.fillWidth: true
        }

        InkText {
            text: Format.duration(Media.length)
            font.pixelSize: 12
        }
    }
}
