import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services
import qs.theme
import "../../../lib/appnames.js" as Names
import "../../../lib/glyphs.js" as Glyphs
import "../../../lib/notifications.js" as NotifLib

// One row of the history: the icon plate, "APP · 3 min" with the repeat count and a dismiss ×, the summary, the
// body in four lines, and for a notification the app can still reach its buttons and reply field. Clicking the
// text or the icon does what clicking the bubble does (the default action of a live notification, else the app's
// window while one is open), and closes the panel; a click that reaches nothing does nothing here (on the bubble,
// the click takes the bubble down instead).
// The row only knows its record's id (`rid`, from the list's model) and looks the record up again whenever the
// history changes; for a moment after a dismissal the record can already be gone, so every read is null-safe, and
// every click takes its id and identifier by value.
Item {
    id: root

    required property int rid
    // The time the age is counted to; the section moves it on.
    property real now: 0
    readonly property var rec: Notifications.recordFor(rid)
    readonly property var source: rec ? NotifLib.iconSource(rec) : ({ file: "", name: "" })
    readonly property string themed: source.name !== "" ? Quickshell.iconPath(source.name, true) : ""
    readonly property string image: source.file !== "" ? source.file : themed
    readonly property bool critical: (rec?.urgency ?? 1) === 2
    readonly property int count: rec?.count ?? 1
    readonly property string summary: rec?.summary ?? ""
    readonly property string body: rec?.body ?? ""
    readonly property string app: Names.displayName(rec?.appName ?? "").toUpperCase()
    readonly property string age: typeof rec?.at === "number" ? NotifLib.ago(rec.at, now) : ""
    readonly property bool live: rec?.live === true
    // Whether a click reaches anything: a live notification with a default action, or an app with a window open
    // (false for a record that is gone).
    readonly property bool clickable: Notifications.canActivate(rid)
    readonly property bool canReply: live && rec?.canReply === true
    // The first six actions, each with the record it belongs to (see NotificationPill).
    readonly property var buttons: {
        const id = rid;
        const actions = live && Array.isArray(rec?.actions) ? rec.actions : [];
        return actions.filter(a => typeof a?.identifier === "string").slice(0, 6).map(a => ({
                    id,
                    identifier: a.identifier,
                    text: label(a.text || a.identifier)
                }));
    }

    // An app can send any text for a button; a long one would push the others off the row.
    function label(s: var): string {
        const chars = Array.from(typeof s === "string" ? s : "");
        return chars.length > 24 ? chars.slice(0, 23).join("") + "…" : chars.join("");
    }

    function send(): void {
        const text = field.text.trim();
        if (text === "" || !canReply)
            return;
        const id = rid;
        field.text = "";
        Notifications.reply(id, text);
    }

    // The reply field takes the keyboard when the bubble's Reply button asked for this row, once.
    function takeFocus(): void {
        if (rid === 0 || Notifications.replyTarget !== rid || !canReply)
            return;
        field.forceActiveFocus();
        Notifications.replyTarget = 0;
    }

    onCanReplyChanged: takeFocus()
    // The row is not in the window yet when it completes, and a field focused then does not keep it.
    Component.onCompleted: Qt.callLater(takeFocus)

    Connections {
        target: Notifications

        function onReplyTargetChanged(): void {
            root.takeFocus();
        }
    }

    implicitHeight: content.implicitHeight + 2 * Theme.gap + 1
    height: implicitHeight
    // A row whose record is already gone shows nothing and takes no clicks while it waits to be removed.
    visible: rec !== null
    enabled: rec !== null

    Rectangle {
        anchors.fill: parent
        color: Theme.accent.sun
        opacity: area.containsMouse && root.clickable ? 0.2 : 0
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            // A click that reaches nothing (no live default action and no open window of the app) leaves the panel
            // open.
            const id = root.rid;
            if (Notifications.activate(id))
                PillControl.close();
        }
    }

    // The line under the row.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.ink
        opacity: 0.25
    }

    RowLayout {
        id: content

        x: Theme.gap
        y: Theme.gap
        width: parent.width - 2 * Theme.gap
        spacing: Theme.pad

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

                // The app's name gives way to the age: a long one is cut short, the age stays whole.
                InkText {

                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    Layout.maximumWidth: Math.min(Math.ceil(implicitWidth), 360)
                    // Takes back the row's gap when the age follows as one string, " · 3 min".
                    Layout.rightMargin: root.age !== "" ? -Theme.gap : 0
                    visible: text !== ""
                    text: root.app
                    font.bold: true
                    font.letterSpacing: 1
                    elide: Text.ElideRight
                    color: Theme.textMuted
                }

                InkText {

                    textFormat: Text.PlainText
                    visible: text !== ""
                    text: root.age === "" || root.app === "" ? root.age : ` · ${root.age}`
                    font.bold: true
                    font.letterSpacing: 1
                    color: Theme.textMuted
                }

                // A repeat of the same notification.
                Rectangle {
                    visible: root.count > 1
                    implicitWidth: tag.implicitWidth + Theme.gap
                    implicitHeight: tag.implicitHeight
                    color: Theme.accent.sun
                    border.color: Theme.ink
                    // 2 px: a lighter line than the box outline, like the other small outlines.
                    border.width: 2

                    InkText {

                        textFormat: Text.PlainText
                        id: tag

                        anchors.centerIn: parent
                        text: `×${root.count}`
                        color: Theme.on.sun
                        font.bold: true
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // The dismiss button: a glyph with a hit area as tall as a button.
                Item {
                    objectName: "dismissButton"
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    Accessible.role: Accessible.Button
                    Accessible.name: "Dismiss notification"
                    Accessible.onPressAction: Notifications.dismiss(root.rid)

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
                        onClicked: {
                            const id = root.rid;
                            Notifications.dismiss(id);
                        }
                    }
                }
            }

            InkText {

                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: text !== ""
                text: root.summary
                font.bold: true
                elide: Text.ElideRight
            }

            InkText {

                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: text !== ""
                text: root.body
                // Anywhere, not only at a space: a body that is one long word still stops at the edge.
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 4
                elide: Text.ElideRight
                color: Theme.textMuted
            }

            // The buttons and the reply field sit on an area of their own that takes clicks and does nothing, so a
            // near miss between two of them does not count as a click on the row.
            Item {
                Layout.fillWidth: true
                Layout.topMargin: Theme.gap
                Layout.bottomMargin: Theme.shadowOffset
                visible: root.buttons.length > 0 || root.canReply
                implicitHeight: controls.implicitHeight

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                }

                ColumnLayout {
                    id: controls

                    width: parent.width
                    spacing: Theme.gap

                    Flow {
                        Layout.fillWidth: true
                        visible: root.buttons.length > 0
                        spacing: Theme.gap

                        Repeater {
                            model: root.buttons

                            InkButton {
                                required property var modelData

                                text: modelData.text
                                onClicked: Notifications.invoke(modelData.id, modelData.identifier)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.canReply
                        spacing: Theme.gap

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.pillHeight
                            color: Theme.paper
                            border.color: Theme.ink
                            border.width: Theme.inkWidth

                            TextInput {
                                id: field

                                Accessible.role: Accessible.EditableText
                                Accessible.name: root.rec?.replyPlaceholder || "Reply"
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.pad
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.pad
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                maximumLength: 2000
                                color: Theme.text
                                selectionColor: Theme.accent.sun
                                selectedTextColor: Theme.on.sun
                                font.family: Theme.font
                                font.pixelSize: Theme.textMin
                                // The text goes to the app as it is; nothing here builds a command from it.
                                Keys.onReturnPressed: root.send()
                                Keys.onEnterPressed: root.send()
                            }

                            InkText {

                                textFormat: Text.PlainText
                                anchors.left: field.left
                                anchors.right: field.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: field.text === ""
                                text: root.rec?.replyPlaceholder || "Reply…"
                                elide: Text.ElideRight
                                color: Theme.textMuted
                            }

                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                cursorShape: Qt.IBeamCursor
                                onClicked: field.forceActiveFocus()
                            }
                        }

                        InkButton {
                            // Room on the right for the button's hard shadow.
                            Layout.rightMargin: Theme.shadowOffset
                            enabled: field.text.trim() !== ""
                            icon: Glyphs.glyph("send")
                            text: "Send"
                            accent: "teal"
                            onClicked: root.send()
                        }
                    }
                }
            }
        }
    }
}
