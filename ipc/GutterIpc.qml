import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Scope {
    IpcHandler {
        target: "gutter"

        function toggle(): void {
            PillControl.toggle(Hypr.focusedScreenName, "");
        }

        function open(section: string): void {
            PillControl.openOn(Hypr.focusedScreenName, section);
        }

        // For scripts (scripts/shot.sh): open on a named monitor without moving focus there.
        function openOn(screen: string, section: string): void {
            PillControl.openOn(screen, section);
        }

        function close(): void {
            PillControl.close();
        }

        function volumeUp(): void {
            Audio.press(0.1);
        }

        function volumeDown(): void {
            Audio.press(-0.1);
        }

        function volumeMute(): void {
            Audio.toggleMute();
        }

        function brightnessUp(): void {
            Brightness.change(0.05);
        }

        function brightnessDown(): void {
            Brightness.change(-0.05);
        }

        // Starts a timer of that many minutes; 0 resets it.
        function timer(minutes: real): void {
            if (minutes > 0)
                Timers.startTimer(minutes);
            else
                Timers.resetTimer();
        }

        function timerToggle(): void {
            Timers.toggleTimer();
        }

        function stopwatchToggle(): void {
            Timers.toggleStopwatch();
        }

        // Do-not-disturb: holds back every bubble except critical ones; all of them still reach the history.
        function notificationsDnd(): void {
            Notifications.toggleDnd();
        }

        // Empties the notification history.
        function notificationsClear(): void {
            Notifications.clear();
        }

        // Opens the notifications section on the focused monitor.
        function notificationsOpen(): void {
            PillControl.openOn(Hypr.focusedScreenName, "notifications");
        }

        // Puts a file or folder (absolute path) on the shelf, e.g. from a script or a file manager action.
        function shelfAdd(path: string): void {
            Shelf.addPath(path);
        }

        function shelfClear(): void {
            Shelf.clear();
        }

        // Opens or closes the power menu on a monitor ("" for the focused one).
        function powerMenu(screen: string): void {
            Power.toggleMenu(screen !== "" ? screen : Hypr.focusedScreenName);
        }

        // While on, power actions are logged instead of run; off again at the next start.
        function powerDryRun(on: bool): void {
            Power.dryRun = on;
        }

        // The action the last dry run logged ("" for none).
        function powerLastDryRun(): string {
            return Power.lastDryRun;
        }

        // Opens or closes the launcher on a monitor ("" for the focused one).
        function launcher(screen: string): void {
            Launcher.toggle(screen !== "" ? screen : Hypr.focusedScreenName, "launcher");
        }

        // Opens or closes the session screen on a monitor ("" for the focused one).
        function session(screen: string): void {
            Launcher.toggle(screen !== "" ? screen : Hypr.focusedScreenName, "session");
        }

        // Types into the launcher's search box, e.g. "/dark".
        function launcherQuery(text: string): void {
            Launcher.setQuery(text);
        }

        // While on, launching and commands are logged instead of run; off again at the next start.
        function launcherDryRun(on: bool): void {
            Launcher.dryRun = on;
        }

        // The action the last dry run logged ("" for none).
        function launcherLast(): string {
            return Launcher.lastDryRun;
        }

        // Flips light and dark until the next automatic switch (for good in a fixed mode).
        function themeToggle(): void {
            ThemeMode.toggle();
        }

        // A flip to "light" or "dark"; anything else is ignored with a warning.
        function themeSet(mode: string): void {
            ThemeMode.set(mode);
        }

        // The sun/moon cell's tooltip, e.g. "Dark until 07:12 (sunrise)".
        function themeStatus(): string {
            return ThemeMode.tip;
        }
    }

    IpcHandler {
        target: "lock"

        // Locks the session (a dry run shows the preview instead), or does nothing when it is locked already.
        function lock(): void {
            Lock.request();
        }

        // Whether the real lock is held.
        function isLocked(): bool {
            return Lock.locked;
        }

        // While on, a lock request only shows the preview and takes no lock; off again at the next start. Not
        // changed while the real lock is held. Answers with what it did (turning it on says that no real lock
        // will be taken).
        function dryRun(on: bool): string {
            return Lock.setDryRun(on);
        }

        // What the last dry run would have done ("" for none).
        function last(): string {
            return Lock.lastDryRun;
        }

        // Closes the dry-run preview. The real lock has no unlock here: only the password or a fingerprint does.
        function unlock(): void {
            Lock.unlockDryRun();
        }
    }
}
