import QtQuick
import qs.theme
import qs.services

// A player's name as a button; the selected one sits pressed. Clicking selects that player.
InkButton {
    id: root

    required property var player
    property bool highlighted: false
    // False where the chip only names the current player (the overview), so a screen reader hears a button, not an
    // unchecked choice.
    property bool selectable: true

    icon: root.player?.isPlaying ? "" : ""
    text: root.player?.identity ?? ""
    checked: highlighted
    checkable: selectable
    onClicked: {
        if (root.player)
            Media.select(root.player.dbusName);
    }
}
