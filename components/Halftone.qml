pragma ComponentBehavior: Bound

import QtQuick
import qs.theme

// Dots of radius `dot` px, one centred in each `grid` px cell, over the parent's area.
// The shader draws them; if it cannot load, a Canvas draws the same dots once per size change.
ShaderEffect {
    id: root

    property color dotColor: Theme.ink
    property real dot: Theme.halftoneDot
    property real grid: Theme.halftoneGrid
    // The shader's own name for `dot`: a uniform called `dot` collides with GLSL's dot() and reads as 0.
    readonly property real dotRadius: dot
    readonly property size size: Qt.size(width, height)

    anchors.fill: parent
    fragmentShader: Qt.resolvedUrl("../theme/halftone.frag.qsb")

    Loader {
        anchors.fill: parent
        active: root.status === ShaderEffect.Error

        sourceComponent: Canvas {
            id: canvas

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()

            Connections {
                function onDotColorChanged() {
                    canvas.requestPaint();
                }
                function onDotChanged() {
                    canvas.requestPaint();
                }
                function onGridChanged() {
                    canvas.requestPaint();
                }

                target: root
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = root.dotColor;
                for (let y = root.grid / 2; y < canvas.height; y += root.grid) {
                    for (let x = root.grid / 2; x < canvas.width; x += root.grid) {
                        ctx.beginPath();
                        ctx.arc(x, y, root.dot, 0, 2 * Math.PI);
                        ctx.fill();
                    }
                }
            }
        }
    }
}
