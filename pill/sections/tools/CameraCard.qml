import QtQuick
import qs.theme
import qs.components

// Camera mirror in a caption box. Off until switched on; the camera stops whenever the Tools tab closes.
// `available` is false without a camera or Qt Multimedia, and the Tools tab then hides the card and gives
// its room to the toggles.
CaptionBox {
    id: root

    property bool on: false
    readonly property var view: loader.item
    readonly property bool available: loader.status === Loader.Ready && (view?.hasCamera ?? false)
    readonly property string problem: loader.status === Loader.Error ? "Needs qt6-multimedia" : !view ? "" : !view.hasCamera ? "No camera found" : view.error

    tabs: [
        {
            text: "Camera",
            accent: "pink"
        }
    ]
    currentTab: 0

    // The picture, square-cornered inside the box's ink outline.
    Item {
        anchors.fill: parent
        clip: true

        Loader {
            id: loader

            anchors.fill: parent
            source: "CameraView.qml"
        }

        // The view is loaded by URL, so its `active` is set from outside rather than by name.
        Binding {
            target: loader.item
            property: "active"
            value: root.on && root.visible
        }

        // Off, starting or unavailable: the camera glyph, a title and the state.
        Column {
            anchors.centerIn: parent
            visible: !(root.view?.live ?? false)
            spacing: Theme.gap

            InkBox {
                anchors.horizontalCenter: parent.horizontalCenter
                fill: Theme.accent[root.problem !== "" ? "navy" : "pink"]

                InkIcon {
                    anchors.centerIn: parent
                    icon: root.problem !== "" ? "\u{f05df}" : "\u{f0100}"
                    size: 32
                    color: Theme.on[root.problem !== "" ? "navy" : "pink"]
                }

                // The glyph is centred, which the box counts as 0, so the size is stated.
                implicitWidth: 76
                implicitHeight: 62
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 1

                InkText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Camera mirror"
                    font.pixelSize: 14
                    font.bold: true
                }

                InkText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.problem !== "" ? root.problem : root.on ? "Starting…" : "Check yourself before a call"
                    color: Theme.textMuted
                }
            }
        }

        InkButton {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: Theme.pad + Theme.shadowOffset
            anchors.bottomMargin: Theme.pad + Theme.shadowOffset
            width: 36
            height: 32
            visible: root.problem === "" || root.on
            icon: root.on ? "\u{f0568}" : "\u{f0567}"
            iconSize: 18
            checked: root.on
            accent: root.on ? "" : "pink"
            onClicked: root.on = !root.on
        }
    }
}
