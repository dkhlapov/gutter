import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.components

// Quick toggle. Off, it is a plain button; on, it drops onto its shadow (InkButton's checked look) and fills
// with the coral accent. Short tiles (a row under the camera) show icon and label; tall ones (a column when
// there is no camera) make the icon bigger and add the state below the label.
Item {
    id: root

    property string icon
    property string label
    property string shortLabel: label
    property string status: on ? "On" : "Off"
    property bool on: false
    property bool available: true
    readonly property bool tall: height > 96
    // An unavailable tile is paper whatever its state, as InkButton draws it.
    readonly property bool lit: on && available
    readonly property color ink: lit ? Theme.on.coral : Theme.text

    signal clicked

    Layout.fillWidth: true
    Layout.fillHeight: true
    implicitWidth: 60
    implicitHeight: 58

    InkButton {
        id: button

        anchors.fill: parent
        accent: root.lit ? "coral" : ""
        checked: root.lit
        enabled: root.available
        onClicked: root.clicked()
    }

    // Follows the button when it drops onto its shadow.
    Item {
        x: button.down ? Theme.shadowOffset : 0
        y: button.down ? Theme.shadowOffset : 0
        width: root.width
        height: root.height
        opacity: root.available ? 1 : 0.4

        Column {
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.inkWidth - 8
            spacing: root.tall ? 8 : 2

            InkIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                icon: root.icon
                size: root.tall ? 30 : 20
                color: root.ink
            }

            Column {
                width: parent.width
                spacing: 0

                InkText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.tall ? root.label : root.shortLabel
                    font.pixelSize: root.tall ? 14 : 11
                    font.bold: true
                    elide: Text.ElideRight
                    color: root.ink
                }

                InkText {
                    width: parent.width
                    visible: root.tall && root.status !== ""
                    horizontalAlignment: Text.AlignHCenter
                    text: root.status
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    color: root.ink
                    opacity: 0.8
                }
            }
        }
    }
}
