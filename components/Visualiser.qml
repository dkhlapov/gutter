pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.services

// Audio bars, one ink-outlined rect per cava value. Holds a reference on the cava service: only instantiate
// it (via Loader) while shown. `count` draws fewer bars, each taking the value at an even step through the
// service's bars (the pill's small gauge); `barSpacing` can be narrowed for it.
Item {
    id: root

    property color color: Theme.accent.pink
    property int count: Media.cava.bars
    property real barSpacing: 4
    readonly property real barWidth: Math.max(1, (width - (count - 1) * barSpacing) / count)

    ServiceRef {
        service: Media.cava
    }

    Repeater {
        model: root.count

        delegate: Rectangle {
            id: bar

            required property int index
            readonly property real level: Math.max(0, Math.min(1, Media.cava.values[Math.floor(index * Media.cava.bars / root.count)] ?? 0))

            x: index * (root.barWidth + root.barSpacing)
            width: root.barWidth
            // Never shorter than its own outline, so a silent bar is still a bar.
            height: Math.max(2 * Theme.inkWidth, level * root.height)
            y: root.height - height
            color: root.color
            border.color: Theme.ink
            border.width: Theme.inkWidth
        }
    }
}
