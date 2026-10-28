pragma ComponentBehavior: Bound

import QtQuick
import qs.theme
import qs.services
import qs.components
import "../lib/power.js" as PowerLib

// The power menu: a caption box of actions, 300 px wide so a confirming row fits. An action that ends the session (log out, restart, power off) asks
// again first: its row turns coral with Cancel and a button that names the action; Escape steps back out of that
// before it closes the menu. Takes the keyboard focus while it exists, like InkMenu.
CaptionBox {
    id: root

    // The action waiting for its confirmation, "" for none.
    property string confirming: ""
    property Item previousFocus: null

    // An action ran, or Escape closed the menu.
    signal dismissed

    tabs: [
        {
            text: "Power",
            accent: "coral"
        }
    ]
    currentTab: 0
    keyline: true
    width: implicitWidth
    height: implicitHeight

    function choose(entry: var): void {
        const result = PowerLib.choose(entry, confirming);
        confirming = result.confirming;
        if (!result.run)
            return;
        dismissed();
        Power.run(entry.id);
    }

    Keys.onEscapePressed: event => {
        if (confirming !== "")
            confirming = "";
        else
            dismissed();
        event.accepted = true;
    }

    Component.onCompleted: {
        previousFocus = Window.window?.activeFocusItem ?? null;
        forceActiveFocus();
    }
    Component.onDestruction: previousFocus?.forceActiveFocus()

    Item {
        implicitWidth: 300
        implicitHeight: list.implicitHeight

        Column {
            id: list

            width: 300

            Repeater {
                model: Power.entries

                Rectangle {
                    id: row

                    required property var modelData
                    readonly property bool asking: root.confirming === modelData.id
                    readonly property bool lit: asking || area.containsMouse
                    readonly property string accent: asking ? "coral" : Theme.roleAccent.active
                    readonly property color textColor: lit ? Theme.on[accent] : Theme.text

                    width: parent.width
                    height: Theme.pillHeight - Theme.inkWidth
                    color: lit ? Theme.accent[accent] : Theme.paper

                    MouseArea {
                        id: area

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !row.asking
                        onClicked: root.choose(row.modelData)
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.pad
                        spacing: Theme.gap

                        InkIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: row.modelData.icon
                            color: row.textColor
                        }

                        InkText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.asking ? `${row.modelData.label}?` : row.modelData.label
                            color: row.textColor
                            font.bold: row.asking
                        }
                    }

                    // Cancel, then the action itself in ink: the last thing on the row is what runs.
                    Row {
                        visible: row.asking
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.gap
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.gap

                        Repeater {
                            model: [
                                {
                                    text: "Cancel",
                                    go: false
                                },
                                {
                                    text: row.modelData.label,
                                    go: true
                                }
                            ]

                            Rectangle {
                                id: choice

                                required property var modelData

                                width: label.implicitWidth + 2 * Theme.gap
                                height: row.height - 2 * Theme.inkWidth
                                color: modelData.go ? (choiceArea.containsMouse ? Theme.accent.navy : Theme.ink) : (choiceArea.containsMouse ? Theme.accent[Theme.roleAccent.active] : Theme.paper)
                                border.color: Theme.ink
                                border.width: 2

                                InkText {
                                    id: label

                                    anchors.centerIn: parent
                                    text: choice.modelData.text
                                    color: choice.modelData.go ? (choiceArea.containsMouse ? Theme.on.navy : Theme.textOnInk) : Theme.text
                                    font.bold: true
                                }

                                MouseArea {
                                    id: choiceArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (choice.modelData.go)
                                            root.choose(row.modelData);
                                        else
                                            root.confirming = "";
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
