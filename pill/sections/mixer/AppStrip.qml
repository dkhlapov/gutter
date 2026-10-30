import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.theme
import qs.components
import "../../../lib/mixer.js" as MixerLib
import "../../../lib/volume.js" as VolumeLib
import "../../../lib/glyphs.js" as Glyphs

// One application playing audio: its icon on its accent, a slider, the mute button, the name and what it
// plays. `position` is its place in the row; the accent cycles through the palette without the master slider's.
InkBox {
    id: root

    required property PwNode node
    required property int position
    readonly property var info: MixerLib.describe(node)
    readonly property var audio: node?.audio ?? null
    readonly property string accent: MixerLib.stripAccent(position, Theme.accentNames)
    readonly property string iconPath: Quickshell.iconPath(info?.icon ?? "", true)
    readonly property real level: audio?.volume ?? 0
    readonly property bool muted: audio?.muted ?? false

    function setLevel(v: real): void {
        if (!audio)
            return;
        audio.muted = false;
        audio.volume = Math.max(0, Math.min(1, v));
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 38
            implicitHeight: 38
            color: Theme.accent[root.accent]
            border.color: Theme.ink
            border.width: Theme.inkWidth

            Image {
                anchors.fill: parent
                anchors.margins: Theme.inkWidth + 1
                visible: root.iconPath !== ""
                source: root.iconPath
                sourceSize: Qt.size(60, 60)
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            InkIcon {
                anchors.centerIn: parent
                visible: root.iconPath === ""
                icon: ""
                size: 18
                color: Theme.on[root.accent]
            }
        }

        InkText {
            Layout.alignment: Qt.AlignHCenter
            text: `${Math.round(root.level * 100)}%`
            font.bold: true
        }

        InkSlider {
            accessibleName: `${root.info?.app || "App"} volume`
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            vertical: true
            accent: root.accent
            muted: root.muted
            enabled: root.audio !== null
            value: root.level
            onMoved: v => root.setLevel(v)
            onStepped: steps => root.setLevel(VolumeLib.step(root.level, steps))
        }

        InkButton {
            accessibleName: `Mute ${root.info?.app || "App"}`
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 26
            Layout.rightMargin: Theme.shadowOffset
            icon: Glyphs.glyph(VolumeLib.icon(root.level, root.muted))
            iconSize: 14
            checked: root.muted
            checkable: true
            enabled: root.audio !== null
            onClicked: if (root.audio)
                root.audio.muted = !root.audio.muted
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            InkText {
                Layout.fillWidth: true
                text: root.info?.app ?? ""
                font.bold: true
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            InkText {
                Layout.fillWidth: true
                text: root.info?.title || " "
                color: Theme.textMuted
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
