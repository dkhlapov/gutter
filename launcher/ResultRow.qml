import QtQuick
import Quickshell
import qs.theme
import qs.services
import qs.components

// One row of the launcher's list: an app (its icon) or a slash command (its glyph), the title and the dimmed subtitle.
// The selected row fills with the active accent; a command waiting for its second Enter fills coral and says so.
Rectangle {
    id: root

    // The launcher's sizes, made by the window. The row's height is the delegate's.
    required property LauncherMetrics metrics
    required property var row
    required property bool selected

    // A command that has been chosen once and waits for the second Enter.
    readonly property bool waiting: row.kind === "command" && Launcher.confirming === row.command.name
    readonly property bool lit: waiting || selected
    readonly property string accent: waiting ? "coral" : Theme.roleAccent.active
    readonly property color textColor: lit ? Theme.on[accent] : Theme.text
    // Where the text starts, and the room it has up to the right edge (or to "Enter again").
    readonly property real iconSize: metrics.px(20)
    // The app's icon from the theme, "" when the theme has none (or the app names none): its row shows a glyph.
    readonly property string appIcon: row.kind === "app" ? Quickshell.iconPath(row.iconName ?? "", true) : ""
    readonly property real textX: root.metrics.pad + iconSize + root.metrics.gap
    readonly property real textRoom: Math.max(0, width - textX - root.metrics.pad - (waiting ? again.width + root.metrics.gap : 0))

    signal clicked
    // The mouse moved over the row (not merely scrolled under it).
    signal hovered

    color: lit ? Theme.accent[accent] : "transparent"
    // A command that cannot run as typed (a timer without its minutes) is drawn faded.
    opacity: row.kind === "command" && !row.ready ? 0.6 : 1

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: root.hovered()
        // A command waiting for its second Enter is confirmed with Enter only, so a double click cannot run it.
        onClicked: {
            if (!root.waiting)
                root.clicked();
        }
    }

    Image {
        visible: root.appIcon !== ""
        x: root.metrics.pad
        anchors.verticalCenter: parent.verticalCenter
        width: root.iconSize
        height: root.iconSize
        sourceSize: Qt.size(root.iconSize, root.iconSize)
        asynchronous: true
        source: root.appIcon
    }

    // A command's glyph, or an app's stand-in when the theme has no icon for it.
    InkIcon {
        visible: root.row.kind === "command" || root.appIcon === ""
        x: root.metrics.pad + (root.iconSize - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        icon: root.row.kind === "command" ? root.row.glyph ?? "" : "\u{f08c6}" // md-application
        size: root.metrics.px(16)
        color: root.textColor
    }

    InkText {
        id: title

        x: root.textX
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.textRoom)
        // The waiting command names itself plainly ("Log out?"): its subtitle is the action's label.
        text: root.waiting ? `${root.row.subtitle}?` : root.row.title
        color: root.textColor
        font.bold: root.waiting
        elide: Text.ElideRight
    }

    InkText {
        x: title.x + title.width + root.metrics.gap
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, root.textRoom - title.width - root.metrics.gap)
        visible: !root.waiting && width > 24
        text: root.row.subtitle
        color: Theme.mutedOn(root.textColor, root.lit ? Theme.accent[root.accent] : Theme.paper)
        elide: Text.ElideRight
    }

    InkText {
        id: again

        visible: root.waiting
        anchors.right: parent.right
        anchors.rightMargin: root.metrics.pad
        anchors.verticalCenter: parent.verticalCenter
        text: "Enter again"
        color: root.textColor
        font.bold: true
    }
}
