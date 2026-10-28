pragma Singleton

import QtQuick
import Quickshell

// Stand-in for services/Launcher.qml in the fit check: the state is whatever the check writes, and nothing runs.
Singleton {
    property string screen: "fit"
    property string mode: "launcher"
    property string query: ""
    property int selected: 0
    property string confirming: ""
    property bool dryRun: true
    property string lastDryRun: ""
    property var usage: ({})
    property bool loaded: true
    property var parsed: ({
            mode: "apps",
            text: ""
        })
    property var apps: []
    property var commands: []
    property var results: []

    function resetSelection(): void {
    }
    function open(screenName: string, newMode: string): void {
    }
    function close(): void {
    }
    function toggle(screenName: string, newMode: string): void {
    }
    function setQuery(text: string): void {
    }
    function move(delta: int): void {
    }
    function complete(): void {
    }
    function cancel(): void {
    }
    function activate(): void {
    }
    function choose(name: string): void {
    }
}
