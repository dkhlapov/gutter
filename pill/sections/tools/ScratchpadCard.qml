pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.components

// Note tabs (first line as the label) and a plain-text editor; saved as you type.
CaptionBox {
    id: root

    tabs: [
        {
            text: "Scratchpad",
            accent: "pink"
        }
    ]
    currentTab: 0

    // A note's tab label, cut short so eight notes fit on one line.
    function label(index: int): string {
        const t = Scratchpad.title(index);
        return t.length > 12 ? t.slice(0, 11) + "…" : t;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.pad

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.gap

            ListView {
                id: tabs

                Layout.fillWidth: true
                Layout.preferredHeight: Theme.pillHeight + Theme.shadowOffset
                orientation: ListView.Horizontal
                spacing: Theme.gap
                clip: true
                // The pressed note drops onto its shadow, past the last one's edge.
                rightMargin: Theme.shadowOffset
                boundsBehavior: Flickable.StopAtBounds
                model: Scratchpad.notes.length
                currentIndex: Scratchpad.current

                delegate: InkButton {
                    id: chip

                    required property int index

                    text: root.label(index)
                    checked: index === Scratchpad.current
                    onClicked: Scratchpad.select(index)
                }
            }

            // Closes the current note; closing the only note clears it.
            InkButton {
                Layout.alignment: Qt.AlignTop
                icon: "\u{f0156}"
                onClicked: Scratchpad.remove(Scratchpad.current)
            }

            InkButton {
                Layout.alignment: Qt.AlignTop
                visible: !Scratchpad.full
                icon: "\u{f0415}"
                accent: "pink"
                onClicked: Scratchpad.add()
            }
        }

        InkBox {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.rightMargin: Theme.shadowOffset
            Layout.bottomMargin: Theme.shadowOffset

            // The padding around the editor is outside it, so a click there focuses the editor too. Behind the
            // Flickable, so clicks on the text, selection and scrolling reach the editor first.
            MouseArea {
                anchors.fill: parent
                enabled: editor.enabled
                cursorShape: Qt.IBeamCursor
                onPressed: editor.forceActiveFocus()
            }

            Flickable {
                id: flick

                anchors.fill: parent
                anchors.margins: Theme.pad
                contentWidth: width
                contentHeight: editor.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                // Keeps the cursor in view while typing.
                function follow(r: rect): void {
                    if (r.y < contentY)
                        contentY = r.y;
                    else if (r.y + r.height > contentY + height)
                        contentY = r.y + r.height - height;
                }

                TextEdit {
                    id: editor

                    // The editor owns its text while it is shown; the service only receives edits, so
                    // saving never moves the cursor. Switching tabs loads the other note.
                    function load(): void {
                        text = Scratchpad.notes[Scratchpad.current]?.text ?? "";
                        cursorPosition = text.length;
                    }

                    // Fills the box, so a click anywhere in it lands in the text (and focuses it).
                    width: flick.width
                    height: Math.max(implicitHeight, flick.height)
                    enabled: Scratchpad.loaded
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    selectByMouse: true
                    color: Theme.text
                    selectionColor: Theme.accent.sun
                    selectedTextColor: Theme.on.sun
                    font.family: Theme.font
                    font.pixelSize: 14
                    onTextChanged: {
                        if (Scratchpad.loaded)
                            Scratchpad.edit(Scratchpad.current, text);
                    }
                    onCursorRectangleChanged: flick.follow(cursorRectangle)
                    // No focus on open, so ←/→ still switch tabs until the note is clicked.
                    Component.onCompleted: load()

                    Connections {
                        target: Scratchpad

                        function onCurrentChanged(): void {
                            editor.load();
                            editor.forceActiveFocus();
                        }

                        function onLoadedChanged(): void {
                            editor.load();
                        }

                        // Closing the only note clears it.
                        function onNotesChanged(): void {
                            if ((Scratchpad.notes[Scratchpad.current]?.text ?? "") !== editor.text)
                                editor.load();
                        }
                    }
                }
            }

            InkText {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Theme.pad
                visible: editor.text === ""
                text: "Write something…"
                font.pixelSize: 14
                color: Theme.textMuted
            }
        }
    }
}
