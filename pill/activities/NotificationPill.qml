import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services
import qs.theme
import "../../lib/appnames.js" as Names
import "../../lib/glyphs.js" as Glyphs
import "../../lib/notifications.js" as NotifLib

// "notification", always a speech bubble: the app's icon, the app name on top (with how many more wait), a
// close button at the top right that dismisses, then the summary, the body in three lines and the app's buttons.
// A click anywhere on the bubble but its button row and the × runs the app's default action, else focuses the app's
// window when one is open (when neither is possible the click takes the bubble down); Bubble holds that area, so the
// padding ring and the tail take the click too. Critical ones are coral.
Item {
    id: root

    // The record that was on screen last. The bubble folds away after the service has dropped the record
    // (`current` is null by then), and it keeps showing this one while it does.
    property var held: null
    readonly property var n: Notifications.current
    readonly property var rec: n ?? held
    readonly property int recId: rec?.id ?? 0
    readonly property var source: rec ? NotifLib.iconSource(rec) : ({ file: "", name: "" })
    readonly property string themed: source.name !== "" ? Quickshell.iconPath(source.name, true) : ""
    readonly property string image: source.file !== "" ? source.file : themed
    readonly property bool critical: (rec?.urgency ?? 1) === 2
    readonly property string title: rec?.summary || rec?.body || ""
    readonly property string detail: rec?.summary ? (rec?.body ?? "") : ""
    readonly property int waiting: Math.max(0, (Notifications.queue?.length ?? 0) - 1)
    // The first three actions, each with the record it belongs to: the buttons keep their own id and identifier
    // by value, so a click after `current` moved on still reaches the notification it was drawn for.
    readonly property var buttons: {
        const id = recId;
        const actions = Array.isArray(rec?.actions) ? rec.actions : [];
        return actions.filter(a => typeof a?.identifier === "string").slice(0, 3).map(a => ({
                    id,
                    identifier: a.identifier,
                    text: label(a.text || a.identifier)
                }));
    }
    readonly property bool canReply: rec?.canReply === true && rec?.live === true

    // An app can send any text for a button; a long one would make the bubble wider than the screen.
    function label(s: var): string {
        const chars = Array.from(typeof s === "string" ? s : "");
        return chars.length > 14 ? chars.slice(0, 13).join("") + "…" : chars.join("");
    }

    onNChanged: {
        if (n)
            held = n;
    }
    Component.onCompleted: {
        if (n)
            held = n;
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    // While the bubble folds away after its record is gone it still shows that record, but nothing on it acts.
    enabled: n !== null

    RowLayout {
        id: row

        anchors.fill: parent
        spacing: Theme.gap

        IconPlate {
            Layout.alignment: Qt.AlignTop
            size: 32
            accent: root.critical ? "coral" : "teal"
            icon: Glyphs.glyph(root.critical ? "priority_high" : "notifications")
            source: root.image
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.gap

                BubbleHeadline {
                    textFormat: Text.PlainText
                    Layout.maximumWidth: 240
                    text: Names.displayName(root.rec?.appName ?? "").toUpperCase()
                    elide: Text.ElideRight
                }

                // How many more are waiting behind this one.
                Rectangle {
                    visible: root.waiting > 0
                    implicitWidth: tag.implicitWidth + Theme.gap
                    implicitHeight: tag.implicitHeight
                    color: Theme.accent.sun
                    border.color: Theme.ink
                    // 2 px: a lighter line than the box outline, like the other small outlines.
                    border.width: 2

                    InkText {
                        id: tag

                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: `+${root.waiting}`
                        color: Theme.on.sun
                        font.bold: true
                        font.pixelSize: 12
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // The dismiss button: a glyph with a hit area as tall as a button.
                Item {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24

                    InkIcon {
                        anchors.centerIn: parent
                        icon: Glyphs.glyph("close")
                        size: 16
                        opacity: dismiss.containsMouse ? 1 : 0.7
                    }

                    MouseArea {
                        id: dismiss

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifications.dismissBubble()
                    }
                }
            }

            InkText {
                textFormat: Text.PlainText
                Layout.maximumWidth: 320
                visible: text !== ""
                text: root.title
                font.bold: true
                elide: Text.ElideRight
            }

            InkText {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.maximumWidth: 320
                visible: text !== ""
                text: root.detail
                font.pixelSize: 12
                // Anywhere, not only at a space: a body that is one long word still stops at the edge.
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 3
                elide: Text.ElideRight
                opacity: 0.7
            }

            // The buttons sit on an area of their own that takes clicks and does nothing, so a near miss between
            // two of them does not count as a click on the bubble.
            Item {
                Layout.fillWidth: true
                Layout.maximumWidth: 320
                Layout.topMargin: Theme.gap
                visible: root.buttons.length > 0 || root.canReply
                // The width of all the buttons in one row. Not the Flow's own implicit width: it is bound to this
                // item's width, which then starts at nothing, and the Flow settles at one button per row.
                implicitWidth: {
                    let w = 0;
                    let count = 0;
                    for (const c of buttonFlow.children) {
                        // Not `c.visible`: that is false for all of them while the bubble is still folded away.
                        if ((c !== replyButton || root.canReply) && c.implicitWidth > 0) {
                            w += c.implicitWidth;
                            count++;
                        }
                    }
                    return w + Math.max(0, count - 1) * buttonFlow.spacing;
                }
                implicitHeight: buttonFlow.implicitHeight

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                }

                Flow {
                    id: buttonFlow

                    width: parent.width
                    spacing: Theme.gap

                    Repeater {
                        model: root.buttons

                        InkButton {
                            required property var modelData

                            text: modelData.text
                            onClicked: Notifications.invoke(modelData.id, modelData.identifier)
                        }
                    }

                    InkButton {
                        id: replyButton

                        visible: root.canReply
                        icon: Glyphs.glyph("reply")
                        text: "Reply"
                        accent: "teal"
                        onClicked: Notifications.openReply(root.recId)
                    }
                }
            }
        }
    }
}
