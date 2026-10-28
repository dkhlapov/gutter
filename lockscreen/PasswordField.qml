pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.services
import qs.theme

// The password field: an ink box with one square per typed character (the same count on every monitor, the
// password itself never reaches the screen), a fingerprint glyph while the reader is in use, and a coral strip
// when a test PAM folder is in use, so a test run cannot be mistaken for the real thing.
InkBox {
    id: root

    property real ui: 1

    // Squares drawn at most (fewer when the field is too narrow for them); a longer password shows the first ones only.
    readonly property int maxDots: 24
    readonly property real dot: Math.round(8 * ui)
    readonly property real gap: Math.round(5 * ui)
    readonly property real pad: Math.round(10 * ui)
    readonly property real fieldWidth: Math.round(260 * ui)
    // The squares that fit between the padding and the fingerprint glyph (at most `maxDots`).
    readonly property int fitDots: Math.max(1, Math.min(maxDots, Math.floor((fieldWidth - 2 * pad - Math.round(26 * ui) + gap) / (dot + gap))))
    readonly property real rowHeight: Math.round(34 * ui)

    // A failed check: the field jerks sideways once and settles (the bubble under it says why, and shakes too).
    transform: Translate {
        x: shake.offset
    }

    Shake {
        id: shake

        ui: root.ui
    }

    Item {
        implicitWidth: root.fieldWidth
        implicitHeight: banner.height + row.height

        Rectangle {
            id: banner

            visible: Auth.testPam
            width: root.fieldWidth
            height: visible ? Math.round(16 * root.ui) + Theme.inkWidth : 0
            color: Theme.accent.coral

            InkText {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -Math.round(Theme.inkWidth / 2)
                text: "TEST PAM"
                color: Theme.on.coral
                font.bold: true
                font.pixelSize: Math.round(10 * root.ui)
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Theme.inkWidth
                color: Theme.ink
            }
        }

        Item {
            id: row

            y: banner.height
            width: root.fieldWidth
            height: root.rowHeight

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: root.pad
                spacing: root.gap

                Repeater {
                    model: Math.min(Auth.length, root.fitDots)

                    Rectangle {
                        width: root.dot
                        height: root.dot
                        color: Theme.text
                    }
                }
            }

            InkText {
                visible: Auth.length === 0
                anchors.verticalCenter: parent.verticalCenter
                x: root.pad
                opacity: Auth.checking ? 1 : 0.5
                text: Auth.checking ? "…" : "Password"
                font.pixelSize: Math.round(12 * root.ui)
            }

            InkIcon {
                visible: Auth.fingerprintLive
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: root.pad
                icon: "\u{f0237}"
                size: Math.round(18 * root.ui)
            }
        }
    }
}
