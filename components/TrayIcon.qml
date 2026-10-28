import QtQuick
import Quickshell.Widgets
import qs.theme

// A tray item's icon on paper. Tray icons are drawn for dark panels (white, grey, beige), so a hard ink outline is
// traced round the icon's own shape: it keeps a light icon readable without putting a plate behind it. An icon
// that already contrasts with the paper (the icon theme's dark variant on light paper) is left without one.
// An icon that is missing or cannot be read shows a question mark.
Item {
    id: root

    property string source
    // Used when `source` cannot be read.
    property string fallback
    property real size: 18
    // The outline's width in pixels.
    readonly property real edge: 1

    // `source` was tried and failed: the fallback is shown.
    property bool failed: false

    implicitWidth: size
    implicitHeight: size

    IconImage {
        id: image

        anchors.fill: parent
        source: root.failed ? root.fallback : root.source
        onStatusChanged: {
            if (status === Image.Error && !root.failed && root.fallback !== "")
                root.failed = true;
        }
    }

    ShaderEffect {
        id: outline

        readonly property var source: ShaderEffectSource {
            sourceItem: image
            // The texture runs `edge` past the icon on every side, so the outline is not cut at its edges.
            sourceRect: Qt.rect(-root.edge, -root.edge, image.width + 2 * root.edge, image.height + 2 * root.edge)
            hideSource: outline.status !== ShaderEffect.Error
        }
        readonly property color inkColor: Theme.ink
        // The shader skips the outline for an icon that already contrasts with the paper (see outline.frag).
        readonly property real paperLum: Theme.paper.r * 0.299 + Theme.paper.g * 0.587 + Theme.paper.b * 0.114
        readonly property size radius: Qt.size(root.edge / width, root.edge / height)

        x: -root.edge
        y: -root.edge
        width: root.width + 2 * root.edge
        height: root.height + 2 * root.edge
        visible: image.status === Image.Ready && status !== ShaderEffect.Error
        fragmentShader: Qt.resolvedUrl("../theme/outline.frag.qsb")
    }

    InkIcon {
        anchors.centerIn: parent
        visible: image.status !== Image.Ready && image.status !== Image.Loading
        icon: "\u{f02d6}" // md-help, a question mark, for an icon that did not load
        size: root.size - 2
    }
}
