import QtQuick
import qs.theme

// Paper rectangle with an ink outline and a hard offset shadow. Size excludes the shadow.
Item {
    id: root

    property color fill: Theme.paper
    property bool shadow: true
    // A paper line around the shadow (Theme.shadowKeyline wide), for a surface that can sit over something dark.
    property bool keyline: false
    property color shadowColor: Theme.shadow
    default property alias content: inner.data

    // Contract: the content needs an implicit size; an explicit width/height alone does not size the box.
    // The implicit size is the far edge (x/y plus implicit size) of the visible content children, plus the
    // outline. While the box itself is hidden every child counts, since `visible` is then false for all of them,
    // including children meant to stay hidden: a hidden box can measure larger than it will once shown. Nothing
    // here reads the box's actual size or childrenRect, so content may anchor or centre itself in the box without a
    // size cycle; for the same reason a child anchored with fill or centerIn counts from 0, since its x/y follows the
    // box size.
    function extent(horizontal: bool): real {
        let e = 0;
        for (const c of inner.children) {
            if (!c.visible && inner.visible)
                continue;
            const follows = c.anchors.fill || c.anchors.centerIn;
            const pos = follows ? 0 : (horizontal ? c.x : c.y);
            e = Math.max(e, pos + (horizontal ? c.implicitWidth : c.implicitHeight));
        }
        return e;
    }

    implicitWidth: extent(true) + 2 * Theme.inkWidth
    implicitHeight: extent(false) + 2 * Theme.inkWidth

    // A keyline wider than the offset would reach past the box's top and left; the box covers that side anyway, so
    // the line starts at the box's own edge there.
    Rectangle {
        readonly property real edge: Math.max(0, Theme.shadowOffset - Theme.shadowKeyline)

        visible: root.shadow && root.keyline && Theme.shadowKeyline > 0
        x: edge
        y: edge
        width: parent.width + Theme.shadowOffset + Theme.shadowKeyline - edge
        height: parent.height + Theme.shadowOffset + Theme.shadowKeyline - edge
        color: Theme.paper
    }

    Rectangle {
        visible: root.shadow
        x: Theme.shadowOffset
        y: Theme.shadowOffset
        width: parent.width
        height: parent.height
        color: root.shadowColor
    }

    Rectangle {
        anchors.fill: parent
        color: root.fill
        border.color: Theme.ink
        border.width: Theme.inkWidth
    }

    Item {
        id: inner

        anchors.fill: parent
        anchors.margins: Theme.inkWidth
    }
}
