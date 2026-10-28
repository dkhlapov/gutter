import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.services
import qs.components
import "overview"
import "../../lib/volume.js" as VolumeLib
import "../../lib/glyphs.js" as Glyphs
import "../../lib/ddc.js" as DdcLib

// The focused window, then the cards: now playing, clock and weather, levels. The workspaces live in the
// workspace bar at the top left, the status chips and the tray in the bar at the top right (bar/).
ColumnLayout {
    id: root

    property ShellScreen screen

    readonly property string screenName: screen?.name ?? ""
    readonly property real brightness: Brightness.levels[screenName] ?? -1

    spacing: Theme.pad

    ServiceRef {
        service: Cpu
    }
    ServiceRef {
        service: Memory
    }
    ServiceRef {
        service: Storage
    }

    ActiveWindow {
        Layout.fillWidth: true
        screenName: root.screenName
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        columns: 3
        rowSpacing: Theme.pad
        columnSpacing: Theme.pad

        MediaHero {
            Layout.rowSpan: 2
            Layout.preferredWidth: 440
            Layout.fillHeight: true
        }

        ClockWeather {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        CaptionBox {
            Layout.rowSpan: 2
            Layout.preferredWidth: 126
            Layout.fillHeight: true
            tabs: [
                {
                    text: "Levels",
                    accent: "teal"
                }
            ]
            currentTab: 0

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.pad
                spacing: Theme.gap

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.gap

                    InkSlider {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillHeight: true
                        vertical: true
                        accent: "teal"
                        muted: Audio.muted
                        enabled: Audio.ready
                        value: Audio.volume
                        onMoved: v => Audio.setVolume(v)
                        onStepped: steps => Audio.scroll(steps)
                    }

                    InkButton {
                        Layout.alignment: Qt.AlignHCenter
                        // Room on the right and below for the button's hard shadow.
                        Layout.rightMargin: Theme.shadowOffset
                        Layout.bottomMargin: Theme.shadowOffset
                        icon: Glyphs.glyph(VolumeLib.icon(Audio.volume, Audio.muted))
                        iconSize: 18
                        checked: Audio.muted
                        enabled: Audio.ready
                        onClicked: Audio.toggleMute()
                    }
                }

                // The monitor the panel is open on; 5 % per wheel notch, like the brightness keys.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.gap

                    InkSlider {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillHeight: true
                        vertical: true
                        accent: "sun"
                        enabled: Brightness.hasDdc(root.screenName) && root.brightness >= 0
                        value: root.brightness
                        onMoved: v => Brightness.setLevel(root.screenName, v)
                        onStepped: steps => Brightness.setLevel(root.screenName, DdcLib.step(root.brightness, steps * 0.05))
                    }

                    // Same height as the mute button beside it, shadow room included.
                    InkIcon {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredHeight: Theme.pillHeight + Theme.shadowOffset
                        verticalAlignment: Text.AlignVCenter
                        icon: Glyphs.glyph("light_mode")
                        size: 18
                        opacity: Brightness.hasDdc(root.screenName) ? 1 : 0.4
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false // nested layouts default to filling; this row stays 48 px
            Layout.preferredHeight: 48
            spacing: Theme.gap

            ResourceTile {
                icon: ""
                label: "CPU"
                value: Cpu.percentage
                accent: "teal"
            }

            ResourceTile {
                icon: ""
                label: "RAM"
                value: Memory.percentage
                accent: "magenta"
            }

            ResourceTile {
                icon: ""
                label: "Disk"
                value: Storage.primaryDisk?.perc ?? 0
                accent: "sun"
            }
        }
    }
}
