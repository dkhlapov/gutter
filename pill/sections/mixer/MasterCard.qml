import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components
import "../../../lib/mixer.js" as MixerLib
import "../../../lib/volume.js" as VolumeLib
import "../../../lib/glyphs.js" as Glyphs

// The default output: a slider (drag, wheel), the mute button, the device name, the level and what is playing.
CaptionBox {
    id: root

    property int streamCount: 0

    tabs: [
        {
            text: "Master",
            accent: MixerLib.MASTER_ACCENT
        }
    ]
    currentTab: 0

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.pad

        InkSlider {
            accessibleName: "Volume"
            Layout.fillHeight: true
            vertical: true
            accent: MixerLib.MASTER_ACCENT
            muted: Audio.muted
            enabled: Audio.ready
            value: Audio.volume
            onMoved: v => Audio.setVolume(v)
            onStepped: steps => Audio.scroll(steps)
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.gap

            InkButton {
                // Room on the right and below for the button's hard shadow.
                Layout.rightMargin: Theme.shadowOffset
                Layout.bottomMargin: Theme.shadowOffset
                Layout.fillWidth: true
                icon: Glyphs.glyph(VolumeLib.icon(Audio.volume, Audio.muted))
                iconSize: 18
                text: Audio.muted ? "Muted" : "Mute"
                checked: Audio.muted
                checkable: true
                enabled: Audio.ready
                onClicked: Audio.toggleMute()
            }

            InkText {
                Layout.fillWidth: true
                text: Audio.sink?.description || Audio.sink?.nickname || "No output"
                font.pixelSize: Theme.textMin
                font.bold: true
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            Item {
                Layout.fillHeight: true
            }

            InkText {
                text: Audio.ready ? `${Math.round(Audio.volume * 100)}%` : "–"
                font.pixelSize: 34
                font.bold: true
            }

            // Nothing to say while it is quiet (the empty Apps card beside it says why); the line keeps its room so
            // the level above does not jump when an app starts.
            InkText {
                opacity: Audio.muted || root.streamCount > 0 ? 0.75 : 0
                text: Audio.muted ? "Muted" : `${root.streamCount} playing`
            }
        }
    }
}
