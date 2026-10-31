import QtQuick
import QtTest
import "../lib/pillState.js" as S
import "../lib/activities.js" as A

TestCase {
    name: "PillState"

    readonly property var all: ["overview", "music", "calendar", "system", "weather"]

    function test_resolveSectionPrefersRequested() {
        compare(S.resolveSection("system", "music", all), "system");
    }

    function test_resolveSectionKeepsCurrentWhenNoRequest() {
        compare(S.resolveSection("", "calendar", all), "calendar");
    }

    // Review focus 4: current section removed from config.
    function test_resolveSectionFallsBackToFirst() {
        compare(S.resolveSection("", "weather", ["music", "calendar"]), "music");
        compare(S.resolveSection("bogus", "weather", ["calendar"]), "calendar");
    }

    function test_shiftSectionClamps() {
        compare(S.shiftSection("music", all, 1), "calendar");
        compare(S.shiftSection("overview", all, -1), "overview");
        compare(S.shiftSection("weather", all, 1), "weather");
        compare(S.shiftSection("gone", all, 1), "music");
    }

    function facts(over) {
        return Object.assign({ open: false, fullscreenHidden: false, hasActivity: false }, over);
    }

    function test_deriveIdleByDefault() {
        compare(S.derive(facts({})), { mode: "idle", peek: false });
    }

    function test_deriveOpenWins() {
        compare(S.derive(facts({ open: true, fullscreenHidden: true })), { mode: "open", peek: false });
    }

    function test_deriveFullscreenHides() {
        compare(S.derive(facts({ fullscreenHidden: true, hasActivity: true })).mode, "hidden");
    }

    function test_deriveActivity() {
        compare(S.derive(facts({ hasActivity: true })).mode, "activity");
    }

    // Hovered, the island peeks; the panel and a hidden island do not.
    function test_hoverPeeks() {
        compare(S.derive(facts({ hovered: true })), { mode: "idle", peek: true });
        compare(S.derive(facts({ hovered: true, hasActivity: true })), { mode: "activity", peek: true });
        compare(S.derive(facts({ hovered: false })).peek, false);
        compare(S.derive(facts({ hovered: true, open: true })), { mode: "open", peek: false });
        compare(S.derive(facts({ hovered: true, fullscreenHidden: true })), { mode: "hidden", peek: false });
    }

    function test_peekSize() {
        compare(S.peekSize({ mode: "idle", peek: true }), { w: 32, h: 6 });
        compare(S.peekSize({ mode: "activity", peek: true }), { w: 32, h: 6 });
        compare(S.peekSize({ mode: "idle", peek: false }), { w: 0, h: 0 });
        compare(S.peekSize({ mode: "open", peek: false }), { w: 0, h: 0 });
    }

    function act(over) {
        return Object.assign({ w: 0, id: "" }, over || {});
    }

    readonly property int rest: 38

    // The island rests at one height and the width it is given, with or without an activity narrower than it.
    function test_sizes() {
        compare(S.size({ mode: "idle" }, 200, act(), rest), { w: 200, h: 38 });
        compare(S.size({ mode: "hidden" }, 200, act(), rest), { w: 200, h: 0 });
        compare(S.size({ mode: "activity" }, 200, act({ w: 300, id: "volume" }), rest), { w: 300, h: 38 });
        compare(S.size({ mode: "activity" }, 200, act({ w: 900, id: "volume" }), rest), { w: 420, h: 38 });
        compare(S.size({ mode: "activity" }, 200, act({ w: 50, id: "volume" }), rest), { w: 200, h: 38 });
        compare(S.size({ mode: "open" }, 200, act(), rest), { w: 1010, h: 420 });
    }

    function test_restHeightFollowsTheArgument() {
        compare(S.size({ mode: "idle" }, 200, act(), 32).h, 32);
        compare(S.size({ mode: "activity" }, 200, act({ w: 300, id: "timer" }), 32).h, 32);
    }

    function test_trackPopIsTaller() {
        compare(S.size({ mode: "activity" }, 200, act({ w: 420, id: "track" }), rest), { w: 420, h: 48 });
    }

    function test_fitCentresNarrowerContent() {
        compare(S.fit(100, 300), { w: 100, x: 100 });
        compare(S.fit(300, 300), { w: 300, x: 0 });
    }

    // Wider content (a capped face, or a box still growing towards it) gets the room and no more; it elides.
    function test_fitSqueezesWiderContent() {
        compare(S.fit(537, 361), { w: 361, x: 0 });
    }

    // A box shrinking to nothing (hidden over a fullscreen window) leaves no room at all.
    function test_fitNoRoom() {
        compare(S.fit(200, -20), { w: 0, x: 0 });
    }

    function test_raised_on_every_monitor() {
        verify(S.windowRaised({ open: false, hideInFullscreen: false }));
        verify(!S.windowRaised({ open: false, hideInFullscreen: true }));
        verify(S.windowRaised({ open: true, hideInFullscreen: true }));
    }

    function test_bubbles() {
        verify(S.isBubble("timerDone"));
        verify(S.isBubble("agentDone"));
        verify(S.isBubble("notification"));
        verify(!S.isBubble("volume"));
    }

    // The panel shows message bodies in the notifications section, which a lock (the dry-run preview too) never shows.
    function test_canOpenRefusesNotificationsWhileLocked() {
        verify(S.canOpen("notifications", false));
        verify(!S.canOpen("notifications", true));
        verify(S.canOpen("music", true));
        // "" keeps the last section: allowed, the caller resolves it against allowedSections.
        verify(S.canOpen("", true));
    }

    function test_allowedSectionsDropsNotificationsWhileLocked() {
        const sections = ["overview", "notifications", "music"];
        compare(S.allowedSections(sections, false), sections);
        compare(S.allowedSections(sections, true), ["overview", "music"]);
        compare(sections.length, 3);
    }

    // A remembered notifications section does not come back while locked, and shifting steps over it.
    function test_lockedLandingNeverOnNotifications() {
        const sections = ["overview", "notifications", "music"];
        const allowed = S.allowedSections(sections, true);
        compare(S.resolveSection("", "notifications", allowed), "overview");
        compare(S.shiftSection("overview", allowed, 1), "music");
        compare(S.shiftSection("music", allowed, -1), "overview");
        compare(S.shiftSection("notifications", allowed, 1), "music");
    }

    function test_closeOnLock() {
        verify(S.closeOnLock("notifications", true));
        verify(!S.closeOnLock("notifications", false));
        verify(!S.closeOnLock("music", true));
    }

    function test_landingRefusesCleanlyWhenNothingIsLeft() {
        // Notifications is the only configured section: nothing to land on or shift to while locked, null (not undefined).
        compare(S.landing("", "notifications", ["notifications"], true), null);
        compare(S.landing("notifications", "notifications", ["notifications"], true), null);
        compare(S.shifted("notifications", ["notifications"], 1, true), null);
        compare(S.allowedSections(["notifications"], true), []);
        // Unlocked it is an ordinary section.
        compare(S.landing("", "notifications", ["notifications"], false), "notifications");
        compare(S.shifted("notifications", ["notifications"], 1, false), "notifications");
    }

    function test_landingWhileLocked() {
        const sections = ["notifications", "music", "calendar"];
        compare(S.landing("notifications", "music", sections, true), null);
        // A config edit puts notifications first while the panel is on music: the section stays music.
        compare(S.landing("", "music", sections, true), "music");
        compare(S.landing("", "notifications", sections, true), "music");
        compare(S.landing("calendar", "music", sections, true), "calendar");
        compare(S.landing("notifications", "music", sections, false), "notifications");
        compare(S.shifted("music", sections, -1, true), "music");
        compare(S.shifted("music", sections, 1, true), "calendar");
        compare(S.shifted("music", sections, -1, false), "notifications");
    }

    // Exactly those three of every activity there is: a new id is a pill until it is added to BUBBLES.
    function test_onlyTheDoneAndNotificationActivitiesAreBubbles() {
        const ids = Object.keys(A.PRIORITY);
        compare(ids.filter(S.isBubble).sort(), ["agentDone", "notification", "timerDone"]);
    }
}
