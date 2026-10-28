import QtQuick
import Quickshell
import Quickshell.Wayland

// The rescue shell, run by scripts/rescue-unlock.sh as its own `qs -p lockscreen/rescue`. It takes the session lock
// that a dead lock screen left behind (the compositor allows that with misc:allow_session_lock_restore), waits a
// moment, releases it and quits. No PAM: whoever runs it is already logged in on a TTY. It imports nothing of
// Gutter's, so a broken Gutter cannot break it.
//
// It exits 0 only after the lock was confirmed (secure) and released. If the compositor refuses the lock (a live
// lock client still holds it: the lock `locked` goes back to false, as on `finished`), or the lock is not
// confirmed within `giveUpMs`, it logs why and exits 1, so the script leaves the hint and says the session is still
// locked. On stable Quickshell a refusal reaches `onSecureChanged` (false) but never `onLockedChanged`, so only the
// `giveUp` timer catches it (exit 1, still locked).
ShellRoot {
    id: root

    // Whether the lock is wanted; the release is `wanted = false` (the lock's `locked` follows it), as
    // WlSessionLock has no callable unlock().
    property bool wanted: true
    // The lock was confirmed, so a `locked` that goes false from now on is our own release.
    property bool held: false
    // How long the compositor has to confirm the lock.
    property int giveUpMs: 5000

    function fail(why: string): void {
        console.error(`gutter rescue: ${why}`);
        Qt.exit(1);
    }

    WlSessionLock {
        id: lock

        locked: root.wanted

        onSecureChanged: {
            if (secure) {
                root.held = true;
                giveUp.stop();
                hold.start();
            }
        }

        // The compositor ended the lock before it was confirmed: refused (a live client holds it) or finished.
        onLockedChanged: {
            if (!locked && root.wanted && !root.held)
                root.fail("the compositor refused the lock (is the lock screen still running? it must be ended first)");
        }

        WlSessionLockSurface {
            color: "#202020"
        }
    }

    Timer {
        id: giveUp

        running: true
        interval: root.giveUpMs
        onTriggered: root.fail(`the lock was not confirmed within ${interval / 1000} s`)
    }

    Timer {
        id: hold

        interval: 1500
        onTriggered: {
            root.wanted = false;
            quit.start();
        }
    }

    // A moment for the unlock to reach the compositor before the process goes.
    Timer {
        id: quit

        interval: 300
        onTriggered: Qt.quit()
    }
}
