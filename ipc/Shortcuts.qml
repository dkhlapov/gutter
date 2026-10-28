import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

Scope {
    GlobalShortcut {
        appid: "gutter"
        name: "toggle"
        description: "Open or close the pill panel"
        onPressed: PillControl.toggle(Hypr.focusedScreenName, "")
    }

    GlobalShortcut {
        appid: "gutter"
        name: "brightnessUp"
        description: "Increase brightness of the focused monitor"
        onPressed: Brightness.change(0.05)
    }

    GlobalShortcut {
        appid: "gutter"
        name: "brightnessDown"
        description: "Decrease brightness of the focused monitor"
        onPressed: Brightness.change(-0.05)
    }

    GlobalShortcut {
        appid: "gutter"
        name: "volumeUp"
        description: "Raise volume 10 % and show the HUD"
        onPressed: Audio.press(0.1)
    }

    GlobalShortcut {
        appid: "gutter"
        name: "volumeDown"
        description: "Lower volume 10 % and show the HUD"
        onPressed: Audio.press(-0.1)
    }

    GlobalShortcut {
        appid: "gutter"
        name: "volumeMute"
        description: "Toggle mute and show the HUD"
        onPressed: Audio.toggleMute()
    }

    GlobalShortcut {
        appid: "gutter"
        name: "capsLock"
        description: "Caps Lock was pressed: show its state"
        onPressed: LockKeys.poke()
    }

    GlobalShortcut {
        appid: "gutter"
        name: "numLock"
        description: "Num Lock was pressed: show its state"
        onPressed: LockKeys.poke()
    }

    GlobalShortcut {
        appid: "gutter"
        name: "mediaToggle"
        description: "Play or pause the shown player, else any playing one"
        onPressed: Media.keyToggle()
    }

    GlobalShortcut {
        appid: "gutter"
        name: "mediaNext"
        description: "Next track on the shown player, else any playing one"
        onPressed: Media.keyNext()
    }

    GlobalShortcut {
        appid: "gutter"
        name: "mediaPrev"
        description: "Previous track on the shown player, else any playing one"
        onPressed: Media.keyPrevious()
    }

    GlobalShortcut {
        appid: "gutter"
        name: "mediaStop"
        description: "Stop the shown player, else any playing one"
        onPressed: Media.keyStop()
    }

    GlobalShortcut {
        appid: "gutter"
        name: "themeToggle"
        description: "Flip between light and dark until the next automatic switch"
        onPressed: ThemeMode.toggle()
    }

    GlobalShortcut {
        appid: "gutter"
        name: "launcher"
        description: "Open or close the launcher"
        // The bind is a SUPER tap, which Hyprland fires on release (`release = true`);
        // acting on press would race the key still being held.
        onReleased: Launcher.toggle(Hypr.focusedScreenName, "launcher")
    }

    GlobalShortcut {
        appid: "gutter"
        name: "session"
        description: "Open or close the session menu"
        onPressed: Launcher.toggle(Hypr.focusedScreenName, "session")
    }

    GlobalShortcut {
        appid: "gutter"
        name: "lock"
        description: "Lock the session"
        onPressed: Lock.request()
    }
}
