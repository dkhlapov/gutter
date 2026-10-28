pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components

Item {
    id: root

    readonly property int lyricIndex: Lyrics.hasLyrics ? Lyrics.indexForTime(Media.position) : -1

    EmptyState {
        anchors.centerIn: parent
        visible: Media.active === null
        icon: ""
        text: "Nothing playing"
    }

    RowLayout {
        anchors.fill: parent
        visible: Media.active !== null
        spacing: Theme.pad

        CaptionBox {
            Layout.preferredWidth: 336
            Layout.fillHeight: true
            tabs: [
                {
                    text: "Cover",
                    accent: "pink"
                }
            ]
            currentTab: 0

            CoverArt {
                anchors.fill: parent
                anchors.margins: Theme.gap
                source: Media.artUrl
            }
        }

        CaptionBox {
            Layout.fillWidth: true
            Layout.fillHeight: true
            tabs: [
                {
                    text: "Now playing",
                    accent: "pink"
                }
            ]
            currentTab: 0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.pad
                spacing: Theme.gap

                Row {
                    visible: Media.players.length > 1
                    spacing: Theme.pad

                    Repeater {
                        model: Media.players

                        delegate: PlayerChip {
                            required property var modelData

                            player: modelData
                            highlighted: modelData === Media.active
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    InkText {
                        Layout.fillWidth: true
                        text: Media.title || "Unknown track"
                        font.pixelSize: 22
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    InkText {
                        Layout.fillWidth: true
                        text: [Media.artist, Media.album].filter(s => s).join(" · ")
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        opacity: 0.7
                    }
                }

                // Takes the free height (rule 5); keeps it while paused.
                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
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
                    extended: true
                    playSize: 46
                }
            }
        }

        CaptionBox {
            Layout.preferredWidth: 290
            Layout.fillHeight: true
            tabs: [
                {
                    text: "Lyrics",
                    accent: "pink"
                }
            ]
            currentTab: 0

            // The current line stays in the middle of the box.
            ListView {
                id: lyrics

                anchors.fill: parent
                anchors.margins: Theme.pad
                visible: Lyrics.hasLyrics
                clip: true
                interactive: false
                spacing: Theme.gap
                model: Lyrics.lyrics
                currentIndex: root.lyricIndex
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: height / 2 - 14
                preferredHighlightEnd: height / 2 + 14
                highlightMoveDuration: 400

                delegate: Item {
                    id: row

                    required property string modelData
                    required property int index
                    readonly property bool current: index === lyrics.currentIndex

                    width: ListView.view.width
                    height: line.implicitHeight + 8

                    Rectangle {
                        anchors.fill: parent
                        visible: row.current && row.modelData !== ""
                        color: Theme.accent.pink
                        border.color: Theme.ink
                        border.width: Theme.inkWidth
                    }

                    InkText {
                        id: line

                        x: Theme.pad
                        width: parent.width - 2 * Theme.pad
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.WordWrap
                        text: row.modelData
                        font.pixelSize: row.current ? 16 : 14
                        font.bold: row.current
                        color: row.current ? Theme.on.pink : Theme.text
                        opacity: row.current ? 1 : Math.abs(row.index - lyrics.currentIndex) === 1 ? 0.7 : 0.4
                    }
                }
            }

            EmptyState {
                anchors.centerIn: parent
                visible: !Lyrics.hasLyrics
                icon: "\uf075"
                text: "No lyrics"
            }
        }
    }
}
