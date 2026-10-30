import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.theme
import "../../lib/agentUsage.js" as U
import "../../lib/glyphs.js" as Glyphs

// The agent's short alerts. "agentLimit": a plan window crossed 80 / 95 %, a pill on the island. "agentDone" is a
// speech bubble: a check, AGENT DONE, what finished and the prompt. (A session working or waiting is the Claude
// pill beside the island, pill/ClaudePill.qml.)
RowLayout {
    id: root

    required property string kind
    readonly property bool bubble: kind === "agentDone"
    readonly property string title: bubble ? `${Agents.lastDone?.project ?? "Claude"} finished` : `${AgentUsage.alert?.window ?? "Session"} limit ${AgentUsage.alert?.pct ?? 0}%`
    readonly property string detail: {
        if (bubble)
            return Agents.lastDone?.prompt ?? "";
        return (AgentUsage.alert?.resetsIn ?? -1) > 0 ? `resets in ${U.duration(AgentUsage.alert.resetsIn)}` : "";
    }

    spacing: Theme.gap

    IconPlate {
        accent: root.bubble ? "lime" : "coral"
        icon: Glyphs.glyph(root.bubble ? "check" : "speed")
    }

    ColumnLayout {
        visible: root.bubble
        spacing: 2

        BubbleHeadline {
            text: "AGENT DONE"
        }

        InkText {
            Layout.maximumWidth: 320
            text: root.title
            font.bold: true
            elide: Text.ElideRight
        }

        InkText {
            Layout.maximumWidth: 320
            visible: root.detail !== ""
            text: root.detail
            elide: Text.ElideRight
            color: Theme.textMuted
        }
    }

    // Squeezed by the pill, the title and detail give way (they elide); the icon keeps its width.
    InkText {
        Layout.maximumWidth: 200
        Layout.fillWidth: true
        visible: !root.bubble
        text: root.title
        font.bold: true
        elide: Text.ElideRight
    }

    InkText {
        Layout.maximumWidth: 150
        Layout.fillWidth: true
        visible: !root.bubble && root.detail !== ""
        text: root.detail
        elide: Text.ElideRight
        color: Theme.textMuted
    }
}
