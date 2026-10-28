pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.theme

// A tray item's menu as a caption box: the item's title as its tab (none without a title), entries below.
// Separators are ink lines, check boxes and radio buttons are square ticks, an entry with a submenu opens it inline
// under itself.
// Sized by its caller: the implicit size is the whole menu; a smaller `height` makes the entries scroll.
// Takes the keyboard focus while it exists, so Escape closes the menu (not the panel); the focus goes back to
// whatever had it when the menu closes.
CaptionBox {
    id: root

    required property QsMenuHandle menu
    property string title
    property string accent: Theme.roleAccent.active

    // An entry was triggered, Escape was pressed.
    signal dismissed

    readonly property real bodyWidth: 240

    QtObject {
        id: focusState

        property Item previousFocus: null
        property bool focusRestored: false
    }

    // Gives the focus back once, however the menu goes: hidden by its caller, or destroyed.
    function restoreFocus() {
        if (focusState.focusRestored)
            return;
        focusState.focusRestored = true;
        if (focusState.previousFocus?.visible)
            focusState.previousFocus.forceActiveFocus();
    }

    // No title, no tab: an empty one would be a blank plate.
    tabs: root.title === "" ? [] : [
        {
            text: root.title,
            accent: root.accent
        }
    ]
    currentTab: root.title === "" ? -1 : 0

    Keys.onEscapePressed: event => {
        root.dismissed();
        event.accepted = true;
    }

    Component.onCompleted: {
        focusState.previousFocus = Window.window?.activeFocusItem ?? null;
        forceActiveFocus();
    }
    Component.onDestruction: restoreFocus()
    onVisibleChanged: {
        if (!visible)
            restoreFocus();
    }

    // Keeps a click between two entries from reaching the click-outside area underneath and closing the menu.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Flickable {
        id: flick

        anchors.fill: parent
        implicitWidth: root.bodyWidth
        implicitHeight: entries.implicitHeight
        contentWidth: width
        contentHeight: entries.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        // Scrolled by the wheel below, not dragged: a drag on an entry is a click.
        interactive: false
        clip: true

        InkMenuList {
            id: entries

            width: flick.width
            handle: root.menu
            accent: root.accent
            onDismissed: root.dismissed()
        }
    }

    MouseArea {
        anchors.fill: flick
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            if (Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y) || wheel.angleDelta.y === 0
                || flick.contentHeight <= flick.height) {
                wheel.accepted = false; // horizontal scroll switches sections
                return;
            }
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - wheel.angleDelta.y / 2));
        }
    }

    // Shows there is more above or below.
    Item {
        anchors.fill: flick
        visible: flick.contentHeight > flick.height

        Rectangle {
            x: parent.width - width - 2
            y: parent.height * flick.contentY / flick.contentHeight
            width: Theme.inkWidth
            height: parent.height * parent.height / flick.contentHeight
            color: Theme.text
        }
    }
}
