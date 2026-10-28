import QtQuick
import Quickshell.Wayland
import qs.services
import qs.theme

// One monitor's lock surface: the compositor's own top-level, which nothing can cover. Whichever monitor's
// surface has the keyboard, its keys go to the one shared buffer (`Auth`), so every monitor shows the same dots.
// A missing focus cannot unlock anything: at worst the keys do nothing until the compositor focuses a surface
// (the one under the pointer), and the surface takes the focus when the pointer comes in.
WlSessionLockSurface {
    id: surface

    color: Theme.paper

    FocusScope {
        id: keys

        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            Auth.key(event);
            event.accepted = true;
        }

        // The pointer coming onto this monitor takes the focus, over a button too (a MouseArea under the content
        // never sees the pointer enter there).
        HoverHandler {
            onHoveredChanged: {
                if (hovered)
                    keys.forceActiveFocus();
            }
        }

        // Under the content, so the buttons on it (the player's, the layout chip) get their own clicks. Neither
        // takes the keyboard focus: the keys stay with `keys`, and so with the password.
        MouseArea {
            anchors.fill: parent
            onPressed: keys.forceActiveFocus()
        }

        LockContent {
            anchors.fill: parent
            screenInfo: surface.screen
        }
    }

    Component.onCompleted: keys.forceActiveFocus()
}
