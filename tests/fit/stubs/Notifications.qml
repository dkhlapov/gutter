pragma Singleton

import QtQuick
import Quickshell

// Stand-in for services/Notifications.qml in the fit check.
Singleton {
    property var history: []
    property var queue: []
    property var current: null
    property int unread: 0
    property bool dnd: false
    property bool owned: true
    readonly property bool screenLocked: false
    property int bubbleHovers: 0
    readonly property bool bubbleHovered: bubbleHovers > 0
    property int replyTarget: 0
    property bool loaded: true

    function hoverBubble(on: bool): void {
    }

    function dismissBubble(): void {
    }

    function dismiss(id: int): void {
    }

    function clear(): void {
    }

    function markAllRead(): void {
    }

    function invoke(id: int, identifier: string): void {
    }

    function reply(id: int, text: string): void {
    }

    function activate(id: int): bool {
        return false;
    }

    function canActivate(id: int): bool {
        return false;
    }

    function openReply(id: int): void {
    }

    function toggleDnd(): void {
    }

    function setDnd(on: bool): void {
    }

    function recordFor(id: int): var {
        return history.find(h => h.id === id) ?? null;
    }
}
