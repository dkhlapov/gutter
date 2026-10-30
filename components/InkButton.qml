import QtQuick
import qs.theme

// A flat button with a hard shadow. Pressed (or checked) it drops onto its shadow, which then disappears. Checked,
// it also fills with the active role's colour, the same "on" in every section; an explicit accent wins, and is
// for identity (a button of a section's own colour), not state.
Item {
    id: root

    property string icon
    property real iconSize: 16
    property real textSize: 13
    property string text
    property string accent: ""
    property bool checked: false
    // A toggle, for a screen reader: it says whether it is checked.
    property bool checkable: false
    // What a screen reader calls the button: its text, or for an icon-only button the action ("Mute").
    property string accessibleName: text
    // The accent the face is drawn in: the explicit one, else the active role's while checked, else paper.
    readonly property string face: !enabled ? "" : accent !== "" ? accent : checked ? Theme.roleAccent.active : ""
    // True while pressed or checked; can be forced to show the pressed look.
    property bool down: area.pressed || checked

    signal clicked

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName
    Accessible.checkable: checkable
    Accessible.checked: checked
    Accessible.onPressAction: root.clicked()

    implicitWidth: row.implicitWidth + 2 * Theme.pad + 2 * Theme.inkWidth
    implicitHeight: Theme.pillHeight

    Rectangle {
        visible: !root.down && root.enabled
        x: Theme.shadowOffset
        y: Theme.shadowOffset
        width: parent.width
        height: parent.height
        color: Theme.shadow
    }

    Rectangle {
        x: root.down ? Theme.shadowOffset : 0
        y: root.down ? Theme.shadowOffset : 0
        width: parent.width
        height: parent.height
        // Disabled: flat paper, no shadow, outline kept; the text and icon are dimmed (not the surface).
        color: root.face === "" ? Theme.paper : Theme.accent[root.face]
        border.color: Theme.ink
        border.width: Theme.inkWidth

        Row {
            id: row

            readonly property color textColor: root.face === "" ? Theme.text : Theme.on[root.face]

            anchors.centerIn: parent
            spacing: Theme.gap
            opacity: root.enabled ? 1 : 0.4

            InkIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.icon !== ""
                icon: root.icon
                size: root.iconSize
                color: row.textColor
            }

            InkText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.text !== ""
                text: root.text
                color: row.textColor
                font.bold: true
                font.pixelSize: root.textSize
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
