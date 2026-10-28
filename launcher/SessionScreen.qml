pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.theme
import qs.components

// The session screen: the power actions as tiles, three to a row, chosen with the arrows, a letter, or the mouse.
// An action that ends the session (log out, restart, power off) asks again first: its tile turns coral and a strip
// under the grid offers Cancel and the action itself. Keys are handled on the screen, which holds the focus for as
// long as it is shown. What runs goes through Launcher.choose(), never Launcher.activate() (that is the app list's).
CaptionBox {
    id: root

    // The sizes the launcher's views share, made by the window.
    required property LauncherMetrics metrics
    readonly property int columns: 3
    readonly property real tileWidth: (metrics.boxWidth - 2 * root.metrics.pad - 2 * root.metrics.gap) / columns
    readonly property real tileHeight: metrics.px(84)
    // The room under the grid for the confirmation strip (and the ink line above it).
    readonly property real stripHeight: metrics.px(Theme.pillHeight + Theme.gap)
    // Power has six entries at most, so the grid is never taller than two rows.
    readonly property int maxRows: 2
    readonly property real tallestHeight: boxHeight(maxRows, true)
    readonly property var entries: Power.entries
    readonly property int rows: Math.ceil(entries.length / columns)
    readonly property bool asking: Launcher.confirming !== ""
    // The entry the strip is about.
    readonly property var askingEntry: entries.find(e => e.id === Launcher.confirming) ?? null
    // The shortcut letter of each action.
    readonly property var letters: ({
            lock: "L",
            logout: "O",
            suspend: "S",
            hibernate: "H",
            reboot: "R",
            poweroff: "P"
        })

    // The tile the keys act on.
    property int selected: 0

    // The height of the box with the given rows of tiles, with or without the strip.
    function boxHeight(tileRows: int, withStrip: bool): real {
        const grid = tileRows * tileHeight + Math.max(0, tileRows - 1) * root.metrics.gap;
        return headroom + 2 * Theme.inkWidth + 2 * root.metrics.pad + grid + (withStrip ? Theme.inkWidth + stripHeight : 0);
    }

    // Moves the selection; a wait on another tile ends with it.
    function select(index: int): void {
        if (index < 0 || index >= entries.length)
            return;
        selected = index;
        if (Launcher.confirming !== entries[index].id)
            Launcher.confirming = "";
    }

    function chooseAt(index: int): void {
        if (index < 0 || index >= entries.length)
            return;
        select(index);
        Launcher.choose(entries[index].id);
    }

    // Each time the window takes the screen it starts on the first tile.
    function focusScreen(): void {
        selected = 0;
        forceActiveFocus();
    }

    onEntriesChanged: selected = Math.max(0, Math.min(selected, entries.length - 1))

    tabs: [
        {
            text: "Session",
            accent: "coral"
        }
    ]
    currentTab: 0
    keyline: true
    width: implicitWidth
    height: implicitHeight

    Keys.onPressed: event => {
        const n = entries.length;
        const plain = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0;
        if (event.key === Qt.Key_Left) {
            select(selected - 1);
        } else if (event.key === Qt.Key_Right) {
            select(selected + 1);
        } else if (event.key === Qt.Key_Up) {
            select(selected - columns);
        } else if (event.key === Qt.Key_Down) {
            select(selected + columns);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            // A held Enter must not confirm Log out or Power off.
            if (!event.isAutoRepeat)
                chooseAt(selected);
        } else if (event.key === Qt.Key_Escape) {
            Launcher.cancel();
        } else if (plain && event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
            // The same for a held letter: only a fresh press chooses.
            if (!event.isAutoRepeat) {
                const letter = String.fromCharCode(event.key);
                const index = entries.findIndex(e => letters[e.id] === letter);
                if (index >= 0 && index < n)
                    chooseAt(index);
            }
        } else {
            return;
        }
        event.accepted = true;
    }

    Item {
        implicitWidth: root.metrics.boxWidth - 2 * Theme.inkWidth
        implicitHeight: column.implicitHeight

        Column {
            id: column

            width: parent.width

            Item {
                width: parent.width
                height: 2 * root.metrics.pad + root.rows * root.tileHeight + Math.max(0, root.rows - 1) * root.metrics.gap

                Grid {
                    x: (parent.width - width) / 2
                    y: root.metrics.pad
                    columns: root.columns
                    spacing: root.metrics.gap

                    Repeater {
                        model: root.entries

                        Rectangle {
                            id: tile

                            required property var modelData
                            required property int index
                            readonly property bool waiting: Launcher.confirming === modelData.id
                            readonly property bool isSelected: index === root.selected
                            readonly property bool lit: waiting || isSelected
                            readonly property string accent: waiting ? "coral" : Theme.roleAccent.active
                            readonly property color textColor: lit ? Theme.on[accent] : Theme.text

                            width: root.tileWidth
                            height: root.tileHeight
                            color: lit ? Theme.accent[accent] : Theme.paper
                            border.color: Theme.ink
                            border.width: 2

                            // A waiting tile is confirmed with Enter or the strip's button, not by a second click.
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: !tile.waiting
                                onClicked: root.chooseAt(tile.index)
                            }

                            InkIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: root.metrics.px(12)
                                icon: tile.modelData.icon
                                size: root.metrics.px(28)
                                color: tile.textColor
                            }

                            InkText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: root.metrics.px(10)
                                width: Math.min(implicitWidth, parent.width - 2 * root.metrics.gap)
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: tile.waiting ? `${tile.modelData.label}?` : tile.modelData.label
                                color: tile.textColor
                                font.bold: tile.waiting
                            }

                            // The shortcut letter, in a small tab on the corner.
                            Rectangle {
                                x: 0
                                y: 0
                                width: root.metrics.px(20)
                                height: root.metrics.px(20)
                                color: Theme.paper
                                border.color: Theme.ink
                                border.width: 2

                                InkText {
                                    anchors.centerIn: parent
                                    text: root.letters[tile.modelData.id] ?? ""
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }
                        }
                    }
                }
            }

            // The confirmation: the ink line, then what to press and the two buttons.
            Rectangle {
                visible: root.asking
                width: parent.width
                height: Theme.inkWidth
                color: Theme.ink
            }

            Item {
                visible: root.asking
                width: parent.width
                height: root.stripHeight

                InkText {
                    x: root.metrics.pad
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Enter confirms, Esc cancels"
                    opacity: 0.7
                }

                // Cancel, then the action itself in ink: the last thing on the strip is what runs.
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: root.metrics.pad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.metrics.gap

                    Repeater {
                        model: [
                            {
                                text: "Cancel",
                                go: false
                            },
                            {
                                text: root.askingEntry?.label ?? "",
                                go: true
                            }
                        ]

                        Rectangle {
                            id: choice

                            required property var modelData

                            width: label.implicitWidth + 2 * root.metrics.gap
                            height: root.metrics.px(28)
                            color: modelData.go ? (choiceArea.containsMouse ? Theme.accent.navy : Theme.ink) : (choiceArea.containsMouse ? Theme.accent[Theme.roleAccent.active] : Theme.paper)
                            border.color: Theme.ink
                            border.width: 2

                            InkText {
                                id: label

                                anchors.centerIn: parent
                                text: choice.modelData.text
                                color: choice.modelData.go ? (choiceArea.containsMouse ? Theme.on.navy : Theme.textOnInk) : (choiceArea.containsMouse ? Theme.on[Theme.roleAccent.active] : Theme.text)
                                font.bold: true
                            }

                            MouseArea {
                                id: choiceArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (choice.modelData.go)
                                        Launcher.choose(Launcher.confirming);
                                    else
                                        Launcher.confirming = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
