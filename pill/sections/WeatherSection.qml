pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.services
import qs.components
import "../../lib/weather.js" as WeatherLib
import "../../lib/glyphs.js" as Glyphs
import "../../lib/astro.js" as Astro

Item {
    id: root

    readonly property var weather: Weather.data
    // The hero box is sun yellow by day and navy at night; its text comes from the matching `Theme.on`.
    readonly property bool day: weather?.current.isDay ?? true
    readonly property string heroAccent: day ? "sun" : "navy"
    readonly property color ink: Theme.on[heroAccent]
    readonly property var moon: Astro.moonPhase(clock.date)
    readonly property var bounds: WeatherLib.weekBounds(weather?.week ?? [])

    SystemClock {
        id: clock

        precision: SystemClock.Hours
    }

    EmptyState {
        anchors.centerIn: parent
        visible: root.weather === null
        icon: Weather.error ? "" : ""
        busy: !Weather.error
        text: Weather.error ? "Weather unavailable" : "Loading weather…"
    }

    RowLayout {
        anchors.fill: parent
        visible: root.weather !== null
        spacing: Theme.pad

        CaptionBox {
            Layout.preferredWidth: 265
            Layout.fillHeight: true
            fill: Theme.accent[root.heroAccent]
            tabs: [
                {
                    text: "Now",
                    accent: root.day ? "navy" : "sun"
                }
            ]
            currentTab: 0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.pad
                spacing: Theme.gap

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    InkIcon {
                        icon: ""
                        size: 14
                        color: root.ink
                    }

                    InkText {
                        Layout.fillWidth: true
                        text: Weather.place
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight
                        color: root.ink
                    }

                    InkText {
                        text: `updated ${Qt.formatTime(new Date(Weather.updatedAt), "hh:mm")}`
                        color: Theme.mutedOn(root.ink, Theme.accent[root.heroAccent])
                    }

                    InkText {
                        visible: Weather.stale
                        text: "· stale"
                        font.bold: true
                        color: root.ink
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.gap

                    InkIcon {
                        icon: Glyphs.glyph(WeatherLib.icon(root.weather?.current.code ?? -1, root.weather?.current.isDay ?? true))
                        size: 52
                        color: root.ink
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: -4

                        InkText {
                            text: `${Math.round(root.weather?.current.temp ?? 0)}°`
                            font.pixelSize: 46
                            font.bold: true
                            color: root.ink
                        }

                        InkText {
                            Layout.fillWidth: true
                            text: WeatherLib.condition(root.weather?.current.code ?? -1)
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            color: root.ink
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    InkText {
                        Layout.fillWidth: true
                        text: `Feels like ${Math.round(root.weather?.current.feels ?? 0)}°`
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        color: root.ink
                    }

                    InkText {
                        text: `H ${Math.round(root.weather?.today.max ?? 0)}° · L ${Math.round(root.weather?.today.min ?? 0)}°`
                        font.pixelSize: 13
                        color: root.ink
                    }
                }

                // Sun and moon tiles share the free height (rule 5).
                TileGrid {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 2
                    model: [
                        {
                            label: "Sunrise",
                            icon: "",
                            value: root.weather?.today.sunrise?.text ?? "—"
                        },
                        {
                            label: "Sunset",
                            icon: "",
                            value: root.weather?.today.sunset?.text ?? "—"
                        }
                    ]

                    delegate: InfoTile {
                        required property var modelData

                        label: modelData.label
                        icon: modelData.icon
                        value: modelData.value
                    }
                }

                InfoTile {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    label: "Moon"
                    icon: ""
                    value: `${root.moon.name} · ${root.moon.illumination}% lit`
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.pad

            CaptionBox {
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                tabs: [
                    {
                        text: "Hourly",
                        accent: "teal"
                    }
                ]
                currentTab: 0

                HourlyStrip {
                    anchors.fill: parent
                    anchors.margins: Theme.gap
                    hours: root.weather?.hourly ?? []
                    showRain: true
                }
            }

            TileGrid {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 3
                rowSpacing: Theme.pad
                columnSpacing: Theme.pad
                model: root.weather ? [
                    {
                        label: "Wind",
                        icon: "",
                        value: `${Math.round(root.weather.current.wind)} ${Weather.windUnit}`
                    },
                    {
                        label: "Gusts",
                        icon: "",
                        value: `${Math.round(root.weather.current.gusts)} ${Weather.windUnit}`
                    },
                    {
                        label: "Humidity",
                        icon: "",
                        value: `${root.weather.current.humidity}%`
                    },
                    {
                        label: "UV",
                        icon: "",
                        value: `${Math.round(root.weather.current.uv)} ${WeatherLib.uvWord(root.weather.current.uv)}`
                    },
                    {
                        label: "Pressure",
                        icon: "",
                        value: `${Math.round(root.weather.current.pressure)} hPa`
                    },
                    {
                        label: "Air",
                        icon: "",
                        value: Weather.airQuality === null ? "—" : `${Math.round(Weather.airQuality)} ${WeatherLib.aqiWord(Weather.airQuality)}`
                    }
                ] : []

                delegate: InfoTile {
                    required property var modelData

                    large: true
                    label: modelData.label
                    icon: modelData.icon
                    value: modelData.value
                }
            }
        }

        CaptionBox {
            Layout.preferredWidth: 265
            Layout.fillHeight: true
            tabs: [
                {
                    text: "Week",
                    accent: "pink"
                }
            ]
            currentTab: 0

            // Seven rows share the box height (rule 5).
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.gap
                spacing: 0

                Repeater {
                    model: root.weather?.week ?? []

                    delegate: DayRow {
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        day: modelData
                        lo: root.bounds.lo
                        hi: root.bounds.hi
                    }
                }
            }
        }
    }
}
