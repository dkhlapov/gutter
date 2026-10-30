import QtQuick
import qs.theme
import qs.components

// One cell of the top-right bar: its own small ink box (with the outer surfaces' paper keyline round its shadow)
// holding a glyph and/or text. Hovered it shows halftone dots; pressed in (the mouse is down, or `down` while
// its menu is open) it fills with `accent`. A `dimmed` cell is off (muted, powered down): the fill is only ever
// press feedback. Other content (a tray icon) goes in as children, centred.
Item {
    id: root

    property string icon
    property real iconSize: Theme.glyphSize
    property string text
    // A text wider than this is cut with an ellipsis (0: never); `text` stays whole.
    property real maxTextWidth: 0
    property string accent: Theme.roleAccent.muted
    property bool dimmed: false
    property bool down: area.pressed
    // Width of the content children, for a cell that holds something other than the glyph and text.
    property real contentWidth: implicitContentWidth
    readonly property real implicitContentWidth: row.implicitWidth
    readonly property bool hovered: area.containsMouse
    // The font of the text, here once so a width measured elsewhere agrees with what is drawn.
    readonly property font labelFont: Qt.font({
        family: Theme.font,
        pixelSize: Theme.textSize,
        bold: true
    })
    readonly property string shownText: maxTextWidth > 0 ? elider.elidedText : text
    // A tooltip ({ title, body }, or null for none) and the bar that shows it on hover.
    property var tip: null
    // What a screen reader calls the cell: this, else the tooltip's title, else its text. An icon-only cell sets it.
    property string accessibleName: ""
    property var tipHost: null
    default property alias content: holder.data

    signal clicked(var mouse)
    signal wheeled(var wheel)

    // A cell without text (a glyph, a tray icon) is a square of the pill's height; one with text is that high and
    // as wide as its content plus the same padding on both sides.
    readonly property bool square: text === ""

    implicitWidth: square ? Theme.pillHeight : Math.max(Theme.pillHeight, contentWidth + 2 * Theme.pad + 2 * Theme.inkWidth)
    implicitHeight: Theme.pillHeight

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName || tip?.title || text
    Accessible.description: tip?.body ?? ""
    Accessible.onPressAction: root.clicked({ button: Qt.LeftButton })

    onHoveredChanged: tipHost?.hoverTip(root, hovered)

    TextMetrics {
        id: elider

        font: root.labelFont
        text: root.text
        elide: Text.ElideRight
        elideWidth: root.maxTextWidth
    }

    readonly property color textColor: down ? Theme.on[accent] : Theme.text

    InkBox {
        anchors.fill: parent
        keyline: true
        fill: root.down ? Theme.accent[root.accent] : Theme.paper

        Item {
            anchors.fill: parent
            visible: root.hovered && !root.down
            opacity: 0.35

            Halftone {}
        }

        Row {
            id: row

            anchors.centerIn: parent
            opacity: root.dimmed ? 0.45 : 1
            spacing: Theme.gap

            InkIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.icon !== ""
                icon: root.icon
                size: root.iconSize
                color: root.textColor
            }

            InkText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.text !== ""
                text: root.shownText
                color: root.textColor
                font: root.labelFont
            }
        }

        Item {
            id: holder

            anchors.centerIn: parent
            width: root.contentWidth
            height: parent.height
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => root.clicked(mouse)
        onWheel: wheel => root.wheeled(wheel)
    }
}
