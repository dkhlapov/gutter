pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.services
import qs.settings
import qs.components
import "../../lib/calendar.js" as Cal
import "../../lib/astro.js" as Astro
import "../../lib/worldclock.js" as ClockLib
import "../../lib/wheel.js" as WheelLib

Item {
    id: root

    readonly property int weekStart: Qt.locale().firstDayOfWeek % 7
    readonly property date now: clock.date
    readonly property bool onCurrentMonth: year === now.getFullYear() && month === now.getMonth()
    property int year: now.getFullYear()
    property int month: now.getMonth()
    property real wheelRest: 0

    function shift(delta: int): void {
        const m = Cal.shiftMonth(year, month, delta);
        year = m.year;
        month = m.month;
    }

    function showToday(): void {
        year = now.getFullYear();
        month = now.getMonth();
    }

    SystemClock {
        id: clock

        precision: SystemClock.Seconds
    }

    RowLayout {
        anchors.fill: parent
        spacing: Theme.pad

        CaptionBox {
            Layout.preferredWidth: 380
            Layout.fillHeight: true
            tabs: [
                {
                    text: "Today",
                    accent: "teal"
                }
            ]
            currentTab: 0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.pad
                spacing: Theme.pad

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    AnalogClock {
                        date: root.now
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        Row {
                            InkText {
                                text: Qt.formatTime(root.now, "hh:mm")
                                font.pixelSize: 44
                                font.bold: true
                            }

                            InkText {
                                anchors.baseline: parent.children[0].baseline
                                text: Qt.formatTime(root.now, ":ss")
                                font.pixelSize: 18
                                color: Theme.textMuted
                            }
                        }

                        InkText {
                            Layout.fillWidth: true
                            text: Qt.formatDate(root.now, "dddd, d MMMM")
                            font.pixelSize: 14
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        InkText {
                            Layout.fillWidth: true
                            text: `Week ${Cal.isoWeek(root.now)} · day ${Cal.dayOfYear(root.now)} of ${Cal.daysInYear(root.now.getFullYear())}`
                            elide: Text.ElideRight
                            color: Theme.textMuted
                        }
                    }
                }

                // Takes the free height (rule 5).
                TileGrid {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 2
                    // Does not read the clock, so the tiles are not rebuilt every second.
                    model: ClockLib.tiles(Settings.worldClocks, WorldClocks.offsets, WorldClocks.localOffset)

                    delegate: WorldClockTile {
                        required property var modelData

                        label: modelData.label
                        time: modelData.offsetMin === null ? "—" : ClockLib.timeAt(root.now.getTime(), modelData.offsetMin)
                        offset: modelData.relative
                    }
                }

                DaylightBar {
                    Layout.fillWidth: true
                    riseText: Weather.data?.today.sunrise?.text ?? ""
                    setText: Weather.data?.today.sunset?.text ?? ""
                    sun: Astro.daylight(root.now.getTime(), Cal.startOfDay(root.now).getTime(), Weather.data?.today ?? null, Weather.data?.week[0] ?? null)
                }
            }
        }

        CaptionBox {
            Layout.fillWidth: true
            Layout.fillHeight: true
            tabs: [
                {
                    text: "Month",
                    accent: "teal"
                }
            ]
            currentTab: 0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.pad
                spacing: Theme.pad

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    InkText {
                        Layout.fillWidth: true
                        text: `${Qt.locale().standaloneMonthName(root.month)} ${root.year}`
                        font.pixelSize: 19
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    InkButton {
                        text: "Today"
                        enabled: !root.onCurrentMonth
                        onClicked: root.showToday()
                    }

                    InkButton {
                        accessibleName: "Previous month"
                        icon: ""
                        onClicked: root.shift(-1)
                    }

                    InkButton {
                        accessibleName: "Next month"
                        icon: ""
                        onClicked: root.shift(1)
                    }
                }

                MonthGrid {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    year: root.year
                    month: root.month
                    weekStart: root.weekStart
                    today: root.now
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            const dy = WheelLib.vertical(wheel.angleDelta);
            if (dy !== 0) {
                // Whole notches only: touchpads and hi-res wheels send many small deltas per notch.
                const r = WheelLib.accumulate(root.wheelRest, dy);
                root.wheelRest = r.rest;
                if (r.steps !== 0)
                    root.shift(-r.steps);
            } else
                wheel.accepted = false; // horizontal scroll switches sections
        }
    }
}
