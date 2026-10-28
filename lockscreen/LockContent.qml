import QtQuick
import qs.components
import qs.services
import qs.theme

// What the lock shows, one layout for every monitor's lock surface and for the dry-run preview: the wallpaper,
// dimmed by a halftone screen, with the clock and the password field centred over it. Its sizes (not the ink
// width or the shadow) grow with the monitor's height like the launcher's. The player sits left of the clock and
// the unread counts right of it, the status chips at the bottom centre; where the surface is narrower than
// 1100 px at ui 1 (its width divided by `ui`, so the test follows the sizes), the three stack under the field,
// as many as fit inside the frame.
Item {
    id: root

    required property var screenInfo
    // 1 up to 960 px of monitor height, then in proportion.
    property real ui: Math.max(1, (screenInfo?.height ?? 0) / 960)
    // The inset of the ink-line frame, and what stays clear inside it.
    readonly property real frame: Math.round(14 * ui)
    readonly property real clearance: Math.round(20 * ui)
    // Too narrow for the side pieces: they stack under the field.
    readonly property bool stacked: width / ui < 1100

    // The unlock fade.
    opacity: Lock.fade

    Rectangle {
        anchors.fill: parent
        color: Theme.paper
    }

    Image {
        anchors.fill: parent
        source: Wallpaper.path === "" ? "" : "file://" + encodeURI(Wallpaper.path).replace(/#/g, "%23").replace(/\?/g, "%3F")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: Qt.size((root.screenInfo?.width ?? 0) * (root.screenInfo?.devicePixelRatio ?? 1), (root.screenInfo?.height ?? 0) * (root.screenInfo?.devicePixelRatio ?? 1))
        visible: status === Image.Ready
    }

    // The dim: paper over the picture, and the dots over that.
    Rectangle {
        anchors.fill: parent
        color: Theme.paper
        opacity: 0.45
    }

    Halftone {
        opacity: 0.35
    }

    // The ink-line frame, inside the screen's edge.
    Rectangle {
        anchors.fill: parent
        anchors.margins: root.frame
        color: "transparent"
        border.color: Theme.ink
        border.width: Theme.inkWidth
    }

    // The clock and the field: centred (a little above the middle), never closer to the top than the frame and its
    // clearance, and in no way dependent on what the stacked layout holds, so a player or a count appearing moves neither.
    Column {
        id: column

        x: Math.round((root.width - width) / 2)
        y: Math.max(root.frame + root.clearance, Math.round((root.height - height) / 2 - root.height * 0.05))
        spacing: Math.round(24 * root.ui)

        ClockBlock {
            id: clock

            anchors.horizontalCenter: parent.horizontalCenter
            ui: root.ui
            maxSize: root.height / 6
        }

        PasswordField {
            id: field

            anchors.horizontalCenter: parent.horizontalCenter
            ui: root.ui
        }
    }

    // The stacked layout's pieces, under the field (the field's message bubble overlays the gap above them). What
    // does not fit above the frame's clearance is left out, the player first, then the counts, and the chips last
    // (the layout chip can matter for typing the password). The clock and the field always stay. A piece left out
    // stays in the tree, transparent and disabled, so its size is measured the same either way (a hidden one would
    // measure a little different, and what is shown could then depend on what was shown before).
    Item {
        id: stack

        readonly property real gap: Math.round(16 * root.ui)
        readonly property real room: root.height - root.frame - root.clearance - Theme.shadowOffset - y
        // Whether the player, the counts and the chips are shown, in that order: the pieces that are there, taken
        // chips first, then counts, then player, each kept if it still fits with those already kept.
        readonly property var kept: {
            const parts = [stackPlayer, stackCounts, stackStrip];
            const out = [false, false, false];
            let used = 0;
            for (let i = parts.length - 1; i >= 0; i--) {
                if (!parts[i].has)
                    continue;
                const next = used + parts[i].implicitHeight + (used > 0 ? gap : 0);
                if (next > room)
                    continue;
                used = next;
                out[i] = true;
            }
            return out;
        }
        // Where each piece's top is, from the top of the stack: the kept ones one under the other, in order.
        readonly property var tops: {
            const parts = [stackPlayer, stackCounts, stackStrip];
            const out = [0, 0, 0];
            let at = 0;
            for (let i = 0; i < parts.length; i++) {
                out[i] = at;
                if (kept[i])
                    at += parts[i].implicitHeight + gap;
            }
            return out;
        }

        width: root.width
        y: column.y + field.y + field.height + Math.round(58 * root.ui)
        visible: root.stacked

        PlayerCard {
            id: stackPlayer

            anchors.horizontalCenter: parent.horizontalCenter
            y: stack.tops[0]
            ui: root.ui
            opacity: stack.kept[0] ? 1 : 0
            enabled: stack.kept[0]
        }

        NotifCounts {
            id: stackCounts

            anchors.horizontalCenter: parent.horizontalCenter
            y: stack.tops[1]
            ui: root.ui
            opacity: stack.kept[1] ? 1 : 0
            enabled: stack.kept[1]
            maxWidth: Math.round(Math.min(root.width - 2 * (root.frame + root.clearance), 320 * root.ui))
        }

        StatusStrip {
            id: stackStrip

            anchors.horizontalCenter: parent.horizontalCenter
            y: stack.tops[2]
            ui: root.ui
            opacity: stack.kept[2] ? 1 : 0
            enabled: stack.kept[2]
        }
    }

    // The wide layout's pieces: the player left of the clock and the counts right of it, both level with it, and
    // the chips at the bottom centre. Kept inside the frame.
    PlayerCard {
        id: sidePlayer

        readonly property real gap: Math.round(48 * root.ui)

        ui: root.ui
        shown: !root.stacked
        x: Math.max(root.frame + root.clearance, column.x + clock.x - gap - width)
        y: column.y + clock.y + Math.round((clock.height - height) / 2)
    }

    NotifCounts {
        id: sideCounts

        readonly property real gap: Math.round(48 * root.ui)

        ui: root.ui
        shown: !root.stacked
        x: Math.min(root.width - root.frame - root.clearance - width, column.x + clock.x + clock.width + gap)
        y: Math.max(root.frame + root.clearance, column.y + clock.y + Math.round((clock.height - height) / 2))
    }

    StatusStrip {
        id: sideStrip

        ui: root.ui
        // Left out where a short monitor would put it on the field.
        shown: !root.stacked && y >= column.y + column.height + Math.round(16 * root.ui)
        x: Math.round((root.width - width) / 2)
        y: root.height - root.frame - root.clearance - height - Theme.shadowOffset
    }

    // Over the layout, under the field (its tail points at the field), so a message never moves the clock or the field.
    StateBubble {
        ui: root.ui
        x: column.x + field.x + Math.round((field.width - width) / 2)
        y: column.y + field.y + field.height + Theme.shadowOffset
    }
}
