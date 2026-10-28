pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import "../lib/weather.js" as WeatherLib
import "../lib/glyphs.js" as Glyphs

// Hour columns that stretch to fill the strip (rule 5); the first one is "Now", on a sun-yellow plate. The icons
// of a rainy hour are teal (DayRow's colour for a rainy day); the "Now" column is never tinted.
RowLayout {
    id: root

    property var hours: []
    property bool longLabels: false
    property bool showRain: false
    property real iconPx: 28
    property real tempPx: 13

    spacing: Theme.gap

    Repeater {
        model: root.hours

        delegate: Rectangle {
            id: col

            required property var modelData
            required property int index
            readonly property bool now: index === 0
            readonly property bool wet: modelData.pop >= 30
            readonly property bool rainy: !now && WeatherLib.isRainy(modelData.code)
            readonly property color ink: now ? Theme.on.sun : Theme.text
            readonly property color iconInk: rainy ? Theme.accent.teal : ink

            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: content.implicitWidth + 8
            implicitHeight: content.implicitHeight + 12
            color: now ? Theme.accent.sun : "transparent"
            border.color: Theme.ink
            border.width: now ? Theme.inkWidth : 0

            ColumnLayout {
                id: content

                anchors.centerIn: parent
                spacing: 5

                InkText {
                    Layout.alignment: Qt.AlignHCenter
                    text: col.now ? "Now" : root.longLabels ? `${col.modelData.hour}:00` : col.modelData.hour
                    font.pixelSize: 13
                    font.bold: col.now
                    color: col.ink
                    opacity: col.now ? 1 : 0.7
                }

                InkIcon {
                    Layout.alignment: Qt.AlignHCenter
                    icon: Glyphs.glyph(WeatherLib.icon(col.modelData.code, col.modelData.isDay))
                    size: root.iconPx
                    color: col.iconInk
                }

                InkText {
                    Layout.alignment: Qt.AlignHCenter
                    text: `${Math.round(col.modelData.temp)}°`
                    font.pixelSize: root.tempPx
                    font.bold: true
                    color: col.ink
                }

                Row {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.showRain
                    spacing: 2

                    InkIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: ""
                        size: 12
                        color: col.iconInk
                        opacity: col.wet ? 1 : 0.5
                    }

                    InkText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: `${col.modelData.pop}%`
                        font.pixelSize: 11
                        font.bold: col.wet
                        color: col.ink
                        opacity: col.wet ? 1 : 0.5
                    }
                }
            }
        }
    }
}
