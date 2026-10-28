import QtQuick
import qs.theme
import qs.services

// A player's name as a button; the selected one sits pressed. Clicking selects that player.
InkButton {
    id: root

    required property var player
    property bool highlighted: false

    icon: root.player?.isPlaying ? "" : ""
    text: root.player?.identity ?? ""
    checked: highlighted
    onClicked: {
        if (root.player)
            Media.select(root.player.dbusName);
    }
}
