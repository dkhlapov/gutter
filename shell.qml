//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import qs.bar
import qs.dev
import qs.ipc
import qs.launcher
import qs.lockscreen
import qs.pill
import qs.services
import qs.settings
import qs.wallpaper

ShellRoot {
    // A singleton loads only when referenced; touching each one here starts its work at launch.
    Component.onCompleted: [Audio.ready, Brightness.buses, Media.playing, Weather.data, Agents.items, AgentUsage.data, Shelf.loaded, Clipboard.items, Notifications.dnd, Wallpaper.path, Settings.sections, Power.entries, ThemeMode.mode, Launcher.screen, Lock.locked, Idle.active, LockKeys.kind]

    Variants {
        model: Quickshell.screens

        WallpaperWindow {}
    }

    Variants {
        model: Quickshell.screens

        PillWindow {}
    }

    Variants {
        model: Quickshell.screens

        BarWindow {}
    }

    Variants {
        model: Quickshell.screens

        LauncherWindow {}
    }

    Variants {
        model: Quickshell.screens

        WorkspaceWindow {}
    }

    // Quickshell pairs a reload's children by index: while the session is locked, do not add elements before
    // this one (see lockscreen/LockScreen.qml).
    LockScreen {}

    Variants {
        model: Quickshell.screens

        LockPreviewWindow {}
    }

    GutterIpc {}

    Shortcuts {}

    LazyLoader {
        active: Quickshell.env("GUTTER_GALLERY") === "1"

        Gallery {}
    }
}
