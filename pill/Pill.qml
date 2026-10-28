import QtQuick
import Quickshell
import qs.components
import qs.services
import qs.settings
import qs.theme
import "../lib/pillState.js" as PillState
import "../lib/sidePills.js" as SidePills
import "../lib/wheel.js" as WheelLib

// One monitor's island: a caption box sized from PillState. Hangs from the top edge of its window.
// At rest it shows the date and time at one size; hovered it peeks a little larger, and open it unfolds downward into
// the section panel.
// Beside it, while music plays (left) or an agent works or waits (right), a side pill: a box of its own in the
// same surface, so it shares the island's hover, input mask and animations. The island stays in the surface's
// centre whichever of them show.
Item {
    id: root

    required property string screenName
    required property ShellScreen screen
    readonly property Item inputItem: hitArea
    readonly property Item musicInput: musicBox
    readonly property Item claudeInput: claudeBox
    readonly property bool open: PillControl.openScreen === screenName
    property bool hovered: false
    property real wheelRest: 0

    readonly property string activityId: Activities.current?.id ?? ""
    // Transient activities show as a speech bubble under the pill; every other one takes the pill's body.
    readonly property bool bubbleActivity: PillState.isBubble(activityId)
    readonly property var view: PillState.derive({
        open: root.open,
        fullscreenHidden: Settings.hideInFullscreen && Hypr.hasFullscreen(root.screenName),
        hovered: root.hovered && root.pointerOn === "island",
        hasActivity: activityId !== "" && !bubbleActivity
    })
    readonly property real collapsedWidth: collapsed.restWidth + 2 * Theme.inkWidth
    readonly property var target: PillState.size(view, collapsedWidth, {
        w: collapsed.activityWidth + 2 * Theme.inkWidth,
        id: view.mode === "activity" ? activityId : ""
    }, Theme.pillHeight)

    // The side pills: what each says (null while it has nothing to show), kept while the pill folds away. They
    // show beside the resting island and its short activities, not over a fullscreen window or the panel.
    readonly property var musicNow: SidePills.music({
        playing: Media.playing,
        title: Media.title,
        artist: Media.artist
    })
    readonly property var agentNow: SidePills.agent(Agents.items, Agents.now)
    property var musicKept: ({ title: "", artist: "" })
    property var agentKept: ({ kind: "working", elapsed: -1 })
    readonly property bool sidesAllowed: view.mode !== "hidden" && !panelShown
    // Where they sit: clear of the island's shadow and keyline even when it peeks, and clear of the surface's
    // sides, with room to peek outward. The island's width counted is the face's plus the whole peek, so a hover
    // moves no pill; a pill's own peek grows into the room kept for the island's.
    readonly property real sideEdge: Theme.shadowOffset + Theme.shadowKeyline
    readonly property var sides: SidePills.layout(root.width, baseW + PillState.PEEK_W, Theme.gap / 2 + sideEdge, sideEdge + PillState.PEEK_W / 2, {
        left: musicContent.implicitWidth + 2 * (Theme.pad + Theme.inkWidth),
        right: claudeContent.implicitWidth + 2 * (Theme.pad + Theme.inkWidth)
    })

    // The speech bubble: kept (in `bubbleId`) while it folds away after its activity ended.
    readonly property bool bubbleWanted: bubbleActivity && !open && view.mode !== "hidden"
    property string bubbleId: ""
    readonly property real bubbleFull: bubbleId !== "" ? bubble.height + Theme.shadowOffset + Theme.shadowKeyline : 0
    property real bubbleH: bubbleWanted ? bubbleFull : 0
    readonly property Item bubbleInput: bubbleClip

    // The drawn size, animated: the face's size plus the hover peek, each with its own animation, so that the side
    // pills can sit around the face and leave the peek its room. Everything that draws or takes input follows it.
    readonly property var peek: PillState.peekSize(view)
    property real baseW: target.w
    property real baseH: target.h
    property real peekW: peek.w
    property real peekH: peek.h
    readonly property real drawW: baseW + peekW
    readonly property real drawH: baseH + peekH
    // The panel stays up while it folds back, until the box is down to the pill's height again (the track pop
    // and a peek are taller than the resting island, so the resting height is no yardstick).
    property bool folding: false
    readonly property bool panelShown: open || folding
    // The pill rests on a line midway down the gap above the windows and grows evenly around it: up as well
    // as down when showing a taller face. Past the tallest collapsed face (the panel) it grows
    // down only.
    readonly property real centreY: Theme.pillTop + Theme.pillHeight / 2
    readonly property real boxY: centreY - Math.min(drawH, PillState.TRACK_H + PillState.PEEK_H) / 2

    Behavior on baseW {
        Anim {}
    }
    Behavior on baseH {
        Anim {}
    }
    Behavior on peekW {
        Anim {}
    }
    Behavior on peekH {
        Anim {}
    }
    Behavior on bubbleH {
        Anim {}
    }

    onMusicNowChanged: {
        if (musicNow)
            musicKept = musicNow;
    }
    onAgentNowChanged: {
        if (agentNow)
            agentKept = agentNow;
    }

    onActivityIdChanged: {
        // Not `bubbleActivity`: that binding may not have caught up with the change yet.
        if (PillState.isBubble(activityId))
            bubbleId = activityId;
    }
    // The change signal does not fire for the value a pill is created with.
    Component.onCompleted: {
        if (PillState.isBubble(activityId))
            bubbleId = activityId;
    }
    // Nothing is left to keep once the bubble has folded away.
    onBubbleHChanged: {
        if (bubbleH === 0 && !bubbleWanted)
            bubbleId = "";
    }

    // Opens the panel; on `section` if given, else the one the activity on the island points at.
    function activate(section: string): void {
        if (root.open)
            return;
        const activity = Activities.current;
        const requested = section ? section : Settings.opensActivity && (root.view.mode === "activity" || root.bubbleWanted) ? (activity?.section ?? "") : "";
        PillControl.openOn(root.screenName, requested);
    }

    // The surface has room for the shadow and its paper line on the right and below.
    implicitWidth: PillState.OPEN_W + 2 * (Theme.shadowOffset + Theme.shadowKeyline)
    implicitHeight: centreY - (PillState.TRACK_H + PillState.PEEK_H) / 2 + PillState.OPEN_H + Theme.shadowOffset + Theme.shadowKeyline
    focus: root.open

    Keys.onEscapePressed: PillControl.close()
    Keys.onLeftPressed: PillControl.shift(-1)
    Keys.onRightPressed: PillControl.shift(1)

    // Shown on screen: an unmapped surface or a hidden item sends no hover leave, so `hovered` is dropped here.
    readonly property bool shown: visible && (Window.window?.visible ?? false)
    onShownChanged: {
        if (!shown) {
            hoverTimer.stop();
            hovered = false;
        }
    }

    // The pointer on the island or on a side pill: they hover as one (`hovered`, `pointerIn`), so the panel opens from
    // either, on a pill's own section. Each peeks only while the pointer is on it. (Not readonly: the layout check
    // has no pointer to move.)
    property string pointerOn: SidePills.pointerOn(hover.hovered, musicBox.hovered, claudeBox.hovered)
    readonly property bool pointerIn: pointerOn !== ""
    readonly property string pointerSection: pointerOn === "island" ? "" : pointerOn

    onPointerInChanged: {
        if (pointerIn) {
            closeTimer.stop();
            hoverTimer.restart();
        } else {
            hoverTimer.stop();
            root.hovered = false;
            if (root.open)
                closeTimer.restart();
        }
    }

    onHoveredChanged: {
        if (hovered && Settings.openOnHover)
            activate(pointerSection);
    }

    // A close timer left over from an earlier hover must not close a panel opened again by click or shortcut.
    onDrawHChanged: {
        if (folding && drawH <= target.h + 1)
            folding = false;
    }

    onOpenChanged: {
        // Past the tallest collapsed face (a track pop with its peek): only a panel on its way back counts.
        folding = !open && drawH > PillState.TRACK_H + PillState.PEEK_H + 1;
        closeTimer.stop();
        if (open)
            Brightness.refresh(screenName);
    }

    // The input region: the drawn box plus its shadow, and the gap above it, so the pointer thrown against the
    // screen's top edge still lands on the pill.
    MouseArea {
        id: hitArea

        x: (root.width - root.drawW) / 2
        y: 0
        width: root.drawW + Theme.shadowOffset
        height: root.boxY + root.drawH + Theme.shadowOffset
        visible: root.drawH > 0
        acceptedButtons: Qt.LeftButton

        property real pressY: 0

        onClicked: root.activate("")
        onPressed: mouse => pressY = mouse.y
        // Pulling the pill down opens the panel, like a drawer.
        onPositionChanged: mouse => {
            if (pressed && !root.open && mouse.y - pressY > 12)
                root.activate("");
        }
        onWheel: wheel => {
            if (!Settings.gestures)
                return;
            if (root.open) {
                const d = wheel.angleDelta.x;
                if (d !== 0)
                    PillControl.shift(d < 0 ? 1 : -1);
            } else {
                const r = WheelLib.accumulate(root.wheelRest, wheel.angleDelta.y);
                root.wheelRest = r.rest;
                if (r.steps !== 0)
                    Audio.scroll(r.steps);
            }
        }

        HoverHandler {
            id: hover
        }

        // Files dragged in from another window: the pill opens on the shelf and keeps what is dropped.
        DropArea {
            anchors.fill: parent
            enabled: Settings.sections.indexOf("shelf") !== -1
            keys: ["text/uri-list"]
            onEntered: {
                Shelf.dropping = true;
                closeTimer.stop();
                if (!root.open || PillControl.section !== "shelf")
                    PillControl.openOn(root.screenName, "shelf");
            }
            onExited: {
                Shelf.dropping = false;
                if (root.open)
                    closeTimer.restart();
            }
            onDropped: drop => {
                Shelf.dropping = false;
                if (Shelf.addUrls(drop.urls.map(u => u.toString())) > 0)
                    drop.acceptProposedAction();
            }
        }

        InkBox {
            id: box

            y: root.boxY
            width: root.drawW
            height: root.drawH
            keyline: true
            visible: root.drawH > 0 && !root.panelShown

            Collapsed {
                id: collapsed

                activity: root.view.mode === "activity"
                activityId: root.activityId
                boxWidth: box.width
                boxHeight: box.height
            }
        }

        Panel {
            y: root.boxY
            width: root.drawW
            height: root.drawH
            visible: root.panelShown
            tabsShown: root.open
            screen: root.screen
        }
    }

    // Hangs Theme.gap below the pill, lined up with its left edge, so the tail at the bubble's top left points at
    // the pill's tab (kept inside the window if the bubble is the wider). It unfolds downward from the tail and
    // folds back up; the input item is the revealed part, so the window's mask follows it.
    Item {
        id: bubbleClip

        x: Math.max(0, Math.min((root.width - root.drawW) / 2, root.width - width))
        y: root.boxY + root.drawH + Theme.gap
        width: root.bubbleId !== "" ? bubble.width + Theme.shadowOffset + Theme.shadowKeyline : 0
        height: root.bubbleH
        visible: height > 0
        clip: true

        Bubble {
            id: bubble

            activityId: root.bubbleId
        }

        // A notification has click areas of its own (focus the app, its buttons, dismiss); a click on it never
        // opens the panel.
        MouseArea {
            anchors.fill: parent
            enabled: root.bubbleId !== "notification"
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activate("")
        }
    }

    // The side pills. A click opens the panel on the pill's section (also with the panel not opening on activity).
    SideBox {
        id: musicBox

        wanted: root.musicNow !== null && root.sidesAllowed
        peeking: root.hovered && root.pointerOn === "music"
        boxX: root.sides.leftX
        boxW: root.sides.leftW
        onClicked: PillControl.openOn(root.screenName, "music")

        MusicPill {
            id: musicContent

            model: root.musicKept
            active: musicBox.shown
        }
    }

    SideBox {
        id: claudeBox

        wanted: root.agentNow !== null && root.sidesAllowed
        peeking: root.hovered && root.pointerOn === "agents"
        boxX: root.sides.rightX
        boxW: root.sides.rightW
        onClicked: PillControl.openOn(root.screenName, "agents")

        ClaudePill {
            id: claudeContent

            model: root.agentKept
            active: claudeBox.shown
        }
    }

    Timer {
        id: hoverTimer

        interval: Settings.hoverDelay
        onTriggered: root.hovered = root.pointerIn && root.shown
    }

    Timer {
        id: closeTimer

        interval: 400
        onTriggered: {
            // A tile dragged out of the shelf has left the pill but is still in use.
            if (Shelf.dragging)
                restart();
            else
                PillControl.close();
        }
    }
}
