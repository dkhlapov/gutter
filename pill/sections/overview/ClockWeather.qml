pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.services
import qs.components
import "../../../lib/weather.js" as WeatherLib
import "../../../lib/calendar.js" as Cal
import "../../../lib/astro.js" as Astro
import "../../../lib/glyphs.js" as Glyphs

// The time and date, the weather now, the next few hours and the day's details.
CaptionBox {
    id: root

    readonly property var weather: Weather.data
    readonly property var sun: Astro.daylight(clock.date.getTime(), Cal.startOfDay(clock.date).getTime(), weather?.today ?? null, weather?.week[0] ?? null)

    tabs: [
        {
            text: "Today",
            accent: "teal"
        }
    ]
    currentTab: 0

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    ColumnLayout {
        id: body

        // What the box holds, by the height it is given: the hourly strip needs about 100 px under the header,
        // the detail tiles 46 px more.
        readonly property bool roomForHours: height >= 170
        readonly property bool roomForTiles: height >= 224

        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.pad

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                spacing: 2

                InkText {
                    text: Qt.formatTime(clock.date, "hh:mm")
                    font.pixelSize: 44
                    font.bold: true
                }

                InkText {
                    text: `${Qt.formatDate(clock.date, "ddd, d MMM")} · week ${Cal.isoWeek(clock.date)}`
                    font.pixelSize: 12
                }
            }

            Item {
                Layout.fillWidth: true
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                visible: root.weather !== null
                spacing: 2

                Row {
                    Layout.alignment: Qt.AlignRight
                    spacing: 6

                    InkIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: Glyphs.glyph(WeatherLib.icon(root.weather?.current.code ?? -1, root.weather?.current.isDay ?? true))
                        size: 30
                    }

                    InkText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: `${Math.round(root.weather?.current.temp ?? 0)}°`
                        font.pixelSize: 28
                        font.bold: true
                    }
                }

                InkText {
                    Layout.alignment: Qt.AlignRight
                    text: `${WeatherLib.condition(root.weather?.current.code ?? -1)} · H ${Math.round(root.weather?.today.max ?? 0)}° L ${Math.round(root.weather?.today.min ?? 0)}°`
                    font.pixelSize: 12
                }

                InkText {
                    Layout.alignment: Qt.AlignRight
                    visible: root.sun.next !== null
                    text: root.sun.next ? `${root.sun.next.label} ${root.sun.next.text}` : ""
                    font.pixelSize: 12
                    opacity: 0.75
                }
            }
        }

        HourlyStrip {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.weather !== null && body.roomForHours
            hours: root.weather?.hourly.slice(0, 6) ?? []
            longLabels: true
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.weather === null

            EmptyState {
                anchors.centerIn: parent
                icon: Weather.error ? "" : ""
                busy: !Weather.error
                text: Weather.error ? "Weather unavailable" : "Loading weather…"
            }
        }

        TileGrid {
            Layout.fillWidth: true
            visible: root.weather !== null && body.roomForTiles
            columns: 4
            model: root.weather ? [
                {
                    label: "Feels",
                    icon: "",
                    value: `${Math.round(root.weather.current.feels)}°`
                },
                {
                    label: "Rain",
                    icon: "",
                    value: `${root.weather.hourly[0]?.pop ?? 0}%`
                },
                {
                    label: "Wind",
                    icon: "",
                    value: `${Math.round(root.weather.current.wind)} ${Weather.windUnit}`
                },
                {
                    label: "Humidity",
                    icon: "",
                    value: `${root.weather.current.humidity}%`
                }
            ] : []

            delegate: InfoTile {
                required property var modelData

                label: modelData.label
                icon: modelData.icon
                value: modelData.value
            }
        }
    }
}
