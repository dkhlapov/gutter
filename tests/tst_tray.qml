import QtQuick
import QtTest
import "../lib/tray.js" as T

TestCase {
    name: "Tray"

    function test_iconPartsSplitsThePrivateThemePath() {
        compare(T.iconParts("image://icon/discord-tray?path=/tmp/.org.chromium.Chromium.abc"), { name: "discord-tray", path: "/tmp/.org.chromium.Chromium.abc" });
        compare(T.iconParts("steam_tray_mono?path=/home/u/icons"), { name: "steam_tray_mono", path: "/home/u/icons" });
    }

    function test_iconPartsIgnoresPlainIcons() {
        compare(T.iconParts("image://icon/arch-update"), null);
        compare(T.iconParts(""), null);
    }

    function test_menuStaysWhereItWasAnchoredWhenItFits() {
        compare(T.placeMenu(100, 80, 200, 150, 1000, 360, 5), { x: 100, y: 80, height: 150, scrolls: false });
    }

    function test_menuIsPulledBackFromTheRightEdgeShadowIncluded() {
        compare(T.placeMenu(900, 80, 200, 150, 1000, 360, 5).x, 795);
    }

    function test_menuWiderThanThePanelStartsAtZero() {
        compare(T.placeMenu(50, 80, 1200, 150, 1000, 360, 5).x, 0);
    }

    function test_tallMenuIsCutToTheRoomBelowAndScrolls() {
        compare(T.placeMenu(0, 80, 200, 500, 1000, 360, 5), { x: 0, y: 80, height: 275, scrolls: true });
    }

    function test_exactFitDoesNotScroll() {
        compare(T.placeMenu(0, 80, 200, 275, 1000, 360, 5).scrolls, false);
    }

    function test_noRoomLeftGivesZeroHeightNotNegative() {
        compare(T.placeMenu(0, 400, 200, 100, 1000, 360, 5), { x: 0, y: 400, height: 0, scrolls: true });
    }

    function test_leftClickOpensTheMenu() {
        compare(T.clickAction("left", false, true), "menu");
        compare(T.clickAction("left", true, true), "menu");
    }

    function test_leftClickActivatesAnItemWithoutAMenu() {
        compare(T.clickAction("left", false, false), "activate");
        compare(T.clickAction("left", true, false), "activate");
    }

    function test_rightClickActivates() {
        compare(T.clickAction("right", false, true), "activate");
        compare(T.clickAction("right", false, false), "activate");
    }

    function test_rightClickOpensTheMenuOfAMenuOnlyItem() {
        compare(T.clickAction("right", true, true), "menu");
        compare(T.clickAction("right", true, false), "activate");
    }

    function test_middleClickIsSecondaryActivate() {
        compare(T.clickAction("middle", true, true), "secondary");
        compare(T.clickAction("middle", false, false), "secondary");
    }

    function test_noEntriesOrOnlySeparatorsIsEmpty() {
        compare(T.hasEntries([]), false);
        compare(T.hasEntries([{ isSeparator: true }, { isSeparator: true }]), false);
    }

    function test_oneRealEntryIsEnough() {
        compare(T.hasEntries([{ isSeparator: true }, { isSeparator: false }]), true);
    }

    function test_iconNameStripsThePrefixPathAndDirectory() {
        compare(T.iconName("image://icon/discord-tray?path=/tmp/.org.chromium.Chromium.abc"), "discord-tray");
        compare(T.iconName("steam_tray_mono?path=/home/u/icons"), "steam_tray_mono");
        compare(T.iconName("image://icon/arch-update"), "arch-update");
        compare(T.iconName("/usr/share/pixmaps/foo.png"), "foo");
        compare(T.iconName("discord"), "discord");
        compare(T.iconName(""), "");
    }

    function test_iconNameOfAPixmapItemIsEmpty() {
        compare(T.iconName("image://qsimage/12345?v=2"), "");
        compare(T.iconName("image://qspixmap/x"), "");
    }

    function test_firstNameSkipsWhatIsMissingOrBlank() {
        compare(T.firstName(["Steam", "Steam client", "Steam Desktop"]), "Steam");
        compare(T.firstName(["", undefined, null, "  ", "Discord"]), "Discord");
        compare(T.firstName(["  Discord  "]), "Discord");
        compare(T.firstName(["", undefined]), "");
        compare(T.firstName([]), "");
    }

    function test_tooltipUsesTheTooltipTitleThenTheName() {
        compare(T.tooltip("Steam", "Steam client", "Friends online: 2"), { title: "Steam client", body: "Friends online: 2" });
        compare(T.tooltip("Steam", "", "Friends online: 2"), { title: "Steam", body: "Friends online: 2" });
        compare(T.tooltip("Steam", undefined, "Friends online: 2"), { title: "Steam", body: "Friends online: 2" });
    }

    function test_tooltipWithoutDescriptionIsJustItsName() {
        compare(T.tooltip("Discord", "", ""), { title: "", body: "Discord" });
        compare(T.tooltip("Discord", "Discord", "Discord"), { title: "", body: "Discord" });
        compare(T.tooltip("", "Discord", ""), { title: "", body: "Discord" });
    }

    function test_tooltipOfAnItemWithNoNameShowsOnlyItsDescription() {
        compare(T.tooltip("", "", "Up to date"), { title: "", body: "Up to date" });
    }

    function test_tooltipOfNothingIsNull() {
        compare(T.tooltip("", "", ""), null);
        compare(T.tooltip("", undefined, undefined), null);
    }

    function test_tooltipDescriptionMarkupIsReadAsText() {
        compare(T.tooltip("App", "", "<b>3</b> updates<br/>pacman &amp; aur").body, "3 updates\npacman & aur");
        compare(T.tooltip("App", "", "a &lt;b&gt; &quot;c&quot; &#39;d&#39;").body, "a <b> \"c\" 'd'");
        compare(T.tooltip("App", "", "  <p>  </p> "), { title: "", body: "App" });
    }
}
