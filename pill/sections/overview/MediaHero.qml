import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components

// What is playing: cover, player, title and artist, the visualiser while it plays, progress and transport.
CaptionBox {
    tabs: [
        {
            text: "Now playing",
            accent: "pink"
        }
    ]
    currentTab: 0

    EmptyState {
        anchors.centerIn: parent
        visible: Media.active === null
        icon: "\u{f075a}" // md-music
        text: "Nothing playing"
        hint: "Play something in a music app and it shows up here."
        textWidth: 170
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad
        visible: Media.active !== null
        spacing: Theme.pad

        CoverArt {
            Layout.preferredWidth: 160
            Layout.fillHeight: true
            source: Media.artUrl
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.gap

            PlayerChip {
                // Room on the right and below for the button's hard shadow.
                Layout.rightMargin: Theme.shadowOffset
                Layout.bottomMargin: Theme.shadowOffset
                player: Media.active
                selectable: false
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                InkText {
                    Layout.fillWidth: true
                    text: Media.title || "Unknown track"
                    font.pixelSize: 18
                    font.bold: true
                    elide: Text.ElideRight
                }

                InkText {
                    Layout.fillWidth: true
                    text: Media.artist
                    elide: Text.ElideRight
                    color: Theme.textMuted
                }
            }

            // Keeps its height while paused so the layout does not jump.
            Loader {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                active: Media.playing

                sourceComponent: Visualiser {
                    color: Theme.accent.pink
                }
            }

            MediaProgress {
                Layout.fillWidth: true
            }

            Transport {
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
