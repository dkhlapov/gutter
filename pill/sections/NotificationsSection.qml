pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components
import "notifications"
import "../../lib/glyphs.js" as Glyphs
import "../../lib/notifications.js" as NotifLib

// The notification history, newest first: one row per record with its buttons and reply field while the app can
// still be reached. Opening the section marks everything read. The list shows a ListModel of ids that is kept in
// step with the history (NotifLib.syncOps), so a new, dismissed or updated record does not rebuild the rows that
// stay: a reply being typed, the focus and the scroll position survive.
Item {
    id: root

    // The time the rows' ages are counted to.
    property real now: Date.now()
    // The ids that were new when the section opened (and have arrived since), for the header: they are marked read at
    // once, and one that is dismissed leaves the count.
    property var freshIds: []
    readonly property int fresh: freshIds.length
    readonly property int total: Notifications.history?.length ?? 0

    // A function, not a property, so each call is ordered with the handlers that follow the history's changes.
    function records(): var {
        return Array.isArray(Notifications.history) ? Notifications.history : [];
    }

    function sync(): void {
        const history = records();
        const have = [];
        for (let i = 0; i < rows.count; i++)
            have.push(rows.get(i).rid);
        for (const op of NotifLib.syncOps(have, history.filter(h => typeof h?.id === "number").map(h => h.id))) {
            if (op.op === "remove")
                rows.remove(op.at);
            else if (op.op === "insert")
                rows.insert(op.at, { rid: op.id });
            else
                rows.move(op.from, op.to, 1);
        }
    }

    // Marks only when something is unread: marking replaces the history, which must not trigger marking again.
    function acknowledge(): void {
        if (visible && Notifications.unread > 0)
            Notifications.markAllRead();
    }

    Component.onCompleted: {
        sync();
        freshIds = NotifLib.newIds([], records());
        acknowledge();
        // A reply request nothing in the list took (its record is gone) does not wait for a later opening.
        settle.start();
    }
    Component.onDestruction: Notifications.replyTarget = 0
    onVisibleChanged: acknowledge()

    Connections {
        target: Notifications

        function onHistoryChanged(): void {
            root.sync();
            root.freshIds = NotifLib.newIds(root.freshIds, root.records());
        }

        // Marks what arrived while the section is open (the header counts it from the history).
        function onUnreadChanged(): void {
            // Later: marking replaces the history, which would re-evaluate unread while it is still announcing a change.
            Qt.callLater(root.acknowledge);
        }
    }

    Timer {
        running: root.visible
        interval: 30000
        repeat: true
        onTriggered: root.now = Date.now()
    }

    Timer {
        id: settle

        interval: 400
        onTriggered: Notifications.replyTarget = 0
    }

    ListModel {
        id: rows
    }

    CaptionBox {
        anchors.fill: parent
        tabs: [
            {
                text: "History",
                accent: "sun"
            }
        ]
        currentTab: 0

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: Theme.pad

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap

                InkText {
                    Layout.fillWidth: true
                    text: root.total === 0 ? "" : `${root.total} ${root.total === 1 ? "notification" : "notifications"}${root.fresh > 0 ? ` · ${root.fresh} new` : ""}`
                    elide: Text.ElideRight
                }

                InkButton {
                    icon: Glyphs.glyph("do_not_disturb")
                    text: "Do not disturb"
                    checked: Notifications.dnd
                    onClicked: Notifications.toggleDnd()
                }

                InkButton {
                    // Room on the right for the button's hard shadow.
                    Layout.rightMargin: Theme.shadowOffset
                    enabled: root.total > 0
                    icon: Glyphs.glyph("delete_sweep")
                    text: "Clear all"
                    onClicked: Notifications.clear()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: !Notifications.owned
                implicitHeight: Theme.pillHeight
                color: Theme.accent.coral
                border.color: Theme.ink
                border.width: Theme.inkWidth

                InkText {
                    anchors.centerIn: parent
                    text: "Another daemon holds notifications"
                    color: Theme.on.coral
                    font.bold: true
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list

                    anchors.fill: parent
                    anchors.rightMargin: scroll.reserve
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 400
                    // No current row: a view hands the keyboard focus to its current item, which would take it from a reply field.
                    currentIndex: -1
                    // Up and Down in a reply field would otherwise reach the view and move that current row.
                    keyNavigationEnabled: false
                    model: rows

                    delegate: NotificationCard {
                        width: list.width
                        now: root.now
                    }
                }

                InkScrollBar {
                    id: scroll

                    anchors.top: list.top
                    anchors.bottom: list.bottom
                    anchors.left: list.right
                    anchors.leftMargin: gap
                    target: list
                }

                EmptyState {
                    anchors.centerIn: parent
                    visible: root.total === 0
                    icon: Glyphs.glyph("notifications")
                    text: "Nothing new"
                }
            }
        }
    }
}
