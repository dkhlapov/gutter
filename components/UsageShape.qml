import QtQuick
import qs.theme
import "../lib/usage.js" as UsageLib

// Usage percentage on a flat blob that changes shape with the load (cookie, sun, burst): accent fill,
// ink outline, a hard offset shadow.
Item {
    id: root

    property real value
    property string accent: "teal"
    readonly property string kind: UsageLib.shapeFor(value)

    implicitWidth: 92
    implicitHeight: implicitWidth

    onKindChanged: canvas.requestPaint()
    onAccentChanged: canvas.requestPaint()

    Canvas {
        id: canvas

        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.lineJoin = "miter";
            ctx.miterLimit = 6;
            const off = Theme.shadowOffset;
            // The outline's miter at a tip reaches past the vertex by (lineWidth / 2) / sin(half the tip angle),
            // up to the miter limit; leave that much room so sharp tips are not clipped at the canvas edge.
            const unit = UsageLib.shapeOutline(root.kind, 0, 0, 1);
            const tip = unit[0];
            const a = unit[1];
            const b = unit[unit.length - 1];
            const ang = Math.abs(Math.atan2(a.y - tip.y, a.x - tip.x) - Math.atan2(b.y - tip.y, b.x - tip.x));
            const half = Math.min(ang, 2 * Math.PI - ang) / 2;
            const lw = Theme.inkWidth;
            const reach = Math.min(lw / 2 / Math.sin(half), 6 * lw / 2);
            const r = (Math.min(width, height) - off) / 2 - reach;
            const cx = (width - off) / 2;
            const cy = (height - off) / 2;
            const pts = UsageLib.shapeOutline(root.kind, cx, cy, r);

            function trace(dx, dy) {
                ctx.beginPath();
                ctx.moveTo(pts[0].x + dx, pts[0].y + dy);
                for (let i = 1; i < pts.length; i++)
                    ctx.lineTo(pts[i].x + dx, pts[i].y + dy);
                ctx.closePath();
            }

            ctx.fillStyle = Theme.shadow;
            trace(off, off);
            ctx.fill();

            ctx.fillStyle = Theme.accent[root.accent];
            ctx.strokeStyle = Theme.ink;
            ctx.lineWidth = Theme.inkWidth;
            trace(0, 0);
            ctx.fill();
            ctx.stroke();
        }

        Connections {
            // The palette is applied whole, so one signal covers ink, paper and the accents.
            function onAppliedChanged() {
                canvas.requestPaint();
            }
            // The shadow settings change on their own.
            function onShadowChanged() {
                canvas.requestPaint();
            }
            function onShadowOffsetChanged() {
                canvas.requestPaint();
            }

            target: Theme
        }
    }

    InkText {
        x: (root.width - Theme.shadowOffset - width) / 2
        y: (root.height - Theme.shadowOffset - height) / 2
        text: `${Math.round(root.value * 100)}%`
        font.pixelSize: root.value >= 0.995 ? 14 : 19
        font.bold: true
        color: Theme.on[root.accent]
    }
}
