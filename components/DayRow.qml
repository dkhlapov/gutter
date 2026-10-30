import QtQuick
import QtQuick.Layouts
import qs.theme
import "../lib/weather.js" as WeatherLib
import "../lib/glyphs.js" as Glyphs

// Day name and date, icon, rain chance, low, range bar on the week's scale, high.
RowLayout {
    id: root

    required property var day
    property real lo
    property real hi
    readonly property date noon: new Date(`${day.date}T12:00`)
    readonly property var range: WeatherLib.rangeFractions(day.min, day.max, lo, hi)

    spacing: 6

    // fillWidth children would make this column fill too and squeeze the range bar.
    ColumnLayout {
        Layout.preferredWidth: 44
        Layout.fillWidth: false
        spacing: -2

        InkText {
            Layout.fillWidth: true
            text: Qt.locale().dayName(root.noon.getDay(), Locale.ShortFormat)
            font.pixelSize: Theme.textMin
            font.bold: true
        }

        InkText {
            Layout.fillWidth: true
            text: Qt.formatDate(root.noon, "d MMM")
            color: Theme.textMuted
        }
    }

    InkIcon {
        Layout.preferredWidth: 24
        horizontalAlignment: Text.AlignHCenter
        icon: Glyphs.glyph(WeatherLib.icon(root.day.code, true))
        size: 20
    }

    Row {
        Layout.preferredWidth: 44
        spacing: 2

        InkIcon {
            anchors.verticalCenter: parent.verticalCenter
            icon: ""
            size: 12
            opacity: root.day.pop >= 30 ? 1 : 0.5
        }

        InkText {
            anchors.verticalCenter: parent.verticalCenter
            text: `${root.day.pop}%`
            font.bold: root.day.pop >= 30
            color: root.day.pop >= 30 ? Theme.text : Theme.textMuted
        }
    }

    InkText {
        Layout.preferredWidth: 28
        horizontalAlignment: Text.AlignRight
        text: `${Math.round(root.day.min)}°`
        color: Theme.textMuted
    }

    Rectangle {
        id: track

        Layout.fillWidth: true
        implicitHeight: 12
        color: Theme.paper
        border.color: Theme.ink
        border.width: Theme.inkWidth

        Rectangle {
            x: root.range.from * (track.width - 2 * Theme.inkWidth) + Theme.inkWidth
            y: Theme.inkWidth
            width: Math.max(2, (root.range.to - root.range.from) * (track.width - 2 * Theme.inkWidth))
            height: parent.height - 2 * Theme.inkWidth
            color: WeatherLib.isRainy(root.day.code) ? Theme.accent.teal : Theme.accent.sun
        }
    }

    InkText {
        Layout.preferredWidth: 32
        horizontalAlignment: Text.AlignRight
        text: `${Math.round(root.day.max)}°`
        font.pixelSize: Theme.textMin
        font.bold: true
    }
}
