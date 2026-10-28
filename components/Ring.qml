import QtQuick
import qs.theme

// Usage ring from 12 o'clock clockwise, with a glyph in the middle. A paper band between two ink outlines;
// the part that is used is filled with the accent and ends square, with an ink tick across the band.
Item {
    id: root

    property real value
    property string accent: "teal"
    property string icon
    property real thickness: 10
    // Off for values that tick continuously (e.g. a stopwatch sweep), where easing lags and wraps backwards.
    property bool animated: true
    // The value as drawn: follows `value`, eased when `animated`.
    property real shown: value

    implicitWidth: 56
    implicitHeight: implicitWidth

    Behavior on shown {
        enabled: root.animated

        Anim {}
    }

    onShownChanged: canvas.requestPaint()
    onAccentChanged: canvas.requestPaint()
    onThicknessChanged: canvas.requestPaint()

    Canvas {
        id: canvas

        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.lineCap = "butt";
            const ow = Theme.inkWidth;
            const outer = Math.min(width, height) / 2;
            const mid = outer - ow - root.thickness / 2;
            const cx = width / 2;
            const cy = height / 2;
            const frac = Math.max(0, Math.min(1, root.shown));
            const start = -Math.PI / 2;

            ctx.lineWidth = root.thickness;
            ctx.strokeStyle = Theme.paper;
            ctx.beginPath();
            ctx.arc(cx, cy, mid, 0, 2 * Math.PI);
            ctx.stroke();

            if (frac > 0) {
                ctx.strokeStyle = Theme.accent[root.accent];
                ctx.beginPath();
                ctx.arc(cx, cy, mid, start, start + 2 * Math.PI * frac);
                ctx.stroke();
            }

            ctx.lineWidth = ow;
            ctx.strokeStyle = Theme.ink;
            for (const r of [outer - ow / 2, outer - ow - root.thickness - ow / 2]) {
                ctx.beginPath();
                ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                ctx.stroke();
            }

            // Ticks across the band where the used part starts and ends.
            if (frac > 0 && frac < 1) {
                for (const a of [start, start + 2 * Math.PI * frac]) {
                    ctx.beginPath();
                    ctx.moveTo(cx + (mid - root.thickness / 2) * Math.cos(a), cy + (mid - root.thickness / 2) * Math.sin(a));
                    ctx.lineTo(cx + (mid + root.thickness / 2) * Math.cos(a), cy + (mid + root.thickness / 2) * Math.sin(a));
                    ctx.stroke();
                }
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

    InkIcon {
        anchors.centerIn: parent
        icon: root.icon
        size: Math.max(1, Math.round(root.width * 0.3))
    }
}
