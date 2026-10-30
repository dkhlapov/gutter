import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components
import "../../../lib/format.js" as Format

// Memory ring with used / total underneath.
CaptionBox {
    id: root

    tabs: [
        {
            text: "Memory",
            accent: "coral"
        }
    ]
    currentTab: 0

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8

        Ring {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 72
            value: Memory.percentage
            accent: "coral"
            icon: ""
        }

        InkText {
            Layout.alignment: Qt.AlignHCenter
            text: `${Format.kib(Memory.used)} / ${Format.kib(Memory.total)}`
        }
    }
}
