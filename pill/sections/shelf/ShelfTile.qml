import QtQuick
import qs.theme
import qs.services
import qs.components
import "../../../lib/shelf.js" as ShelfLib
import "../../../lib/glyphs.js" as Glyphs

// One held file: thumbnail or kind icon, name, size. Click opens it, dragging carries it out as a file
// URL, the corner button takes it off the shelf. A file that is gone has dimmed text and cannot be dragged.
InkBox {
    id: root

    required property string path
    readonly property var stat: Shelf.info[path]
    readonly property bool gone: stat === undefined
    readonly property string kind: ShelfLib.kind(path, stat?.dir ?? false)
    readonly property bool thumb: kind === "image" && !gone
    // Accent by kind; the glyph on it takes its text colour from Theme.on.
    readonly property var accents: ({
            folder: "teal",
            image: "pink",
            video: "magenta",
            audio: "navy",
            pdf: "coral",
            archive: "sun",
            code: "lime"
        })
    readonly property string accent: accents[kind] ?? "navy"
    readonly property bool lit: hover.hovered && !gone
    readonly property string subtitle: gone ? "File is gone" : kind === "folder" ? "Folder" : `${ShelfLib.humanSize(stat.size)} · ${ShelfLib.extension(path).toUpperCase() || "FILE"}`

    // The grid leaves room on the right and below for the shadow. Under the pointer the tile turns sun-yellow.
    fill: lit ? Theme.accent.sun : Theme.paper

    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction | Qt.LinkAction
    Drag.mimeData: ({ "text/uri-list": ShelfLib.uriList([path]) })
    Drag.hotSpot: Qt.point(40, 30)
    Drag.active: dragger.active && !gone
    Drag.onDragFinished: Shelf.dragging = false

    Component.onDestruction: Shelf.dragging = false

    // The image that follows the pointer is the preview area, grabbed ahead of time because a drag
    // cannot wait for an asynchronous grab.
    function grabPreview(): void {
        preview.grabToImage(r => root.Drag.imageSource = r.url, Qt.size(80, 60));
    }

    HoverHandler {
        id: hover

        onHoveredChanged: if (hovered && !root.gone)
            root.grabPreview()
    }

    TapHandler {
        enabled: !root.gone
        onTapped: Shelf.open(root.path)
    }

    DragHandler {
        id: dragger

        target: null
        enabled: !root.gone
        onActiveChanged: if (active)
            Shelf.dragging = true
    }

    Item {
        id: preview

        // Fills the box, which the box counts as 0, so the tile's size comes from its cell.
        x: 8
        y: 8
        width: parent.width - 16
        height: parent.height - 8 - 46

        Rectangle {
            anchors.fill: parent
            clip: true
            color: Theme.accent[root.accent]
            border.color: Theme.ink
            border.width: Theme.inkWidth

            InkIcon {
                anchors.centerIn: parent
                visible: !root.thumb
                icon: Glyphs.glyph(root.gone ? "unknown_document" : ShelfLib.icon(root.kind))
                size: 34
                color: Theme.on[root.accent]
                opacity: root.gone ? 0.6 : 1
            }

            Image {
                anchors.fill: parent
                anchors.margins: Theme.inkWidth
                visible: root.thumb
                source: root.thumb ? ShelfLib.fileUrl(root.path) : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 240
                sourceSize.height: 160
                asynchronous: true
                cache: false
            }
        }
    }

    Column {
        x: 10
        y: parent.height - 38
        width: parent.width - 20
        spacing: 1
        opacity: root.gone ? 0.6 : 1

        InkText {
            width: parent.width
            text: ShelfLib.baseName(root.path)
            font.bold: true
            elide: Text.ElideMiddle
            color: root.lit ? Theme.on.sun : Theme.text
        }

        InkText {
            width: parent.width
            text: root.subtitle
            elide: Text.ElideRight
            color: Theme.mutedOn(root.lit ? Theme.on.sun : Theme.text, root.lit ? Theme.accent.sun : Theme.paper)
        }
    }

    InkButton {
        accessibleName: "Remove from shelf"
        x: parent.width - width - 14
        y: 14
        width: 26
        height: 26
        icon: "\u{f0156}"
        iconSize: 13
        visible: hover.hovered && !dragger.active
        onClicked: Shelf.remove(root.path)
    }
}
