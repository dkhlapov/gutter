pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import "activities"

// Shows the compact view of an activity (the current one unless `activityId` says otherwise); each activity
// id maps to its view in `components`. A HUD also names the label tab it starts with on the island (`tabText`).
Item {
    id: root

    property string activityId: Activities.current?.id ?? ""
    readonly property var components: ({
            volume: volumeHud,
            brightness: brightnessHud,
            kbLayout: keysHud,
            capsLock: keysHud,
            numLock: keysHud,
            track: nowPlaying,
            timer: timerPill,
            stopwatch: timerPill,
            timerDone: timerPill,
            agentDone: agentPill,
            agentLimit: agentPill,
            notification: notificationPill
        })
    // The label tab at the start of the island for the HUDs.
    readonly property var tabs: ({
            volume: {
                text: "VOL",
                accent: "coral"
            },
            brightness: {
                text: "BRI",
                accent: "sun"
            },
            kbLayout: {
                text: "KBD",
                accent: "lime"
            },
            capsLock: {
                text: "CAPS",
                accent: "lime"
            },
            numLock: {
                text: "NUM",
                accent: "lime"
            }
        })
    readonly property string tabText: tabs[activityId]?.text ?? ""
    readonly property string tabAccent: tabs[activityId]?.accent ?? "sun"

    // How narrow the view can be laid out: the fixed parts of its face, with the text elided to nothing.
    readonly property real minimumWidth: (loader.item as Item)?.Layout.minimumWidth ?? 0

    implicitWidth: loader.implicitWidth
    implicitHeight: loader.implicitHeight

    Loader {
        id: loader

        // A narrower view (the pill's body squeezed by its box) lays its face out narrower too.
        width: root.width

        sourceComponent: root.components[root.activityId] ?? null
    }

    Component {
        id: volumeHud

        VolumeHud {
            accent: root.tabAccent
        }
    }

    Component {
        id: brightnessHud

        BrightnessHud {
            accent: root.tabAccent
        }
    }

    Component {
        id: keysHud

        KeysHud {
            kind: root.activityId === "kbLayout" ? "layout" : root.activityId === "capsLock" ? "caps" : "num"
        }
    }

    Component {
        id: agentPill

        AgentPill {
            kind: root.activityId
        }
    }

    Component {
        id: notificationPill

        NotificationPill {}
    }

    Component {
        id: timerPill

        TimerPill {
            kind: root.activityId
        }
    }

    Component {
        id: nowPlaying

        NowPlaying {}
    }
}
