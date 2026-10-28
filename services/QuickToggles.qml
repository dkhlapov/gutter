pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Microphone mute, keep awake and lock (which is Lock.request(), Gutter's own lock screen).
Singleton {
    id: root

    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool micReady: source?.ready ?? false
    readonly property bool micMuted: source?.audio?.muted ?? false
    // Read by PillWindow's IdleInhibitor (the inhibitor needs a mapped window).
    property bool keepAwake: false

    function toggleMic(): void {
        if (micReady && source.audio)
            source.audio.muted = !source.audio.muted;
    }

    function toggleKeepAwake(): void {
        keepAwake = !keepAwake;
    }

    function lock(): void {
        PillControl.close();
        Lock.request();
    }

    PwObjectTracker {
        objects: [root.source]
    }
}
