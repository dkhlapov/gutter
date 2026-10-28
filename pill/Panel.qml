import QtQuick
import Quickshell
import qs.components
import qs.services
import qs.settings
import qs.theme
import "../lib/pillState.js" as PillState

// The expanded pill: a caption box with one label tab per section along its top edge. Its size is driven from
// outside (the pill's animated size); the section is laid out at full size and revealed by the growing box.
CaptionBox {
    id: root

    required property ShellScreen screen
    readonly property var accents: ({
            overview: "sun",
            music: "pink",
            calendar: "teal",
            system: "lime",
            weather: "navy",
            tools: "coral",
            agents: "magenta",
            mixer: "teal",
            clipboard: "lime",
            shelf: "coral",
            notifications: "sun"
        })

    tabs: Settings.sections.map(name => ({
                text: name,
                accent: root.accents[name] ?? "sun"
            }))
    currentTab: Settings.sections.indexOf(PillControl.section)
    currentHalftone: true
    keyline: true

    onTabClicked: index => PillControl.openOn(PillControl.openScreen, Settings.sections[index])

    Item {
        anchors.fill: parent
        clip: true

        SectionHost {
            x: Theme.pad
            y: Theme.pad
            width: PillState.OPEN_W - 2 * (Theme.inkWidth + Theme.pad)
            height: PillState.OPEN_H - root.headroom - 2 * (Theme.inkWidth + Theme.pad)
            section: PillControl.section
            screen: root.screen
        }
    }
}
