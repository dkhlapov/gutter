pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.theme
import qs.services
import qs.components
import "mixer"
import "../../lib/mixer.js" as MixerLib

// Master volume of the default output on the left, one slider per application playing audio on the right.
// The tracker binds the stream nodes so their properties and volumes are readable; it only exists while
// this tab is open.
RowLayout {
    id: root

    // Bracket access: qmllint types Pipewire.nodes as an UntypedObjectModel and rejects `.values`.
    readonly property var candidates: Pipewire.nodes["values"].filter(n => n.isStream)
    readonly property var streams: MixerLib.playback(candidates)

    spacing: Theme.pad

    PwObjectTracker {
        objects: root.candidates
    }

    MasterCard {
        Layout.preferredWidth: 230
        Layout.fillHeight: true
        streamCount: root.streams.length
    }

    CaptionBox {
        Layout.fillWidth: true
        Layout.fillHeight: true
        tabs: [
            {
                text: "Apps",
                accent: "teal"
            }
        ]
        currentTab: 0

        EmptyState {
            anchors.centerIn: parent
            visible: root.streams.length === 0
            accent: "teal"
            icon: "\u{f057e}" // md-volume_high
            textWidth: 280
            text: "No app is playing audio"
            hint: "Each app that plays sound gets its own slider here."
        }

        ListView {
            id: list

            anchors.fill: parent
            anchors.margins: Theme.pad
            visible: root.streams.length > 0
            orientation: ListView.Horizontal
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.streams

            delegate: Item {
                id: cell

                required property var modelData
                required property int index

                width: 104 + Theme.shadowOffset + 8
                height: ListView.view.height

                // Room on the right and below for the strip's hard shadow.
                AppStrip {
                    width: 104
                    height: parent.height - Theme.shadowOffset
                    node: cell.modelData
                    position: cell.index
                }
            }
        }
    }
}
