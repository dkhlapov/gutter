import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components
import "tools"

// Scratchpad | timer and stopwatch | camera mirror over a row of toggles. Without a camera the
// camera card is hidden and the toggles become a column of tall tiles filling the room.
RowLayout {
    spacing: Theme.pad

    ScratchpadCard {
        Layout.fillWidth: true
        Layout.fillHeight: true
    }

    TimerCard {
        Layout.preferredWidth: 300
        Layout.fillHeight: true
    }

    ColumnLayout {
        // Nested layouts default to filling; this column stays 250 px so the scratchpad gets the rest.
        Layout.fillWidth: false
        Layout.preferredWidth: 250
        Layout.fillHeight: true
        spacing: Theme.pad

        CameraCard {
            id: camera

            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: available
        }

        // Three tiles: one row
        // under the camera, or a column of tall tiles without it, so rows are always full (rule 4).
        // The grid's right and bottom margins leave room for the tiles' hard shadows.
        TileGrid {
            Layout.fillWidth: true
            Layout.fillHeight: !camera.available
            Layout.preferredHeight: camera.available ? 58 + Theme.shadowOffset : -1
            Layout.rightMargin: Theme.shadowOffset
            Layout.bottomMargin: Theme.shadowOffset
            columns: camera.available ? 3 : 1
            model: [
                {
                    key: "mic"
                },
                {
                    key: "awake"
                },
                {
                    key: "lock"
                }
            ]

            delegate: ToggleTile {
                id: tile

                required property var modelData
                readonly property bool micTile: modelData.key === "mic"
                readonly property bool awakeTile: modelData.key === "awake"

                icon: micTile ? (QuickToggles.micMuted ? "\u{f036d}" : "\u{f036c}") : awakeTile ? "\u{f0176}" : "\u{f033e}"
                label: micTile ? "Microphone" : awakeTile ? "Keep awake" : "Lock"
                shortLabel: micTile ? (QuickToggles.micMuted ? "Muted" : "Mic") : awakeTile ? "Awake" : "Lock"
                status: micTile ? (QuickToggles.micMuted ? "Muted" : "On") : awakeTile ? (on ? "On" : "Off") : "Lock screen"
                on: micTile ? !QuickToggles.micMuted : awakeTile ? QuickToggles.keepAwake : false
                available: micTile ? QuickToggles.micReady : true
                onClicked: micTile ? QuickToggles.toggleMic() : awakeTile ? QuickToggles.toggleKeepAwake() : QuickToggles.lock()
            }
        }
    }
}
