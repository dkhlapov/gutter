pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import "../lib/calendar.js" as Cal

// A ruled month: week numbers on the left, weekday headers on top, one ink-outlined cell per day. Cells share
// their borders (negative spacing), so every rule is one inkWidth line. Today is a sun cell with halftone.
RowLayout {
    id: root

    property int year
    property int month
    property int weekStart
    property date today
    readonly property var rows: Cal.monthRows(year, month, weekStart)
    readonly property int headerHeight: 24

    spacing: -Theme.inkWidth

    // fillWidth children would make this column fill too and squeeze the days.
    ColumnLayout {
        Layout.preferredWidth: 52
        Layout.fillWidth: false
        Layout.fillHeight: true
        spacing: -Theme.inkWidth

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: root.headerHeight
            color: Theme.accent.navy
            border.color: Theme.ink
            border.width: Theme.inkWidth

            InkText {
                anchors.centerIn: parent
                text: "WK"
                font.pixelSize: 11
                font.bold: true
                color: Theme.on.navy
            }
        }

        Repeater {
            model: root.rows

            delegate: Rectangle {
                id: week

                required property var modelData
                readonly property bool current: modelData.cells.some(c => Cal.sameDay(c, root.today))

                Layout.fillWidth: true
                Layout.fillHeight: true
                color: current ? Theme.accent.sun : Theme.paper
                border.color: Theme.ink
                border.width: Theme.inkWidth

                InkText {
                    anchors.centerIn: parent
                    text: `W${week.modelData.week}`
                    font.pixelSize: 12
                    font.bold: week.current
                    color: week.current ? Theme.on.sun : Theme.text
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: -Theme.inkWidth

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: root.headerHeight
            spacing: -Theme.inkWidth

            Repeater {
                model: Cal.weekdays(root.weekStart)

                delegate: Rectangle {
                    id: head

                    required property int modelData
                    // Weekends are a quieter, paper header: red is the urgent colour and says nothing about the date.
                    readonly property bool weekend: modelData === 0 || modelData === 6

                    Layout.fillWidth: true
                    Layout.preferredHeight: root.headerHeight
                    Layout.preferredWidth: 1
                    color: head.weekend ? Theme.paper : Theme.accent.navy
                    border.color: Theme.ink
                    border.width: Theme.inkWidth

                    InkText {
                        anchors.centerIn: parent
                        text: Qt.locale().dayName(head.modelData, Locale.ShortFormat).toUpperCase()
                        font.pixelSize: 11
                        font.bold: true
                        color: head.weekend ? Theme.text : Theme.on.navy
                    }
                }
            }
        }

        Repeater {
            model: root.rows

            delegate: RowLayout {
                required property var modelData

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: -Theme.inkWidth

                Repeater {
                    model: parent.modelData.cells

                    delegate: Rectangle {
                        id: cell

                        required property var modelData
                        readonly property bool isToday: Cal.sameDay(modelData, root.today)

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        color: isToday ? Theme.accent.sun : Theme.paper
                        border.color: Theme.ink
                        border.width: Theme.inkWidth

                        Item {
                            anchors.fill: parent
                            anchors.margins: Theme.inkWidth
                            visible: cell.isToday

                            Halftone {}
                        }

                        // A solid patch under the number, so the dots do not run through it.
                        Rectangle {
                            anchors.centerIn: label
                            width: label.implicitWidth + 2 * Theme.inkWidth
                            height: label.implicitHeight + 2
                            visible: cell.isToday
                            color: Theme.accent.sun
                        }

                        InkText {
                            id: label

                            anchors.centerIn: parent
                            text: cell.modelData.day
                            font.pixelSize: 16
                            font.bold: cell.isToday
                            color: cell.isToday ? Theme.on.sun : Theme.text
                            opacity: cell.isToday || cell.modelData.inMonth ? 1 : 0.3
                        }
                    }
                }
            }
        }
    }
}
