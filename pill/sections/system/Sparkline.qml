import QtQuick
import qs.theme

// Two scrolling history lines on a shared scale: `line1` as a filled area, `line2` as a bare line. Each is an
// array of samples, oldest first. A new sample slides in over `interval` ms.
Item {
    id: root

    property var line1
    property var line2
    property string accent1: "teal"
    property string accent2: "magenta"
    property int historyLength: 30
    property real maxValue: 1024
    property real slideProgress: 1
    property int interval: 1000

    function path(ctx, values, step, dx): void {
        for (let i = 0; i < values.length; i++) {
            const x = width - (values.length - 1 - i) * step + dx;
            const y = height - 2 - Math.min(1, values[i] / root.maxValue) * (height - 6);
            i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
        }
    }

    onMaxValueChanged: canvas.requestPaint()
    onSlideProgressChanged: canvas.requestPaint()

    Canvas {
        id: canvas

        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.lineJoin = "miter";
            const step = width / Math.max(1, root.historyLength - 1);
            const dx = (1 - root.slideProgress) * step;
            const a = root.line1 ?? [];
            const b = root.line2 ?? [];

            if (a.length >= 2) {
                ctx.beginPath();
                root.path(ctx, a, step, dx);
                ctx.lineTo(width + dx, height);
                ctx.lineTo(width - (a.length - 1) * step + dx, height);
                ctx.closePath();
                ctx.fillStyle = Theme.accent[root.accent1];
                ctx.fill();
                ctx.beginPath();
                root.path(ctx, a, step, dx);
                ctx.strokeStyle = Theme.ink;
                ctx.lineWidth = 2;
                ctx.stroke();
            }

            if (b.length >= 2) {
                ctx.beginPath();
                root.path(ctx, b, step, dx);
                ctx.strokeStyle = Theme.ink;
                ctx.lineWidth = 5;
                ctx.stroke();
                ctx.beginPath();
                root.path(ctx, b, step, dx);
                ctx.strokeStyle = Theme.accent[root.accent2];
                ctx.lineWidth = 2;
                ctx.stroke();
            }
        }

        Connections {
            // The palette is applied whole, so one signal covers ink, paper and the accents.
            function onAppliedChanged() {
                canvas.requestPaint();
            }

            target: Theme
        }
    }

    NumberAnimation {
        id: slide

        target: root
        property: "slideProgress"
        from: 0
        to: 1
        duration: root.interval
    }

    // The history is replaced, not edited: a changed array is a new sample.
    onLine1Changed: slide.restart()
}
