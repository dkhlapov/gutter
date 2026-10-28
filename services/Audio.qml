pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../lib/volume.js" as VolumeLib
import "../lib/activities.js" as ActLib

Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink?.ready ?? false
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    // The default microphone: the status row's mic chip mutes it.
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool micReady: source?.ready ?? false
    readonly property bool micMuted: source?.audio?.muted ?? false
    property var tracker: VolumeLib.createTracker()

    function setVolume(v: real): void {
        if (!ready || !sink.audio)
            return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, v));
    }

    function scroll(steps: real): void {
        setVolume(VolumeLib.step(volume, steps));
    }

    // Volume keys: always show the HUD, even at 0 % / 100 % where the value does not change.
    function press(delta: real): void {
        if (!ready)
            return;
        setVolume(Math.round((volume + delta) * 100) / 100);
        Activities.show("volume", ActLib.PRIORITY.hud, 1500, "");
    }

    function toggleMute(): void {
        if (!ready || !sink.audio)
            return;
        sink.audio.muted = !sink.audio.muted;
        Activities.show("volume", ActLib.PRIORITY.hud, 1500, "");
    }

    function toggleMicMute(): void {
        if (!micReady || !source.audio)
            return;
        source.audio.muted = !source.audio.muted;
    }

    function check(): void {
        if (!ready)
            return;
        const r = VolumeLib.update(tracker, sink.id, volume, muted);
        tracker = r.tracker;
        if (r.changed)
            Activities.show("volume", ActLib.PRIORITY.hud, 1500, "");
    }

    // A new default sink resets the tracker, even when its volume and mute match the old one's.
    onSinkChanged: check()
    onReadyChanged: check()
    onVolumeChanged: check()
    onMutedChanged: check()

    PwObjectTracker {
        objects: [root.sink, root.source]
    }
}
