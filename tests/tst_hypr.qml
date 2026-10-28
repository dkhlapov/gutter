import QtQuick
import QtTest
import "../lib/hypr.js" as H

TestCase {
    name: "Hypr"

    function test_specialNameFromMonitorIpc() {
        compare(H.specialName({ specialWorkspace: { id: -97, name: "special:game" } }), "special:game");
        compare(H.specialName({ specialWorkspace: { id: 0, name: "" } }), "");
        compare(H.specialName(null), "");
        compare(H.specialName({}), "");
    }

    function test_fullscreenOnActiveWorkspace() {
        verify(H.fullscreen({ hasFullscreen: true }, null));
        verify(!H.fullscreen({ hasFullscreen: false }, null));
        verify(!H.fullscreen(null, null));
    }

    // A fullscreen game on a special workspace shown over a normal one.
    function test_fullscreenOnSpecialWorkspace() {
        verify(H.fullscreen({ hasFullscreen: false }, { hasFullscreen: true }));
        verify(!H.fullscreen({ hasFullscreen: false }, { hasFullscreen: false }));
    }

    // Quickshell's workspace objects only learn hasFullscreen from a refresh, so a fullscreen game on a special
    // workspace went unseen and the island stayed above it.
    function test_refreshesWorkspacesOnFullscreenAndSpecialToggle() {
        verify(H.refreshesWorkspaces("fullscreen"));
        verify(H.refreshesWorkspaces("activespecial"));
        verify(!H.refreshesWorkspaces("activewindow"));
        verify(!H.refreshesWorkspaces(""));
    }

    // Hyprland keeps the last focused window as active after the workspace it sat on empties or is covered.
    function test_toplevelOnTop() {
        verify(H.toplevelOnTop("4", "4", ""));
        verify(!H.toplevelOnTop("11", "4", ""));
        verify(!H.toplevelOnTop("4", "2", ""));
        verify(!H.toplevelOnTop("", "4", ""));
    }

    function test_toplevelOnTopWithSpecial() {
        verify(H.toplevelOnTop("special:music", "4", "special:music"));
        // The special workspace covers the active one.
        verify(!H.toplevelOnTop("4", "4", "special:music"));
        verify(!H.toplevelOnTop("special:music", "4", ""));
    }

    function test_rememberMovesToFront() {
        const a = { id: "a" }, b = { id: "b" }, c = { id: "c" };
        compare(H.remember([], a, 3), [a]);
        compare(H.remember([a, b], b, 3), [b, a]);
        compare(H.remember([a, b, c], { id: "d" }, 3).length, 3);
        compare(H.remember([a, b], null, 3), [a, b]);
    }

    // An unfocused monitor shows the window focused last on its workspace in view.
    function test_lastOnWorkspaceInView() {
        const a = { workspace: { name: "4" } }, b = { workspace: { name: "11" } }, c = { workspace: { name: "11" } };
        compare(H.lastOn([a, b, c], "11"), b);
        compare(H.lastOn([a, b, c], "4"), a);
        compare(H.lastOn([a, b, c], "12"), null);
        compare(H.lastOn([a, b], ""), null);
        // A closed window has no workspace left.
        compare(H.lastOn([{ workspace: null }, null], "4"), null);
    }
}
