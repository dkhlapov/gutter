import QtQuick
import QtQuick.Layouts
import qs.components
import qs.theme

// The music pill's content: the visualiser, the title and the artist. Squeezed by the pill, the text gives way
// (it elides); the bars keep their width.
RowLayout {
    id: root

    // { title, artist } (lib/sidePills.js, music), kept while the pill folds away.
    property var model: ({ title: "", artist: "" })
    // Whether the pill shows: the visualiser holds the cava service only then.
    property bool active: false

    anchors.verticalCenter: parent.verticalCenter
    x: Theme.pad
    width: parent.width - 2 * Theme.pad
    spacing: Theme.gap

    Loader {
        Layout.preferredWidth: 28
        Layout.preferredHeight: Theme.glyphSize
        active: root.active

        sourceComponent: Visualiser {
            count: 4
            barSpacing: 3
            color: Theme.accent.pink
        }
    }

    // One line, so that a pill too narrow for it cuts the artist first and the title last.
    InkText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        textFormat: Text.StyledText
        text: {
            const plain = t => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
            const dim = Qt.tint(Theme.paper, Qt.alpha(Theme.text, 0.7));
            return `<b>${plain(root.model.title)}</b>` + (root.model.artist !== "" ? ` <font color="${dim}">${plain(root.model.artist)}</font>` : "");
        }
        font.pixelSize: Theme.textSize
        elide: Text.ElideRight
    }
}
