import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.theme

// The dry-run preview on one monitor: the lock's content in an ordinary overlay window that takes the keyboard and
// takes no session lock. Escape (or `ipc call lock unlock`) closes it. It is the one thing that is shown for a dry
// run, and it can unlock nothing. Without a test PAM folder (GUTTER_LOCK_PAM_DIR) Enter checks nothing; with one
// the keys go to `Auth` as on the real surface, so the checks can be tried here. Its `visible` and layer never
// read fullscreen (test_windows.py): it only exists while it is wanted.
PanelWindow {
    id: win

    required property ShellScreen modelData

    screen: modelData
    visible: Lock.preview

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: Theme.paper
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "gutter-lock-preview"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    onVisibleChanged: {
        if (visible)
            keys.forceActiveFocus();
    }

    FocusScope {
        id: keys

        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            event.accepted = true;
            if (event.key === Qt.Key_Escape) {
                Lock.unlockDryRun();
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !Auth.testPam) {
                console.info("gutter: lock (dry run): not checked");
                Auth.buffer = "";
            } else {
                Auth.key(event);
            }
        }

        // Under the content, so its buttons get their own clicks (see LockSurface).
        MouseArea {
            anchors.fill: parent
            onPressed: keys.forceActiveFocus()
        }

        LockContent {
            anchors.fill: parent
            screenInfo: win.modelData
        }
    }
}
