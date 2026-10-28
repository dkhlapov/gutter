pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.theme

// The big time, a paper face with a thick ink outline and the hard shadow behind it, and the date on a plate
// below. `ui` scales the type and the gaps; the outline and the shadow are the shell's and do not scale.
Item {
    id: root

    property real ui: 1
    // The type never grows past this, so the clock stays in proportion on a big monitor.
    property real maxSize: 1000

    // How far the outline reaches round each glyph.
    readonly property real outline: Theme.inkWidth + 1
    readonly property real size: Math.min(Math.round(128 * ui), maxSize)
    readonly property string time: Qt.formatTime(clock.date, "HH:mm")
    // Eight steps round a glyph: the outline is the text drawn at each of them, in ink.
    readonly property var steps: [[-1, -1], [0, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [0, 1], [1, 1]]

    implicitWidth: Math.max(face.implicitWidth + 2 * outline + Theme.shadowOffset, date.implicitWidth)
    implicitHeight: face.implicitHeight + 2 * outline + Theme.shadowOffset + Math.round(10 * ui) + date.implicitHeight

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    // Only measures the time (its size is the face's), and gives the baseline: the canvas below draws it.
    Text {
        id: face

        visible: false
        text: root.time
        font.family: Theme.font
        font.bold: true
        font.pixelSize: root.size
    }

    // The shadow, the outline and the face as one image, painted again when the minute, the size or a colour
    // changes (19 Text copies drawn every frame cost far more).
    Canvas {
        id: art

        // Centred in the block, which the date plate can make wider than the face.
        x: Math.round((root.width - width) / 2)
        width: face.implicitWidth + 2 * root.outline + Theme.shadowOffset
        height: face.implicitHeight + 2 * root.outline + Theme.shadowOffset

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            // The pixel size the text takes (a whole number, whatever `size` is).
            ctx.font = `bold ${face.font.pixelSize}px "${Theme.font}"`;
            ctx.textBaseline = "alphabetic";
            const base = root.outline + face.baselineOffset;
            // The text at `shift` px down and right of the face's place, `reach` px round it in the eight steps (0: just once).
            const layer = (color, shift, reach) => {
                ctx.fillStyle = color;
                for (const step of reach === 0 ? [[0, 0]] : root.steps)
                    ctx.fillText(root.time, root.outline + shift + step[0] * reach, base + shift + step[1] * reach);
            };
            layer(Theme.shadow, Theme.shadowOffset, root.outline);
            layer(Theme.ink, 0, root.outline);
            layer(Theme.paper, 0, 0);
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            function onTimeChanged() {
                art.requestPaint();
            }
            function onSizeChanged() {
                art.requestPaint();
            }

            target: root
        }

        Connections {
            function onPaperChanged() {
                art.requestPaint();
            }
            function onInkChanged() {
                art.requestPaint();
            }
            function onShadowChanged() {
                art.requestPaint();
            }
            function onShadowOffsetChanged() {
                art.requestPaint();
            }

            target: Theme
        }

        Component.onCompleted: requestPaint()
    }

    InkBox {
        id: date

        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height - height - Theme.shadowOffset

        Item {
            implicitWidth: label.implicitWidth + Math.round(24 * root.ui)
            implicitHeight: label.implicitHeight + Math.round(10 * root.ui)

            InkText {
                id: label

                anchors.centerIn: parent
                text: Qt.formatDate(clock.date, "dddd • d MMM")
                font.pixelSize: Math.round(22 * root.ui)
                font.bold: true
            }
        }
    }
}
