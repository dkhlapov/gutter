import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import "../lib/lock.js" as LockLib

// The session lock and everything that starts and ends with it. A Scope, never a window: the compositor owns the
// lock's surfaces (one LockSurface per monitor, made and dropped by Quickshell as monitors come and go) and no
// window of ours can cover or unmap them. If the shell dies the compositor keeps the session locked.
//
// The only way out is `Auth.succeeded`, a successful PAM check, which fades the screen and then clears
// `held`, which `WlSessionLock.locked` is bound to (the lock has no callable unlock() in QML): when the fade ends, or
// after a second, whichever is first, so a stuck animation cannot keep a session locked that was unlocked. The dry-run preview (LockPreviewWindow) is closed the same way. `Auth`
// is begun when the lock (or the preview) appears and ended when it goes, strictly in pairs.
//
// A Quickshell hot reload builds a new WlSessionLock that adopts the old one's session lock and releases it if
// its own `locked` is false. So the intent to be locked (`held`) is carried across reloads by PersistentProperties,
// declared before the WlSessionLock so it is restored first, and `locked` is a binding to it. `held` is set only
// for a real lock (never for the dry-run preview) and cleared only after a successful unlock (or when the
// compositor ended the lock). A failed acquisition (the compositor ends the lock before it is secure) drops `held`
// through `releaseEnded()` (from `onLockedChanged`, or on stable, which sends none, from `onSecureChanged`); a
// compositor that never answers leaves `held` true on purpose: the lock stays wanted, and the session fails closed.
// After a failed acquisition Quickshell hits a protocol error (it destroys the lock before its surfaces; an upstream
// ordering issue) and the shell exits: the session stays locked, and only a restart or the rescue script gets out.
//
// The state Lock publishes does not read `WlSessionLock.locked` back: stable Quickshell 0.3.2 sends no `lockedChanged`
// after our own release (`secureChanged` does come, while `locked` still reads true), so a binding on it would stay
// true (only a later look, as `releaseEnded()` takes, sees false). The state follows `held` (asked for) and
// `confirmed` (the compositor said so, cleared by our own PAM success or by `secure` going false), one source of
// truth that a lock adopted by a reload also sets (in `resume()`).
//
// Quickshell pairs the children of a Scope with the old instance's by INDEX on a reload. Do not put new elements
// before the PersistentProperties and the WlSessionLock below (or before `LockScreen {}` in shell.qml) while the
// session is locked: a hot reload would then pair them wrongly and the old lock manager would be deleted, which
// sends a destroy after `locked` (a protocol error): the compositor disconnects the shell and it exits. That fails
// closed (the compositor keeps the session locked) but leaves no surfaces, and only the rescue script gets out.
Scope {
    id: root

    // Auth.begin() has run and Auth.end() has not.
    property bool authOn: false
    // The compositor has confirmed the real lock, and we have not released or lost it since.
    property bool confirmed: false
    // The dry-run preview is the thing that began Auth (never true while a real lock is held).
    property bool previewOn: false

    PersistentProperties {
        id: persisted

        reloadableId: "lockscreen"

        property bool held: false

        // After a reload a carried-over lock never changes `secure`: begin the check here.
        onReloaded: Qt.callLater(root.resume)
    }

    // The lock was already up when this instance started (a hot reload kept it): bring the screen's own state back.
    function resume(): void {
        confirmed = lock.secure;
        if (!confirmed)
            return;
        Lock.hint.set(true);
        beginAuth();
    }

    function beginAuth(): void {
        if (authOn)
            return;
        authOn = true;
        // Defensive: no path begins Auth while an unlock is under way, but a flag left set would block every lock.
        Lock.unlocking = false;
        unlockFade.stop();
        unlockTimer.stop();
        Lock.fade = 1;
        // The preview only draws the screen; the account's PAM and fingerprint reader stay out of a dry run.
        Auth.fingerprintAllowed = !previewOn || Auth.testPam;
        Auth.begin();
    }

    function endAuth(): void {
        if (!authOn)
            return;
        authOn = false;
        Auth.end();
    }

    // The right password or print: the hint goes first (a restart during the fade must not lock again), then the
    // fade, then the release. `Lock.unlocking` is set before anything else can yield: for up to a frame (~16 ms) after
    // this `Lock.fade` is still 1 (the animation has not ticked), and a sleep handled in that window must not take the
    // lock for up.
    function startUnlock(): void {
        if (Lock.unlocking || !authOn)
            return;
        if (!Lock.locked && !previewOn)
            return;
        Lock.unlocking = true;
        Lock.hint.set(false);
        unlockFade.restart();
        unlockTimer.restart();
    }

    function finishUnlock(): void {
        if (!Lock.unlocking)
            return;
        unlockFade.stop();
        unlockTimer.stop();
        if (previewOn) {
            // The preview's handler below does the rest (it stops the fade, ends Auth and clears the flag), also
            // for a preview closed from outside.
            Lock.preview = false;
            return;
        }
        // The release: `lock.locked` is bound to `held`, so this unlocks the session. Only now is the lock no
        // longer wanted, so a reload from here on does not take it again. (WlSessionLock has no callable
        // unlock(): calling it is a TypeError that left the screen faded and locked.) Our own PAM success is the
        // authority that it is over: stable Quickshell sends no `lockedChanged` after a release of our own, so
        // `confirmed` goes first, and Lock does not wait for a signal.
        root.confirmed = false;
        persisted.held = false;
        endAuth();
        Lock.fade = 1;
        // The fallback: normally `onSecureChanged` (the release emits it at once) has cleared the flag already. Last,
        // so that a sleep handled before this still sees the lock as being unlocked.
        Lock.unlocking = false;
    }

    WlSessionLock {
        id: lock

        locked: persisted.held

        onSecureChanged: {
            // `root.confirmed` stays the first statement: `Lock.secure` must follow before `Lock.fade` and
            // `Lock.unlocking` are reset below (Idle's `lockUp` would otherwise see the lock up for a moment).
            root.confirmed = secure;
            if (secure) {
                Lock.hint.set(true);
                root.beginAuth();
            } else {
                // The LockedHint is left as it is: only a successful unlock clears it, so a lock the compositor
                // ended some other way is taken again at the next start. The rescue script must clear it. This branch
                // also runs during our own release (`finishUnlock` clears `held` just before its `endAuth()`, which
                // then does nothing if the call below already ended Auth; `authOn` keeps the pairing).
                unlockFade.stop();
                unlockTimer.stop();
                root.endAuth();
                Lock.fade = 1;
                Lock.unlocking = false;
                // Stable Quickshell sends no `lockedChanged` when a lock is ended; look again once the manager has
                // dropped its lock object (at this signal it still holds it).
                Qt.callLater(root.releaseEnded);
            }
        }

        LockSurface {}
    }

    // The compositor ended the lock without Auth (not a reload, which never goes from locked to unlocked): it is
    // no longer wanted, and a later request must be able to take it again.
    function releaseEnded(): void {
        if (!lock.locked && persisted.held)
            persisted.held = false;
    }

    // The lock is held when it is wanted (`held`, carried over a reload) or confirmed.
    Binding {
        target: Lock
        property: "locked"
        value: persisted.held || root.confirmed
    }

    // The compositor's confirmation, for what must not rely on a lock only asked for (Idle's lock before sleep).
    // Declared after the WlSessionLock and the first Binding, like everything added here.
    Binding {
        target: Lock
        property: "secure"
        value: root.confirmed
    }

    Connections {
        target: lock

        function onLockedChanged(): void {
            root.releaseEnded();
        }
    }

    Connections {
        target: Lock

        function onLockRequested(): void {
            persisted.held = true;
            // Quickshell refuses at once (no ext-session-lock-v1 protocol, a second lock in this process, a null
            // surface component), leaving no lock object: `lock.locked` is then false, and `held` goes back so a
            // later request tries again. Later failures (a stale lock, `allow_session_lock_restore` off) arrive as
            // the compositor's `finished` event, and `releaseEnded()` drops `held` (from `onLockedChanged`, or on
            // stable, which sends none, from `onSecureChanged`). A pending lock (`locked` true, `secure` not yet) is
            // never dropped here: it fails closed, and a late grant stays locked.
            if (!lock.locked)
                persisted.held = false;
        }

        function onPreviewChanged(): void {
            if (Lock.preview) {
                // A preview is never shown over a real lock, or one on its way: it would take the Auth that the
                // lock needs to unlock.
                if (!LockLib.previewAllowed(persisted.held, lock.locked, root.confirmed)) {
                    console.warn("gutter: lock: locked, no dry-run preview");
                    Lock.preview = false;
                    return;
                }
                root.previewOn = true;
                Lock.hint.set(true);
                root.beginAuth();
            } else {
                if (!root.previewOn)
                    return;
                root.previewOn = false;
                unlockFade.stop();
                unlockTimer.stop();
                // A dry run's hint is a test file or none: never the real session's.
                if (Lock.hintBackend !== "logind")
                    Lock.hint.set(false);
                root.endAuth();
                Lock.fade = 1;
                Lock.unlocking = false;
            }
        }
    }

    Connections {
        target: Auth

        function onSucceeded(): void {
            root.startUnlock();
        }
    }

    NumberAnimation {
        id: unlockFade

        target: Lock
        property: "fade"
        from: 1
        to: 0
        duration: 250
        onFinished: root.finishUnlock()
    }

    Timer {
        id: unlockTimer

        interval: 1000
        onTriggered: root.finishUnlock()
    }

    // A session that was left locked (the shell restarted or reloaded) is locked again.
    Component.onCompleted: {
        // A lock carried over a reload may be secure already.
        resume();
        Lock.restore();
    }
}
