pragma Singleton

import QtQuick
import Quickshell

// Stand-in for services/AgentUsage.qml in the fit check.
Singleton {
    property var limits: ({ session: null })
    property var alert: null
}
