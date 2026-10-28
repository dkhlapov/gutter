import QtQuick
import Quickshell
import qs.components
import qs.theme

// Every ink component in one window, for looking at. Loaded by shell.qml only when GUTTER_GALLERY=1.
FloatingWindow {
    title: "gutter-gallery"
    implicitWidth: 880
    implicitHeight: 620
    color: Theme.accent.navy

    Column {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 24

        Row {
            spacing: Theme.gap

            Repeater {
                model: Theme.accentNames

                LabelTab {
                    required property string modelData

                    text: modelData
                    accent: modelData
                }
            }
        }

        Row {
            spacing: 32

            InkBox {
                width: 160
                height: 110

                InkText {
                    anchors.centerIn: parent
                    text: "INK BOX"
                }
            }

            CaptionBox {
                id: caption

                width: 300
                height: 130
                currentTab: 0
                tabs: [
                    {
                        text: "Overview",
                        accent: "sun"
                    },
                    {
                        text: "Music",
                        accent: "coral"
                    },
                    {
                        text: "Tools",
                        accent: "magenta"
                    }
                ]
                onTabClicked: index => currentTab = index

                InkText {
                    anchors.centerIn: parent
                    text: "tab " + caption.currentTab
                }
            }

            SpeechBubble {
                text: "Time's up!"
            }
        }

        Row {
            spacing: 32

            InkBox {
                width: 120
                height: 90
                shadow: false

                Halftone {}
            }

            InkBox {
                width: 120
                height: 90
                shadow: false
                fill: Theme.role.active

                Halftone {}
            }

            Column {
                spacing: 16

                Row {
                    spacing: 20

                    InkButton {
                        text: "Rest"
                        icon: ""
                        accent: "sun"
                    }

                    InkButton {
                        text: "Pressed"
                        icon: ""
                        accent: "sun"
                        down: true
                    }

                    InkButton {
                        text: "Plain"
                    }
                }

                InkSlider {
                    id: slider

                    width: 260
                    value: 0.6
                    onMoved: v => value = v
                }
            }

            InkSlider {
                height: 90
                vertical: true
                value: 0.3
            }
        }

        // Cycling demo: the caption box edge must stay put across tab changes, and the bubble must
        // resize with its text.
        Row {
            spacing: 32

            CaptionBox {
                width: 300
                height: 90
                currentTab: demo.step % 4 - 1
                tabs: [
                    {
                        text: "One",
                        accent: "lime"
                    },
                    {
                        text: "Two",
                        accent: "pink"
                    },
                    {
                        text: "Three",
                        accent: "teal"
                    }
                ]

                InkText {
                    anchors.centerIn: parent
                    text: "constant content"
                }
            }

            SpeechBubble {
                text: demo.step % 2 === 0 ? "A much longer balloon text" : "Hi"
            }

            Timer {
                id: demo

                property int step: 0

                interval: 1500
                running: true
                repeat: true
                onTriggered: step++
            }
        }
    }
}
