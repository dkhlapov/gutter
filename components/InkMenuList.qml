pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.theme

// The entries of one tray menu level; a submenu is another InkMenuList one level in. Used by InkMenu.
Column {
    id: list

    property QsMenuHandle handle: null // set by the caller; not required, so a submenu can be loaded by file name
    property int depth: 0
    property string accent: Theme.roleAccent.active

    // Sizes of the entry parts: the box round a check or radio mark and an entry's icon, the marks and glyphs in them.
    readonly property real boxSize: 16
    readonly property real boxBorder: 2
    readonly property real radioSize: 8
    readonly property real tickSize: 11
    readonly property real iconGlyphSize: 14
    readonly property real chevronSize: 12

    // An entry was triggered.
    signal dismissed

    QsMenuOpener {
        id: opener

        menu: list.handle
    }

    Repeater {
        model: opener.children

        Column {
            id: slot

            required property QsMenuEntry modelData
            property bool expanded: false

            width: list.width

            Rectangle {
                id: row

                readonly property bool lit: !slot.modelData.isSeparator && slot.modelData.enabled && area.containsMouse
                readonly property color textColor: lit ? Theme.on[list.accent] : Theme.text

                // Separators are no entries; a submenu entry expands, any other triggers.
                Accessible.role: slot.modelData.isSeparator ? Accessible.Separator : Accessible.MenuItem
                Accessible.name: slot.modelData.isSeparator ? "" : slot.modelData.text
                Accessible.checkable: slot.modelData.buttonType !== QsMenuButtonType.None
                Accessible.checked: slot.modelData.checkState === Qt.Checked
                Accessible.onPressAction: row.activate()

                width: parent.width
                height: slot.modelData.isSeparator ? Theme.inkWidth + Theme.gap : Theme.pillHeight - Theme.inkWidth
                color: lit ? Theme.accent[list.accent] : Theme.paper

                // The one way an entry is used, for a click and for a screen reader's press: a separator or a
                // disabled entry does nothing.
                function activate(): void {
                    if (slot.modelData.isSeparator || !slot.modelData.enabled)
                        return;
                    if (slot.modelData.hasChildren)
                        slot.expanded = !slot.expanded;
                    else {
                        slot.modelData.triggered();
                        list.dismissed();
                    }
                }

                Rectangle {
                    visible: slot.modelData.isSeparator
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.pad
                    width: parent.width - 2 * Theme.pad
                    height: Theme.inkWidth
                    color: Theme.ink
                }

                Row {
                    visible: !slot.modelData.isSeparator
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.pad + list.depth * Theme.pad
                    width: parent.width - x - Theme.pad
                    spacing: Theme.gap
                    opacity: slot.modelData.enabled ? 1 : 0.4

                    // Check box: a tick in a square; radio button: a smaller square in a square.
                    Rectangle {
                        visible: slot.modelData.buttonType !== QsMenuButtonType.None
                        anchors.verticalCenter: parent.verticalCenter
                        width: list.boxSize
                        height: list.boxSize
                        color: "transparent"
                        border.color: row.textColor
                        border.width: list.boxBorder

                        InkIcon {
                            anchors.centerIn: parent
                            visible: slot.modelData.buttonType === QsMenuButtonType.CheckBox && slot.modelData.checkState === Qt.Checked
                            icon: "\uf00c" // check
                            size: list.tickSize
                            color: row.textColor
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            visible: slot.modelData.buttonType === QsMenuButtonType.RadioButton && slot.modelData.checkState === Qt.Checked
                            width: list.radioSize
                            height: list.radioSize
                            color: row.textColor
                        }
                    }

                    Item {
                        visible: slot.modelData.icon !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: list.boxSize
                        height: list.boxSize

                        IconImage {
                            id: entryIcon

                            anchors.fill: parent
                            source: slot.modelData.icon
                            visible: status === Image.Ready
                        }

                        InkIcon {
                            anchors.centerIn: parent
                            visible: entryIcon.status === Image.Error
                            icon: "\u{f02d6}" // md-help, a question mark, for an icon that did not load
                            size: list.iconGlyphSize
                            color: row.textColor
                        }
                    }

                    InkText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - (slot.modelData.hasChildren ? chevron.width + parent.spacing : 0)
                        text: slot.modelData.text
                        color: row.textColor
                        elide: Text.ElideRight
                    }

                    InkIcon {
                        id: chevron

                        visible: slot.modelData.hasChildren
                        anchors.verticalCenter: parent.verticalCenter
                        icon: slot.expanded ? "\uf078" : "\uf054" // chevron down, chevron right
                        size: list.chevronSize
                        color: row.textColor
                    }
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    enabled: !slot.modelData.isSeparator && slot.modelData.enabled
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.activate()
                }
            }

            // Loaded by file name: a type may not instantiate itself in its own definition.
            Loader {
                width: parent.width
                // A Loader keeps the size of the item it last held, which left a gap under a collapsed entry.
                height: item ? (item as InkMenuList).implicitHeight : 0
                active: slot.expanded
                source: "InkMenuList.qml"
                onLoaded: {
                    const sub = item as InkMenuList;
                    sub.width = Qt.binding(() => slot.width);
                    sub.handle = Qt.binding(() => slot.modelData);
                    sub.depth = Qt.binding(() => list.depth + 1);
                    sub.accent = Qt.binding(() => list.accent);
                    sub.dismissed.connect(list.dismissed);
                }
            }
        }
    }
}
