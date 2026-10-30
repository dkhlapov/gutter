import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.theme

// "track": the pop on a track change, a bigger cover with title and "artist · album".
RowLayout {
    id: root

    spacing: Theme.gap

    CoverArt {
        Layout.preferredWidth: 34
        Layout.preferredHeight: 34
        source: Media.artUrl
    }

    // Squeezed by the pill, the text gives way (it elides); the cover and bars keep their width.
    ColumnLayout {
        spacing: 0

        InkText {
            Layout.maximumWidth: 240
            Layout.fillWidth: true
            text: Media.title
            font.bold: true
            font.pixelSize: Theme.textSize
            elide: Text.ElideRight
        }

        InkText {
            Layout.maximumWidth: 240
            Layout.fillWidth: true
            text: [Media.artist, Media.album].filter(s => s).join(" · ")
            elide: Text.ElideRight
            color: Theme.textMuted
        }
    }

    Loader {
        Layout.preferredWidth: 46
        Layout.preferredHeight: 20
        active: Media.playing

        sourceComponent: Visualiser {
            count: 5
            barSpacing: 3
            color: Theme.accent.pink
        }
    }
}
