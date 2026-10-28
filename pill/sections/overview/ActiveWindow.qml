import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components

// The active window on this panel's monitor: its class as a label tab, then its title. Nothing shows when there
// is none; the row keeps its height so the cards below do not jump as focus moves between windows and empty
// workspaces.
Item {
    id: root

    property string screenName

    readonly property var toplevel: Hypr.activeToplevelOn(screenName)
    readonly property string windowClass: toplevel?.lastIpcObject?.class ?? ""

    implicitHeight: Theme.pillHeight - 2 * Theme.inkWidth

    RowLayout {
        anchors.fill: parent
        visible: root.toplevel !== null
        spacing: Theme.pad

        LabelTab {
            visible: root.windowClass !== ""
            text: root.windowClass
            accent: Theme.roleAccent.muted
        }

        InkText {
            Layout.fillWidth: true
            text: root.toplevel?.title ?? ""
            elide: Text.ElideRight
        }
    }
}
