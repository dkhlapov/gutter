pragma ComponentBehavior: Bound

import QtQuick
import qs.settings
import qs.services
import qs.theme
import qs.components

// The launcher's box: a search row over the ranked rows. Typing narrows the rows; `/` switches them to the shell's
// own commands. Keys are handled on the input, which holds the focus for as long as the box is shown.
CaptionBox {
    id: root

    // The sizes the launcher's views share, made by the window.
    required property LauncherMetrics metrics
    readonly property real searchHeight: metrics.px(Theme.pillHeight + Theme.gap)
    readonly property int maxRows: Settings.launcher.maxRows
    // The box with the most rows it will ever show, so the window can be that size and the rows grow into it.
    readonly property real tallestHeight: headroom + 2 * Theme.inkWidth + searchHeight + Theme.inkWidth + maxRows * metrics.rowHeight
    readonly property bool showEmpty: Launcher.results.length === 0 && Launcher.query !== ""

    function focusInput(): void {
        input.forceActiveFocus();
    }

    tabs: [
        {
            text: "Launch",
            accent: Theme.roleAccent.active
        }
    ]
    currentTab: 0
    keyline: true
    width: implicitWidth
    height: implicitHeight

    Item {
        implicitWidth: root.metrics.boxWidth - 2 * Theme.inkWidth
        implicitHeight: column.implicitHeight

        Column {
            id: column

            width: parent.width

            Item {
                width: parent.width
                height: root.searchHeight

                InkIcon {
                    id: magnifier

                    x: root.metrics.pad
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "\u{f0349}" // md-magnify
                    size: root.metrics.px(18)
                }

                // The "cmd" tag on the right says the rows are commands.
                Rectangle {
                    id: tag

                    visible: Launcher.parsed.mode === "command"
                    anchors.right: parent.right
                    anchors.rightMargin: root.metrics.pad
                    anchors.verticalCenter: parent.verticalCenter
                    width: tagText.implicitWidth + 2 * root.metrics.gap
                    height: root.metrics.px(20)
                    color: Theme.accent[Theme.roleAccent.active]
                    border.color: Theme.ink
                    border.width: 2

                    InkText {
                        id: tagText

                        anchors.centerIn: parent
                        text: "cmd"
                        color: Theme.on[Theme.roleAccent.active]
                        font.bold: true
                    }
                }

                TextInput {
                    id: input

                    x: magnifier.x + magnifier.width + root.metrics.gap
                    anchors.verticalCenter: parent.verticalCenter
                    width: (tag.visible ? tag.x - root.metrics.gap : parent.width - root.metrics.pad) - x
                    clip: true
                    focus: true
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: Theme.text
                    selectionColor: Theme.accent[Theme.roleAccent.active]
                    selectedTextColor: Theme.on[Theme.roleAccent.active]
                    selectByMouse: true
                    // Two ways: typing sets the query; a query set from outside (Tab, Ctrl+U, IPC) lands here.
                    text: Launcher.query
                    onTextEdited: Launcher.setQuery(text)

                    Keys.onPressed: event => {
                        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                        if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P))) {
                            Launcher.move(-1);
                        } else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N))) {
                            Launcher.move(1);
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            // A held Enter must not confirm Log out or Power off.
                            if (!event.isAutoRepeat)
                                Launcher.activate();
                        } else if (event.key === Qt.Key_Tab) {
                            Launcher.complete();
                            input.cursorPosition = input.length;
                        } else if (event.key === Qt.Key_Escape) {
                            Launcher.cancel();
                        } else if (ctrl && event.key === Qt.Key_U) {
                            Launcher.setQuery("");
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }

                    InkText {
                        visible: input.text.length === 0 && input.preeditText.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        text: "Search apps, or type / for commands"
                        color: Theme.textMuted
                        elide: Text.ElideRight
                    }
                }
            }

            // The ink line under the search row, while there is something under it.
            Rectangle {
                visible: list.count > 0 || root.showEmpty
                width: parent.width
                height: Theme.inkWidth
                color: Theme.ink
            }

            Item {
                width: parent.width
                height: list.height

                ListView {
                    id: list

                    width: parent.width - scroll.reserve
                    height: Math.min(count, root.maxRows) * root.metrics.rowHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: Launcher.results

                    Behavior on height {
                        Anim {}
                    }

                    Connections {
                        target: Launcher

                        function onSelectedChanged(): void {
                            list.positionViewAtIndex(Launcher.selected, ListView.Contain);
                        }
                    }

                    delegate: ResultRow {
                        required property var modelData
                        required property int index

                        width: list.width
                        height: root.metrics.rowHeight
                        metrics: root.metrics
                        row: modelData
                        selected: index === Launcher.selected
                        onHovered: Launcher.selected = index
                        onClicked: {
                            Launcher.selected = index;
                            Launcher.activate();
                        }
                    }
                }

                InkScrollBar {
                    id: scroll

                    anchors.top: list.top
                    anchors.bottom: list.bottom
                    anchors.left: list.right
                    anchors.leftMargin: gap
                    // The list's final height, not its easing one.
                    viewLength: Math.min(list.count, root.maxRows) * root.metrics.rowHeight
                    target: list
                }
            }

            Item {
                visible: root.showEmpty
                width: parent.width
                height: root.metrics.px(96)

                EmptyState {
                    anchors.centerIn: parent
                    icon: "\u{f0349}" // md-magnify
                    text: "No match"
                }
            }
        }
    }
}
