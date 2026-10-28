pragma Singleton

import QtQuick
import Quickshell

// Stand-in for services/Agents.qml in the agents check: three sessions running, one of them waiting: more than the Now card has room for, so its list scrolls.
Singleton {
    readonly property real now: 1800000000000
    readonly property bool hooksInstalled: true
    // No session works, so the Limits card's lamp, which sits on the box's top edge on purpose, stays off.
    readonly property var counts: ({ working: 0, waiting: 1 })
    readonly property var items: [
        { id: "a", status: "working", cwd: "/home/user/Projects/gutter", tool: "Bash", promptAt: now - 433000 },
        { id: "b", status: "waiting", cwd: "/home/user/Projects/a-project-with-a-much-longer-name", message: "Needs your input", promptAt: now - 90000 },
        { id: "c", status: "working", cwd: "/home/user/Projects/dotfiles", tool: "Edit", promptAt: now - 12000 }
    ]
}
