pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.settings
import "../lib/notifications.js" as NotifLib

// Gutter's own org.freedesktop.Notifications server. Each Notification becomes a record (lib/notifications.js)
// in `history`; the ones that may bubble wait in `queue` and show one at a time through the pill's
// "notification" activity. The service runs the bubble's timer itself, so hovering can pause it, and keeps the
// live Notification objects (by record id) for actions, replies and dismissals. History and do-not-disturb are
// saved to notifications.json. Created at start-up (shell.qml).
// With GUTTER_SMOKE=1 (scripts/smoke.sh, which runs this checkout against the real HOME) or GUTTER_GALLERY=1 (a dev
// instance next to the live shell) the saved file is read but never written.
Singleton {
    id: root

    readonly property bool smoke: Quickshell.env("GUTTER_SMOKE") === "1"
    readonly property bool gallery: Quickshell.env("GUTTER_GALLERY") === "1"
    readonly property bool inert: smoke || gallery
    readonly property string dir: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/gutter`

    // Records, newest first.
    property var history: []
    // Ids of the records waiting to show as a bubble; the first is on screen.
    property var queue: []
    // Transient records: they bubble but are not kept in history.
    property var bubbleOnly: ({})
    // The live Notification objects by record id: the ones whose app can still be reached.
    property var liveById: ({})
    readonly property int currentId: queue.length > 0 ? queue[0] : 0
    readonly property var current: recordFor(currentId)
    readonly property int unread: NotifLib.unreadCount(history)
    property bool dnd: false
    // Server ids of this launch's transient notifications whose bubble has been up; saved, so a reload lets those go
    // and shows the rest (see adopt).
    property var shown: []
    // False when the start-up check found another daemon holding the notification name (the panel says so).
    property bool owned: true
    // How many bubbles (one per monitor) the pointer is on: the timer waits while there is one. Counted, not a
    // flag: with two monitors, the pointer crossing from one bubble to the other would otherwise let the first
    // one's leave undo the second one's enter.
    property int bubbleHovers: 0
    readonly property bool bubbleHovered: bubbleHovers > 0
    // The card whose reply field takes focus when the panel opens; 0 for none.
    property int replyTarget: 0
    property int next: 1
    // The saved state has been read, so new ids cannot collide with saved ones.
    property bool loaded: false
    property bool dirReady: false

    // Names this launch. Quickshell numbers the notifications again from 1 in each launch, and the launch (its
    // instance id) lives across hot reloads, soft or hard, so a saved record is the one of a held-over Notification
    // only when this launch made it.
    function runId(): string {
        return Quickshell.instanceId;
    }

    function recordFor(id: int): var {
        return history.find(h => h.id === id) ?? bubbleOnly[id] ?? null;
    }

    // The record id of a live Notification, or 0.
    function idFor(n: var): int {
        const key = Object.keys(liveById).find(k => liveById[k].id === n.id);
        return key === undefined ? 0 : Number(key);
    }

    function liveAction(id: int, identifier: string): var {
        const live = liveById[id];
        if (!live)
            return null;
        // A QML list<NotificationAction> is array-like, not an Array.
        return Array.from(live.actions).find(a => a.identifier === identifier) ?? null;
    }

    // Lets go of a Notification the record no longer needs: Quickshell keeps tracked ones until they close, so it
    // is expired (the app is told, reason 1). It leaves liveById first, so the closed handler skips it.
    function release(id: int): void {
        const live = liveById[id];
        delete liveById[id];
        try {
            live?.expire();
        } catch (e) {
            console.warn(`gutter: notifications: cannot expire ${id}: ${e}`);
        }
    }

    // A new Notification, or one an app updated in place (replaces_id): the record is built from the object as it
    // is now. An update that left nothing to show keeps the record as it was.
    function ingest(n: var): void {
        const known = idFor(n);
        const rec = NotifLib.fromNotification(n, known || next, Date.now());
        if (!rec)
            return;
        // An update to a record that is already in the history stays there instead of becoming a bubble-only
        // transient: a record kept for a reply (see keepTransient) would be released with its bubble, and the
        // reply with it. So an app turning a normal notification transient in an update also stays in the history.
        if (rec.transient && NotifLib.inHistory(history, known))
            rec.transient = false;
        rec.run = runId();
        let entry = rec;
        // Ids that left the history: replaced by a repeat, or pushed out by the cap.
        let gone = [];
        // The Notification is set live before the record is published, so a card that reads both on the change of
        // the history never sees the record live without it (liveById changes in place, without a signal).
        if (rec.transient) {
            liveById[rec.id] = n;
            bubbleOnly = Object.assign({}, bubbleOnly, { [rec.id]: rec });
        } else {
            const result = NotifLib.remember(history, rec);
            const kept = result.history.map(h => h.id);
            gone = history.filter(h => kept.indexOf(h.id) === -1).map(h => h.id);
            entry = result.history[0];
            liveById[entry.id] = n;
            history = result.history;
        }
        if (entry.id === next)
            next++;
        let q = queue;
        for (const id of gone) {
            release(id);
            q = NotifLib.queueRemove(q, id);
        }
        // An update can change the urgency, which decides whether do-not-disturb lets it bubble.
        q = NotifLib.canBubble(entry, dnd) ? NotifLib.queueAdd(q, entry, dnd) : NotifLib.queueRemove(q, entry.id);
        queue = q;
        if (rec.transient && q.indexOf(entry.id) === -1)
            forgetBubbleOnly(entry.id);
        if (known && entry.id === currentId)
            showCurrent();
    }

    // A Notification the server holds over from before a reload: it takes back the record it had, live again,
    // without a bubble, a new count or an unread mark. A non-transient one with no record of this launch came in
    // just before the reload, before the history was saved (or the save is failing): it is new and shows like one,
    // with the time it was received now, because the original time is unknown to QML. A transient one with no kept
    // record is let go if its bubble had been up (`shown`); otherwise it was waiting in the queue or arrived while
    // the shell reloaded, and shows like a new one.
    function adopt(n: var): void {
        const old = NotifLib.adoptTarget(history, n.id, runId(), n.transient === true);
        if (!old) {
            // A transient one that had its bubble (or lost it to the reload) is not kept; one with nothing to show
            // has no record; `receive` has tracked it, so nothing else would let go of it.
            if (NotifLib.adoptLetGo(n.transient === true, shown, n.id) || !NotifLib.fromNotification(n, 0, 0)) {
                try {
                    n.expire();
                } catch (e) {
                    console.warn(`gutter: notifications: cannot expire: ${e}`);
                }
                return;
            }
            ingest(n);
            return;
        }
        const entry = NotifLib.adoptEntry(old, NotifLib.fromNotification(n, old.id, old.at));
        liveById[old.id] = n;
        history = history.map(h => h === old ? entry : h);
    }

    function receive(n: var): void {
        // Nothing to show (a volume popup, an empty one): not tracked, so Quickshell lets go of it.
        if (!n.lastGeneration && !NotifLib.fromNotification(n, 0, 0))
            return;
        n.tracked = true;
        n.closed.connect(() => root.closed(n));
        for (const changed of [n.summaryChanged, n.bodyChanged, n.expireTimeoutChanged, n.urgencyChanged, n.actionsChanged, n.hintsChanged, n.imageChanged, n.hasInlineReplyChanged, n.residentChanged, n.appIconChanged])
            changed.connect(() => root.ingest(n));
        if (n.lastGeneration)
            adopt(n);
        else
            ingest(n);
    }

    // The app closed it, or Quickshell did after an action, a reply or a dismissal (then the record may be gone).
    function closed(n: var): void {
        const id = idFor(n);
        if (id === 0)
            return;
        delete liveById[id];
        if (history.some(h => h.id === id && h.live))
            history = history.map(h => h.id === id ? Object.assign({}, h, { live: false }) : h);
        leaveQueue(id);
    }

    function forgetBubbleOnly(id: int): void {
        if (bubbleOnly[id] === undefined)
            return;
        const rest = Object.assign({}, bubbleOnly);
        delete rest[id];
        bubbleOnly = rest;
        release(id);
    }

    function leaveQueue(id: int): void {
        queue = NotifLib.queueRemove(queue, id);
        forgetBubbleOnly(id);
    }

    function markRead(id: int): void {
        if (history.some(h => h.id === id && !h.read))
            history = history.map(h => h.id === id ? Object.assign({}, h, { read: true }) : h);
    }

    // Takes the bubble down (whether or not it is the one on screen); the history entry stays, read.
    function takeDown(id: int): void {
        markRead(id);
        leaveQueue(id);
    }

    // A bubble reports the pointer entering (true) or leaving (false) it.
    function hoverBubble(on: bool): void {
        bubbleHovers = NotifLib.hoverCount(bubbleHovers, on);
    }

    // Opening the panel takes the transient bubbles (they have no history card). A reply needs its card, so the
    // record being replied to moves into the history first, still live, read and marked kept. Returns the id of
    // its card, which is the record's own id: ingest keeps an update of a record in the history from becoming
    // a transient, and server ids are unique in a process, so a different id is not expected; the branch below
    // only keeps liveById and the queue consistent if it ever happens.
    function keepTransient(id: int): int {
        const record = bubbleOnly[id];
        if (record === undefined)
            return id;
        const kept = NotifLib.keepTransient(history, record);
        // The live Notification moves to the card's id before the history is published (see ingest), then the history
        // first and bubbleOnly last: the record is found somewhere throughout, so the bubble's record never goes
        // missing in between.
        if (kept.id !== id && liveById[id] !== undefined) {
            liveById[kept.id] = liveById[id];
            delete liveById[id];
        }
        history = kept.history;
        for (const gone of kept.gone) {
            release(gone);
            leaveQueue(gone);
        }
        // The bubble in the queue follows the record to its card's id.
        if (kept.id !== id)
            queue = NotifLib.queueMove(queue, id, kept.id);
        const rest = Object.assign({}, bubbleOnly);
        delete rest[id];
        bubbleOnly = rest;
        return kept.id;
    }

    function dismissBubble(): void {
        if (currentId !== 0)
            takeDown(currentId);
    }

    function dismiss(id: int): void {
        const live = liveById[id];
        delete liveById[id];
        history = NotifLib.removeById(history, id);
        leaveQueue(id);
        live?.dismiss();
    }

    function clear(): void {
        const live = Object.values(liveById);
        history = [];
        queue = [];
        bubbleOnly = ({});
        liveById = ({});
        for (const n of live) {
            try {
                n.dismiss();
            } catch (e) {
                console.warn(`gutter: notifications: cannot dismiss: ${e}`);
            }
        }
    }

    function markAllRead(): void {
        history = NotifLib.markAllRead(history);
    }

    // After an action or a reply the notification goes, unless the app keeps it (resident); a click that reaches
    // something (activate) takes it down even for a resident one.
    function invoke(id: int, identifier: string): void {
        const record = recordFor(id);
        const action = liveAction(id, identifier);
        if (!record || !action)
            return;
        action.invoke();
        if (record.resident)
            markRead(id);
        else
            takeDown(id);
    }

    function reply(id: int, text: string): void {
        const record = recordFor(id);
        const live = liveById[id];
        if (!record || !live)
            return;
        live.sendInlineReply(text);
        if (record.resident)
            markRead(id);
        else
            takeDown(id);
    }

    // The classes of the open windows (see Workspaces.workspaceList for the reading).
    readonly property var windowClasses: Hyprland.toplevels.values.map(t => t.wayland?.appId ?? t.lastIpcObject?.class ?? "")

    // What a click on the notification would do (NotifLib.activation), or null: its default action while it is live
    // and has one, else focusing the app's window while one is open.
    function activationFor(id: int): var {
        const record = recordFor(id);
        if (!record)
            return null;
        const hasAction = record.hasDefault && liveAction(id, "default") !== null;
        return NotifLib.activation(record, liveById[id] !== undefined, hasAction, windowClasses);
    }

    // Whether a click on the notification would reach anything (a live default action, or an open window of the
    // app); the card follows it as the history and the window list change.
    function canActivate(id: int): bool {
        return activationFor(id) !== null;
    }

    // A click on a notification: its default action when it is live and the app has one, else the app's window while
    // the app has one open. A notification with neither (live, or no longer live because the app closed it, the
    // server was turned off or the shell restarted since) does nothing, as one whose record is gone. false, and
    // nothing taken down, when there is nothing to do.
    function activate(id: int): bool {
        const how = activationFor(id);
        if (!how)
            return false;
        if (how.action)
            liveAction(id, "default").invoke();
        else
            Quickshell.execDetached(how.command);
        takeDown(id);
        return true;
    }

    // The panel shows the bodies, so it stays closed while the screen is locked.
    function openReply(id: int): void {
        if (screenLocked)
            return;
        replyTarget = keepTransient(id);
        PillControl.openOn(Hypr.focusedScreenName, "notifications");
    }

    function toggleDnd(): void {
        setDnd(!dnd);
    }

    function setDnd(on: bool): void {
        dnd = on;
    }

    // Shows the head of the queue and starts its timer over. Nothing shows while the screen is locked or the
    // dry-run preview is up: the queue waits (the history and the counts go on), see `resumeAfterLock`.
    function showCurrent(): void {
        if (screenLocked)
            return;
        const record = recordFor(currentId);
        if (!record) {
            // A queued id without a record would block the ones behind it.
            leaveQueue(currentId);
            return;
        }
        if (record.transient)
            shown = NotifLib.shownAdd(shown, record.serverId);
        Activities.show("notification", NotifLib.priority(record), 0, "notifications");
        bubbleTimer.interval = NotifLib.duration(record);
        bubbleTimer.stop();
        if (!bubbleHovered)
            bubbleTimer.start();
    }

    readonly property bool screenLocked: !NotifLib.bubblesAllowed(Lock.locked, Lock.preview)

    // A lock (even a pending one) takes the bubble down and stops its timer; the queue stays.
    onScreenLockedChanged: {
        if (screenLocked) {
            bubbleTimer.stop();
            Activities.hide("notification");
        } else if (PillControl.openScreen !== "") {
            // The panel is open: the held popups do not pop up over it, as if it had opened with them waiting.
            acknowledgeQueue();
        } else {
            resumeAfterLock();
        }
    }

    // The panel has seen what was waiting to bubble: the queue and the transient records go; the history keeps them.
    function acknowledgeQueue(): void {
        queue = [];
        for (const id of Object.keys(bubbleOnly))
            release(Number(id));
        bubbleOnly = ({});
    }

    // The lock ended: what is older than a minute leaves the queue, then the head shows once.
    function resumeAfterLock(): void {
        const plan = NotifLib.resumePlan(queue, currentId, recordFor, Date.now());
        queue = plan.queue;
        for (const id of plan.dropped)
            forgetBubbleOnly(id);
        // A new head shows through onCurrentIdChanged.
        if (plan.showHead)
            showCurrent();
    }

    onCurrentIdChanged: {
        if (currentId === 0) {
            bubbleTimer.stop();
            Activities.hide("notification");
        } else {
            showCurrent();
        }
    }

    onBubbleHoveredChanged: {
        if (bubbleHovered)
            bubbleTimer.stop();
        else if (currentId !== 0 && !screenLocked)
            bubbleTimer.restart();
    }

    // Do-not-disturb holds back what is waiting, except critical ones; the bubble on screen stays.
    onDndChanged: {
        if (dnd) {
            const kept = queue.filter(id => id === currentId || NotifLib.canBubble(recordFor(id) ?? { urgency: 1 }, true));
            const dropped = queue.filter(id => kept.indexOf(id) === -1);
            queue = kept;
            for (const id of dropped)
                forgetBubbleOnly(id);
        }
        scheduleSave();
    }

    onHistoryChanged: scheduleSave()
    onShownChanged: scheduleSave()

    function scheduleSave(): void {
        if (loaded && !inert)
            save.restart();
    }

    function write(): void {
        if (dirReady)
            file.setText(NotifLib.serialize({ dnd, next, items: history, run: runId(), shown }));
        else
            mkdir.running = true;
    }

    // Nothing is saved at exit: Quickshell skips QML destruction on a kill or a reload, so the timer is short.

    Loader {
        active: root.serverOn

        sourceComponent: NotificationServer {
            bodySupported: true
            bodyMarkupSupported: false
            bodyHyperlinksSupported: false
            bodyImagesSupported: false
            actionsSupported: true
            actionIconsSupported: false
            inlineReplySupported: true
            imageSupported: true
            persistenceSupported: true
            keepOnReload: true
            onNotification: n => root.receive(n)
        }
    }

    // The server goes away only after its notifications were expired (the setting turned off), so the apps are told.
    // Settings read first: until then notifications is its default, and a user who turned it off would briefly hold
    // the name. Destroying the server does not free the name, only the process exiting does.
    readonly property bool wanted: Settings.loadedOnce && Settings.notifications && loaded && !inert
    property bool serverOn: false
    // The first failed save was logged.
    property bool saveWarned: false
    // The other owner was logged (once in total, however often it is checked).
    property bool ownerWarned: false
    // The last owner check could not tell who holds the name; `owned` is as the check before it left it.
    property bool ownerUnknown: false

    // The server asks for the name when it starts; a moment later one check says whether another daemon has it.
    onWantedChanged: {
        ownerTimer.stop();
        owned = true;
        ownerUnknown = false;
        if (wanted)
            ownerTimer.start();
        else
            releaseAll();
        serverOn = wanted;
    }

    function checkOwner(): void {
        if (inert || !serverOn || ownerProc.running)
            return;
        try {
            ownerProc.running = true;
        } catch (e) {
            console.warn(`gutter: notifications: cannot check the name owner: ${e}`);
        }
    }

    // The result of the owner check: another daemon holding the name is logged once, and left alone. A check that
    // could not tell (busctl failing) leaves `owned` as it was, so it cannot take the note down while another daemon
    // still holds the name; it is tried again (ownerUnknown) instead.
    function ownerChecked(output: string): void {
        // The setting went off while the check ran.
        if (!serverOn)
            return;
        const state = NotifLib.ownerState(output);
        ownerUnknown = state === "unknown";
        // No busctl: nobody can say, and asking again would not change that; `owned` stays as it is.
        if (state === "unsupported" && !ownerWarned) {
            ownerWarned = true;
            console.warn("gutter: notifications: no busctl, so another daemon holding the name cannot be detected");
        }
        if (ownerUnknown || state === "unsupported")
            return;
        const other = NotifLib.otherOwner(output);
        owned = other === null;
        if (other !== null && !ownerWarned) {
            ownerWarned = true;
            console.warn(`gutter: notifications: ${other} holds the name`);
        }
    }

    function releaseAll(): void {
        const live = Object.values(liveById);
        history = history.map(h => h.live ? Object.assign({}, h, { live: false }) : h);
        liveById = ({});
        queue = [];
        bubbleOnly = ({});
        for (const n of live) {
            try {
                n.expire();
            } catch (e) {
                console.warn(`gutter: notifications: cannot expire: ${e}`);
            }
        }
    }

    // The first owner check, 3 s after the server starts (it has had time to register or queue). It does not run in
    // smoke or gallery instances.
    Timer {
        id: ownerTimer

        interval: 3000
        onTriggered: root.checkOwner()
    }

    // While another daemon holds the name the check repeats: our server queues for the name and takes it over when
    // the other one exits, which `owned` (and the panel's note) must follow. Stops once we own it. A check that could
    // not tell repeats too, so one failure at start-up does not leave another daemon unseen.
    Timer {
        interval: 5000
        repeat: true
        running: root.serverOn && (!root.owned || root.ownerUnknown) && !root.inert
        onTriggered: root.checkOwner()
    }

    Process {
        id: ownerProc

        command: NotifLib.ownerCommand()
        stdout: StdioCollector {
            onStreamFinished: root.ownerChecked(text)
        }
    }

    Timer {
        id: bubbleTimer

        onTriggered: root.dismissBubble()
    }

    // Opening the panel acknowledges the bubble; what was waiting stays in history, unread. Not under a lock or the
    // preview: nobody saw the held popups then; at unlock they show (the fresh ones), or are acknowledged if the panel
    // is open.
    Connections {
        target: PillControl

        function onOpenScreenChanged(): void {
            if (PillControl.openScreen === "" || root.screenLocked)
                return;
            root.acknowledgeQueue();
        }
    }

    FileView {
        id: file

        path: `${root.dir}/notifications.json`
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onLoaded: {
            const parsed = NotifLib.parseState(text());
            if (parsed) {
                root.history = parsed.items;
                root.dnd = parsed.dnd;
                root.next = parsed.next;
                root.shown = NotifLib.shownFor(parsed.shown, root.runId());
            } else {
                console.warn("gutter: notifications.json is not usable, starting empty");
            }
            root.dirReady = true;
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
        onSaveFailed: err => {
            if (root.saveWarned)
                return;
            root.saveWarned = true;
            console.warn(`gutter: notifications: cannot save the history (${err})`);
        }
    }

    // FileView does not create parent directories.
    Process {
        id: mkdir

        command: ["mkdir", "-p", "--", root.dir]
        onExited: code => {
            if (code === 0) {
                root.dirReady = true;
                root.write();
            } else {
                console.warn(`gutter: notifications: cannot create ${root.dir}, the history is not saved`);
            }
        }
    }

    Timer {
        id: save

        interval: 200
        onTriggered: root.write()
    }
}
