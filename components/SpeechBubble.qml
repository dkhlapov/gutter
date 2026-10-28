import QtQuick
import qs.theme
import "../lib/bubble.js" as BubbleLib

// A square-cornered balloon whose tail points up toward the pill. Outline, fill and tail are one path,
// so the tail joins the outline without a seam. Size excludes the shadow.
Item {
    id: root

    // Plain properties, so a bubble on a small surface (the lock screen's) can scale them down or up.
    property real tailHeight: 18
    property real tailHalfBase: 9
    property real padX: 2 * Theme.pad
    property real padY: Theme.pad
    readonly property real miterLimit: 10
    property int textSize: 15
    readonly property real textSpacing: 1

    property string text
    property color fill: Theme.paper
    property real tailX: 0 // 0..1 along the top edge; clamped to stay Theme.pad clear of the corners
    default property alias content: inner.data

    // The largest visible content child's own implicit size (the text label included) plus padding and tail.
    // Nothing here reads the bubble's actual size, so a shorter text shrinks the bubble at once. While the bubble
    // itself is hidden every child counts, even one meant to stay hidden, so a hidden bubble can measure larger than
    // it will once shown (see InkBox.extent).
    function extent(horizontal: bool): real {
        let e = 0;
        for (const c of inner.children) {
            if (!c.visible && inner.visible)
                continue;
            e = Math.max(e, horizontal ? c.implicitWidth : c.implicitHeight);
        }
        return e;
    }

    implicitWidth: extent(true) + 2 * padX
    implicitHeight: tailHeight + extent(false) + 2 * padY

    // Where the tail's tip sits along the top edge: tailX of the width, kept clear of the corners.
    readonly property real tailCentre: BubbleLib.tailCentre(width, tailX, tailHalfBase, Theme.inkWidth, Theme.pad)

    // Whether a point (in the bubble's own coordinates) is on the balloon rather than in the empty corners beside
    // the tail. For a click area's containmentMask.
    function inside(x: real, y: real): bool {
        return BubbleLib.contains(x, y, width, height, tailHeight, tailCentre, tailHalfBase);
    }

    onTailXChanged: canvas.requestPaint()
    onFillChanged: canvas.requestPaint()
    onTailHeightChanged: canvas.requestPaint()
    onTailHalfBaseChanged: canvas.requestPaint()
    // A bubble that is sized from its content is resized after its first paint.
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas

        // Wider and taller than the bubble so the shadow is not clipped.
        width: root.width + Theme.shadowOffset + Theme.shadowKeyline
        height: root.height + Theme.shadowOffset + Theme.shadowKeyline

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();

            const lw = Theme.inkWidth;
            const half = root.tailHalfBase;
            const h = root.tailHeight;
            // The stroke's centre line, inset so the outer edge stays in bounds.
            const left = lw / 2;
            const right = root.width - lw / 2;
            const top = h + lw / 2;
            const bottom = root.height - lw / 2;
            const tx = root.tailCentre;
            // The miter join pushes the tip out by this much, so pull the tip in to stay inside the bounds.
            const tipY = (lw / 2) / Math.sin(Math.atan(half / h));

            const trace = (dx, dy) => {
                ctx.beginPath();
                ctx.moveTo(tx + dx, tipY + dy);
                ctx.lineTo(tx + half + dx, top + dy);
                ctx.lineTo(right + dx, top + dy);
                ctx.lineTo(right + dx, bottom + dy);
                ctx.lineTo(left + dx, bottom + dy);
                ctx.lineTo(left + dx, top + dy);
                ctx.lineTo(tx - half + dx, top + dy);
                ctx.closePath();
            };

            const so = Theme.shadowOffset;
            // A paper line around the shadow (see InkBox): a bubble hangs over whatever is under the pill. A
            // keyline of 0 draws no paper line, so it is skipped. Like InkBox's, the line stops at the bubble's own
            // top edge, except by the tail: a keyline wider than the offset would otherwise leave a paper line above
            // the edge. So the tail's two sides are stroked as they are, the rest clipped to below the tail.
            if (Theme.shadowKeyline > 0) {
                ctx.lineWidth = lw + 2 * Theme.shadowKeyline;
                ctx.lineJoin = "miter";
                ctx.miterLimit = root.miterLimit;
                ctx.strokeStyle = Theme.paper;

                ctx.beginPath();
                ctx.moveTo(tx + half + so, top + so);
                ctx.lineTo(tx + so, tipY + so);
                ctx.lineTo(tx - half + so, top + so);
                ctx.stroke();

                ctx.save();
                ctx.beginPath();
                ctx.rect(0, h, canvas.width, canvas.height - h);
                ctx.clip();
                ctx.beginPath();
                ctx.moveTo(tx + half + so, top + so);
                ctx.lineTo(right + so, top + so);
                ctx.lineTo(right + so, bottom + so);
                ctx.lineTo(left + so, bottom + so);
                ctx.lineTo(left + so, top + so);
                ctx.lineTo(tx - half + so, top + so);
                ctx.stroke();
                ctx.restore();
            }
            // The shadow is the whole outline moved by the offset, stroke included: filling only the centre line's
            // path would show the offset less half the ink width.
            trace(so, so);
            ctx.lineWidth = lw;
            ctx.lineJoin = "miter";
            ctx.miterLimit = root.miterLimit;
            ctx.strokeStyle = Theme.shadow;
            ctx.stroke();
            ctx.fillStyle = Theme.shadow;
            ctx.fill();

            trace(0, 0);
            ctx.fillStyle = root.fill;
            ctx.fill();
            ctx.lineWidth = lw;
            ctx.lineJoin = "miter";
            ctx.miterLimit = root.miterLimit;
            ctx.strokeStyle = Theme.ink;
            ctx.stroke();
        }

        Connections {
            function onPaperChanged() {
                canvas.requestPaint();
            }
            function onInkChanged() {
                canvas.requestPaint();
            }
            function onShadowChanged() {
                canvas.requestPaint();
            }
            function onShadowOffsetChanged() {
                canvas.requestPaint();
            }
            function onShadowKeylineChanged() {
                canvas.requestPaint();
            }

            target: Theme
        }
    }

    Item {
        id: inner

        x: root.padX
        y: root.tailHeight + root.padY
        width: root.width - 2 * root.padX
        height: root.height - root.tailHeight - 2 * root.padY

        InkText {
            id: label

            anchors.centerIn: parent
            visible: root.text !== ""
            text: root.text.toUpperCase()
            font.bold: true
            font.pixelSize: root.textSize
            font.letterSpacing: root.textSpacing
        }
    }
}
