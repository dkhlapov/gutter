import QtQuick
import QtTest
import "../lib/notifications.js" as N

TestCase {
    name: "Notifications"

    // A Notification-shaped object, as Quickshell hands it over.
    function note(over) {
        return Object.assign({ id: 7, appName: "Discord", appIcon: "discord", summary: "Hi", body: "", urgency: 1, expireTimeout: -1, transient: false, resident: false, desktopEntry: "discord", image: "", hasInlineReply: false, inlineReplyPlaceholder: "", hints: {}, actions: [] }, over);
    }

    // A record as fromNotification makes it; `id` is Gutter's own.
    function rec(over) {
        return Object.assign(N.fromNotification(note({}), 1, 1000), over);
    }

    function test_fromNotificationBuildsRecord() {
        const r = N.fromNotification(note({ id: 42, appName: "Telegram", appIcon: "telegram", summary: "Anna", body: "hello", desktopEntry: "org.telegram.desktop", expireTimeout: 5000, urgency: 2, transient: true, resident: true }), 3, 123456);
        compare(r.id, 3);
        compare(r.serverId, 42);
        compare(r.appName, "Telegram");
        compare(r.icon, "telegram");
        compare(r.desktopEntry, "org.telegram.desktop");
        compare(r.summary, "Anna");
        compare(r.body, "hello");
        compare(r.urgency, 2);
        compare(r.timeoutMs, 5000);
        compare(r.transient, true);
        compare(r.resident, true);
        compare(r.at, 123456);
        compare(r.count, 1);
        compare(r.read, false);
        compare(r.run, "");
        compare(r.live, true);
        compare(r.image, "");
        compare(r.actions, []);
        compare(r.hasDefault, false);
        compare(r.canReply, false);
    }

    function test_timeoutIsMilliseconds() {
        compare(N.fromNotification(note({ expireTimeout: 3000 }), 1, 0).timeoutMs, 3000);
        compare(N.fromNotification(note({ expireTimeout: -1 }), 1, 0).timeoutMs, 0);
        compare(N.fromNotification(note({ expireTimeout: 0 }), 1, 0).timeoutMs, 0);
    }

    function test_fromNotificationClipsAndCleans() {
        compare(N.fromNotification(note({ body: "<b>hi</b> &amp; x" }), 1, 0).body, "hi & x");
        compare(N.fromNotification(note({ body: "a".repeat(20000) }), 1, 0).body.length, N.MAX_BODY);
    }

    function test_fromNotificationOddInputs() {
        compare(N.fromNotification(note({ image: 42 }), 1, 0).image, "");
        compare(N.fromNotification(note({ urgency: 7 }), 1, 0).urgency, 1);
        compare(N.fromNotification(note({ summary: "", body: "text" }), 1, 0).body, "text");
        compare(N.fromNotification(note({ summary: "", body: "" }), 1, 0), null);
        compare(N.fromNotification(note({ summary: " ", body: "<b></b>" }), 1, 0), null);
        compare(N.fromNotification(note({ hints: { "x-canonical-private-synchronous": "volume" } }), 1, 0), null);
        compare(N.fromNotification(note({ hints: { synchronous: "brightness" } }), 1, 0), null);
        verify(N.fromNotification(note({ hints: { synchronous: 3 } }), 1, 0) !== null);
        verify(N.fromNotification(note({ hints: undefined }), 1, 0) !== null);

        const r = N.fromNotification(note({ hasInlineReply: true, inlineReplyPlaceholder: "Reply", actions: [{ identifier: "default", text: "Open" }, { identifier: "inline-reply", text: "Reply" }, { identifier: "mute", text: "Mute" }] }), 1, 0);
        compare(r.hasDefault, true);
        compare(r.canReply, true);
        compare(r.replyPlaceholder, "Reply");
        compare(r.actions, [{ identifier: "mute", text: "Mute" }]);
    }

    // Quickshell reports a path or theme name as image://icon/<it>; a record holds the plain form.
    function test_fromNotificationNormalisesImage() {
        compare(N.fromNotification(note({ image: "image://icon//tmp/a.png" }), 1, 0).image, "/tmp/a.png");
        compare(N.fromNotification(note({ image: "image://icon/firefox" }), 1, 0).image, "firefox");
        compare(N.fromNotification(note({ image: "file:///tmp/a.png" }), 1, 0).image, "file:///tmp/a.png");
        compare(N.fromNotification(note({ image: "image://qsimage/7/1" }), 1, 0).image, "");
    }

    // A QML list<NotificationAction> is not an Array.
    function test_fromNotificationReadsListActions() {
        const list = { length: 3, 0: { identifier: "default", text: "Open" }, 1: { identifier: "mute", text: "Mute" }, 2: { identifier: "inline-reply", text: "Reply" } };
        const r = N.fromNotification(note({ actions: list, hasInlineReply: true }), 1, 0);
        compare(r.actions, [{ identifier: "mute", text: "Mute" }]);
        compare(r.hasDefault, true);
        compare(N.duration(r), 15000);
        compare(N.fromNotification(note({ actions: undefined }), 1, 0).actions, []);
        compare(N.fromNotification(note({ actions: 5 }), 1, 0).actions, []);
    }

    // A "<" that starts no tag stays; the one right before a tag does too.
    function test_plainStripsTags() {
        compare(N.plain("a<b>c</b>d"), "acd");
        compare(N.plain("1 < 2 and <i>x</i>"), "1 < 2 and x");
        compare(N.plain("<<b>x"), "<x");
    }

    function test_fromNotificationIsFastOnHugeMarkup() {
        const t0 = Date.now();
        const r = N.fromNotification(note({ summary: "<".repeat(100000), body: "<".repeat(100000) }), 1, 0);
        verify(Date.now() - t0 < 500);
        verify(r.body.length <= N.MAX_BODY);
        const b = N.fromNotification(note({ body: "<".repeat(100000) + "x".repeat(100) }), 1, 0);
        verify(b === null || b.body.length <= N.MAX_BODY);
    }

    function test_fromNotificationClipsStoredText() {
        const many = [];
        for (let i = 0; i < 50; i++)
            many.push({ identifier: "id" + i, text: "t".repeat(5000) });
        const r = N.fromNotification(note({ actions: many, appIcon: "i".repeat(9000), desktopEntry: "d".repeat(9000), inlineReplyPlaceholder: "p".repeat(9000), image: "/" + "m".repeat(9000) }), 1, 0);
        compare(r.actions.length, 10);
        compare(r.actions[0].identifier, "id0");
        compare(r.actions[0].text.length, 200);
        compare(r.icon.length, 4096);
        compare(r.desktopEntry.length, 200);
        compare(r.replyPlaceholder.length, 200);
        compare(r.image.length, 4096);
    }

    function test_fromNotificationClipsNames() {
        const r = N.fromNotification(note({ summary: "s".repeat(5000), appName: "a".repeat(5000) }), 1, 0);
        compare(r.summary.length, 200);
        compare(r.appName.length, 200);
    }

    function test_canBubbleHonoursDnd() {
        compare(N.canBubble(rec({ urgency: 1 }), false), true);
        compare(N.canBubble(rec({ urgency: 1 }), true), false);
        compare(N.canBubble(rec({ urgency: 0 }), true), false);
        compare(N.canBubble(rec({ urgency: 2 }), true), true);
    }

    function test_durationRules() {
        compare(N.duration(rec({ urgency: 2 })), 15000);
        compare(N.duration(rec({ actions: [{ identifier: "a", text: "A" }] })), 15000);
        compare(N.duration(rec({ canReply: true })), 15000);
        compare(N.duration(rec({ timeoutMs: 2000 })), 4000);
        compare(N.duration(rec({ timeoutMs: 5000 })), 5000);
        compare(N.duration(rec({ timeoutMs: 20000 })), 9000);
        compare(N.duration(rec({ timeoutMs: 0 })), 6000);
    }

    function test_priorityByUrgency() {
        compare(N.priority(rec({ urgency: 0 })), 40);
        compare(N.priority(rec({ urgency: 1 })), 70);
        compare(N.priority(rec({ urgency: 2 })), 88);
    }

    function test_rememberCollapsesRepeats() {
        let h = N.remember([], rec({ id: 1, serverId: 1, summary: "a", live: false }), 100).history;
        h = N.remember(h, rec({ id: 2, serverId: 2, summary: "b", live: false }), 100).history;
        const r = N.remember(h, rec({ id: 3, serverId: 3, summary: "a" }), 100);
        compare(r.history.map(e => e.id), [3, 2]);
        compare(r.history[0].count, 2);
        compare(r.replaced, [1]);
    }

    function test_rememberUpdatesLiveRecordInPlace() {
        let h = N.remember([], rec({ id: 1, serverId: 9, summary: "dl 0%", at: 10 }), 100).history;
        h = N.remember(h, rec({ id: 2, serverId: 5, summary: "other" }), 100).history;
        let last;
        for (let i = 1; i <= 50; i++) {
            last = N.remember(h, rec({ id: 100 + i, serverId: 9, summary: "dl " + i + "%", at: 10 + i }), 100);
            h = last.history;
            compare(last.replaced, []);
        }
        compare(h.length, 2);
        compare(h[0].serverId, 9);
        const e = h[0];
        compare(e.id, 1);
        compare(e.count, 1);
        compare(e.summary, "dl 50%");
        compare(e.at, 60);
        compare(e.read, false);
    }

    function test_rememberUpdateKeepsCountAndUnreads() {
        let h = [rec({ id: 1, serverId: 9, count: 3, read: true })];
        h = N.remember(h, rec({ id: 2, serverId: 9, summary: "new" }), 100).history;
        compare(h[0].id, 1);
        compare(h[0].count, 3);
        compare(h[0].read, false);
    }

    function test_rememberSkipsTransient() {
        const h = [rec({ id: 1, summary: "a", serverId: 1 })];
        const r = N.remember(h, rec({ id: 2, serverId: 2, summary: "a", transient: true }), 100);
        compare(r.history, h);
        compare(r.replaced, []);
    }

    function test_rememberCapsAtMax() {
        let h = [];
        for (let i = 1; i <= 101; i++)
            h = N.remember(h, rec({ id: i, serverId: i, summary: "s" + i, live: false }), N.HISTORY_MAX).history;
        compare(h.length, 100);
        compare(h[0].id, 101);
        compare(h[99].id, 2);
    }

    function test_queueAddRespectsDndAndDuplicates() {
        const a = rec({ id: 1 });
        const crit = rec({ id: 2, urgency: 2 });
        compare(N.queueAdd([], a, false), [1]);
        compare(N.queueAdd([1], a, false), [1]);
        compare(N.queueAdd([1], crit, false), [1, 2]);
        compare(N.queueAdd([], a, true), []);
        compare(N.queueAdd([1], crit, true), [1, 2]);
    }

    function test_queueRemove() {
        compare(N.queueRemove([1, 2, 3], 2), [1, 3]);
        compare(N.queueRemove([1], 5), [1]);
    }

    function test_unreadAndMarkAllRead() {
        const h = [rec({ id: 1, read: false }), rec({ id: 2, read: true }), rec({ id: 3, read: false })];
        compare(N.unreadCount(h), 2);
        const r = N.markAllRead(h);
        compare(N.unreadCount(r), 0);
        compare(r.length, 3);
        compare(N.unreadCount(h), 2);
    }

    // The section's "N new": the ids it counted so far that are still in the history, plus the unread ones it has not.
    function test_newIds() {
        const h = [rec({ id: 3, read: false }), rec({ id: 2, read: true }), rec({ id: 1, read: true })];
        compare(N.newIds([], h), [3]);
        compare(N.newIds([1, 2], h), [1, 2, 3]);
        compare(N.newIds([1, 2, 3], N.markAllRead(h)), [1, 2, 3]);
        compare(N.newIds([1, 2, 3], N.removeById(N.markAllRead(h), 2)), [1, 3]);
        compare(N.newIds([1, 3], N.removeById(h, 3)), [1]);
        compare(N.newIds([3], h), [3]);
        compare(N.newIds([5], []), []);
        // A repeat replaces the older entry under a new id; an app updating its notification keeps the id.
        const seen = N.markAllRead([rec({ id: 3, serverId: 30, summary: "c" }), rec({ id: 2, serverId: 20, summary: "b" })]);
        compare(N.newIds([3], N.remember(seen, rec({ id: 4, serverId: 40, summary: "c" })).history), [4]);
        compare(N.newIds([3], N.remember(seen, rec({ id: 4, serverId: 40, summary: "d" })).history), [3, 4]);
        compare(N.newIds([3], N.remember(seen, rec({ id: 4, serverId: 30, summary: "c" })).history), [3]);
    }

    // The lock screen's counts: the unread records per app (the same ones unreadCount counts), the app's name and the
    // number only.
    function test_countsByApp() {
        compare(N.countsByApp([]), []);
        const h = [rec({ id: 1, appName: "Mail" }), rec({ id: 2, appName: "Chat" }), rec({ id: 3, appName: "Mail" }), rec({ id: 4, appName: "Mail" }), rec({ id: 5, appName: "Mail", read: true })];
        compare(N.countsByApp(h), [{ app: "Mail", count: 3, nameless: false }, { app: "Chat", count: 1, nameless: false }]);
        let total = 0;
        for (const c of N.countsByApp(h))
            total += c.count;
        compare(total, N.unreadCount(h));
        compare(N.countsByApp([rec({ id: 1, read: true })]), []);
    }

    function test_countsByAppNoNameIsOther() {
        compare(N.countsByApp([rec({ id: 1, appName: "" }), rec({ id: 2, appName: "" }), rec({ id: 3, appName: "Chat" })]), [{ app: "Other", count: 2, nameless: true }, { app: "Chat", count: 1, nameless: false }]);
        compare(N.countsByApp([rec({ id: 1, appName: undefined })]), [{ app: "Other", count: 1, nameless: true }]);
    }

    // Records with no app name are not an app called "Other": the two stay apart, both labelled "Other".
    function test_countsByAppNamelessIsNotAnAppCalledOther() {
        const h = [rec({ id: 1, appName: "" }), rec({ id: 2, appName: "Other" }), rec({ id: 3, appName: "Other" }), rec({ id: 4, appName: "Other" })];
        compare(N.countsByApp(h), [{ app: "Other", count: 3, nameless: false }, { app: "Other", count: 1, nameless: true }]);
        // Equal counts: the real app first, the same on every call.
        const tie = [rec({ id: 1, appName: "" }), rec({ id: 2, appName: "Other" })];
        compare(N.countsByApp(tie), [{ app: "Other", count: 1, nameless: false }, { app: "Other", count: 1, nameless: true }]);
        compare(N.countsByApp(tie.slice().reverse()), N.countsByApp(tie));
        // The nameless entry is capped like any other.
        const many = [];
        for (let i = 0; i < 6; i++)
            many.push(rec({ id: i + 1, appName: "app" + i }), rec({ id: i + 20, appName: "app" + i }));
        many.push(rec({ id: 40, appName: "" }));
        const counts = N.countsByApp(many);
        compare(counts.length, 6);
        verify(counts.every(c => !c.nameless));
    }

    function test_countsByAppSortsByCountThenName() {
        const h = [rec({ id: 1, appName: "b" }), rec({ id: 2, appName: "a" }), rec({ id: 3, appName: "c" }), rec({ id: 4, appName: "c" })];
        compare(N.countsByApp(h).map(c => c.app), ["c", "a", "b"]);
    }

    function test_countsByAppCapsAtSix() {
        const h = [];
        for (let i = 0; i < 7; i++)
            h.push(rec({ id: i + 1, appName: "app" + i }));
        h.push(rec({ id: 20, appName: "app6" }));
        const counts = N.countsByApp(h);
        compare(counts.length, 6);
        compare(counts[0], { app: "app6", count: 2, nameless: false });
    }

    function test_countsByAppOddNames() {
        compare(N.countsByApp([rec({ id: 1, appName: "__proto__" }), rec({ id: 2, appName: "constructor" })]).map(c => c.app), ["__proto__", "constructor"]);
        // Nothing an app calls itself can land on the nameless entry (which sorts first here: "Other" before "_").
        compare(N.countsByApp([rec({ id: 1, appName: "__proto__" }), rec({ id: 2, appName: "" })]).map(c => c.nameless), [true, false]);
    }

    // Titles and bodies never reach the lock screen: an entry has the app and the number, nothing else.
    function test_countsByAppEntryHasNoText() {
        const c = N.countsByApp([rec({ id: 1, appName: "Mail", summary: "secret", body: "secret too" })]);
        compare(Object.keys(c[0]).sort(), ["app", "count", "nameless"]);
    }

    function test_removeById() {
        const h = [rec({ id: 1 }), rec({ id: 2 })];
        compare(N.removeById(h, 1).map(e => e.id), [2]);
        compare(N.removeById(h, 9).length, 2);
    }

    function test_stateRoundTrip() {
        const items = [rec({ id: 5, summary: "a", image: "/tmp/a.png", count: 2, actions: [{ identifier: "x", text: "X" }], hasDefault: true }), rec({ id: 4, summary: "b" })];
        const s = N.parseState(N.serialize({ dnd: true, next: 6, items }));
        compare(s.dnd, true);
        compare(s.next, 6);
        compare(s.items.length, 2);
        compare(s.items[0].id, 5);
        compare(s.items[0].summary, "a");
        compare(s.items[0].image, "/tmp/a.png");
        compare(s.items[0].count, 2);
        compare(s.items[0].actions, [{ identifier: "x", text: "X" }]);
        compare(s.items[0].hasDefault, true);
        compare(s.items[1].id, 4);
        for (const e of s.items) {
            compare(e.live, false);
            compare(e.read, true);
        }
        compare(JSON.parse(N.serialize({ dnd: false, next: 6, items })).version, 1);
    }

    function test_serializeDropsMemoryImages() {
        const items = [rec({ id: 1, image: "image://qsimage/7/1" }), rec({ id: 2, image: "/tmp/a.png" }), rec({ id: 3, image: "file:///tmp/a.png" }), rec({ id: 4, image: "firefox" })];
        const out = JSON.parse(N.serialize({ dnd: false, next: 5, items })).items;
        compare(out.map(i => i.image), ["", "/tmp/a.png", "file:///tmp/a.png", ""]);
    }

    function test_parseStateRejectsBadFiles() {
        compare(N.parseState(""), null);
        compare(N.parseState("not json"), null);
        compare(N.parseState("[]"), null);
        compare(N.parseState("null"), null);
        compare(N.parseState('{"version":2,"items":[]}'), null);
        compare(N.parseState('{"items":[]}'), null);
    }

    function test_parseStateCleansItems() {
        const good = { id: 3, appName: "A", summary: "s" };
        const s = N.parseState(JSON.stringify({ version: 1, dnd: "yes", next: 2, items: [good, 5, null, "x", [], { id: 9, summary: "no app" }, { id: 4, appName: "B", urgency: 9, count: -2, image: 5, actions: "no" }] }));
        compare(s.dnd, false);
        compare(s.items.map(i => i.appName), ["A", "B"]);
        verify(s.next > 4);
        const b = s.items[1];
        compare(b.urgency, 1);
        compare(b.count, 1);
        compare(b.image, "");
        compare(b.actions, []);
        compare(b.summary, "");
        compare(b.live, false);

        const many = [];
        for (let i = 1; i <= 5000; i++)
            many.push({ id: i, appName: "A", summary: "s" + i });
        const m = N.parseState(JSON.stringify({ version: 1, next: 1, items: many }));
        compare(m.items.length, 100);
        verify(m.next > 100);
    }

    function test_parseStateClipsLongFields() {
        const s = N.parseState(JSON.stringify({ version: 1, next: 1, items: [{ id: 1, appName: "a".repeat(5000), summary: "s".repeat(5000), body: "b".repeat(50000) }] }));
        compare(s.items[0].appName.length, 200);
        compare(s.items[0].summary.length, 200);
        compare(s.items[0].body.length, N.MAX_BODY);
    }

    function test_parseStateClipsStoredText() {
        const many = [];
        for (let i = 0; i < 50; i++)
            many.push({ identifier: "id" + i, text: "t".repeat(5000) });
        const s = N.parseState(JSON.stringify({ version: 1, next: 1, items: [{ id: 1, appName: "A", icon: "i".repeat(9000), desktopEntry: "d".repeat(9000), replyPlaceholder: "p".repeat(9000), image: "/" + "m".repeat(9000), actions: many }] }));
        const i = s.items[0];
        compare(i.actions.length, 10);
        compare(i.actions[0].identifier, "id0");
        compare(i.actions[0].text.length, 200);
        compare(i.icon.length, 4096);
        compare(i.desktopEntry.length, 200);
        compare(i.replyPlaceholder.length, 200);
        compare(i.image.length, 4096);
    }

    function test_parseStateRejectsAbsurdNumbers() {
        const s = N.parseState('{"version":1,"next":1e300,"items":[{"appName":"A","id":1e300},{"appName":"B","id":3}]}');
        verify(s.next > 3);
        verify(s.next < 1e9);
        const ids = s.items.map(i => i.id);
        compare(new Set(ids).size, 2);
        for (const id of ids)
            verify(id < s.next);
    }

    function test_parseStateFixesDuplicateIds() {
        const s = N.parseState(JSON.stringify({ version: 1, next: 5, items: [{ appName: "A", id: 4 }, { appName: "B", id: 4 }, { appName: "C", id: 2 }] }));
        compare(s.items.map(i => i.appName), ["A", "B", "C"]);
        compare(s.items[0].id, 4);
        compare(s.items[2].id, 2);
        compare(new Set(s.items.map(i => i.id)).size, 3);
        for (const i of s.items)
            verify(i.id < s.next);
    }

    function test_parseStateGivesEveryItemAnId() {
        const s = N.parseState(JSON.stringify({ version: 1, next: 1, items: [{ appName: "A", id: 8 }, { appName: "B" }] }));
        const ids = s.items.map(i => i.id);
        compare(new Set(ids).size, 2);
        for (const id of ids)
            verify(id < s.next);
    }

    function test_iconSourcePaths() {
        compare(N.iconSource(rec({ icon: "/tmp/a.png" })).file, "file:///tmp/a.png");
        compare(N.iconSource(rec({ icon: "file:///tmp/a.png" })).file, "file:///tmp/a.png");
        compare(N.iconSource(rec({ icon: "discord" })).name, "discord");
        compare(N.iconSource(rec({ icon: "discord" })).file, "");
        compare(N.iconSource(rec({ icon: "", desktopEntry: "org.telegram.desktop" })).name, "org.telegram.desktop");
        compare(N.iconSource(rec({ icon: "", desktopEntry: "", appName: "Firefox" })).name, "firefox");
        compare(N.iconSource(rec({ icon: "x", image: "/p.png" })).file, "file:///p.png");
        compare(N.iconSource(rec({ icon: "x", image: "firefox" })).name, "firefox");
    }

    function test_iconSourceNeverLoadsMemoryImages() {
        const s = N.iconSource(rec({ icon: "x", image: "image://qsimage/7/1" }));
        compare(s.file, "");
        compare(s.name, "x");
    }

    function test_fromNotificationDropsActionsWithLongIdentifiers() {
        const n = note({ actions: [{ identifier: "x".repeat(500), text: "Long" }, { identifier: "ok", text: "Fine" }] });
        compare(N.fromNotification(n, 1, 0).actions.map(a => a.identifier), ["ok"]);
    }

    function test_ago() {
        compare(N.ago(1000, 1000), "now");
        compare(N.ago(0, 59000), "now");
        compare(N.ago(0, 3 * 60000 + 5000), "3 min");
        compare(N.ago(0, 2 * 3600000 + 60000), "2 h");
        compare(N.ago(0, 4 * 86400000 + 3600000), "4 d");
        compare(N.ago(5000, 1000), "now");
    }

    function test_adoptTargetMatchesServerIdOfThisRun() {
        const h = [rec({ id: 1, serverId: 7, run: "a", live: false }), rec({ id: 2, serverId: 8, run: "a", live: false })];
        compare(N.adoptTarget(h, 7, "a").id, 1);
        compare(N.adoptTarget(h, 8, "a").id, 2);
        compare(N.adoptTarget(h, 9, "a"), undefined);
    }

    function test_adoptTargetSkipsLiveRecords() {
        const h = [rec({ id: 1, serverId: 7, run: "a", live: true })];
        compare(N.adoptTarget(h, 7, "a"), undefined);
    }

    // The server numbers again from 1 after a restart: a record of an earlier launch is not the Notification's.
    function test_adoptTargetIgnoresEarlierRuns() {
        const h = [rec({ id: 1, serverId: 7, summary: "Old", run: "a", live: false }), rec({ id: 2, serverId: 7, summary: "Mine", run: "b", live: false })];
        compare(N.adoptTarget(h, 7, "b").id, 2);
        compare(N.adoptTarget(h, 7, "c"), undefined);
        // A record saved before runs existed has none.
        compare(N.adoptTarget([rec({ id: 1, serverId: 7, run: "", live: false })], 7, "b"), undefined);
    }

    function test_adoptEntryKeepsCountReadAndRun() {
        const old = rec({ id: 4, serverId: 7, summary: "Old", at: 5000, count: 3, read: true, run: "a", live: false });
        const entry = N.adoptEntry(old, N.fromNotification(note({ id: 7, summary: "New" }), old.id, old.at));
        compare(entry.summary, "New");
        compare(entry.id, 4);
        compare(entry.at, 5000);
        compare(entry.count, 3);
        compare(entry.read, true);
        compare(entry.run, "a");
        compare(entry.live, true);
    }

    // An update that emptied the Notification shows nothing: the old record is live again as it was.
    function test_adoptEntryWithoutFreshRecordRevivesTheOldOne() {
        const old = rec({ id: 4, serverId: 7, summary: "Old", count: 2, read: false, run: "a", live: false });
        const entry = N.adoptEntry(old, N.fromNotification(note({ id: 7, summary: "", body: "" }), old.id, old.at));
        compare(entry.live, true);
        compare(entry.summary, "Old");
        compare(entry.id, 4);
        compare(entry.count, 2);
        compare(entry.read, false);
        compare(entry.run, "a");
        compare(old.live, false);
    }

    function test_parseStateKeepsTheRun() {
        const saved = JSON.parse(N.serialize({ dnd: false, next: 2, items: [rec({ id: 1, run: "a" })] }));
        compare(saved.items[0].run, "a");
        compare(N.parseState(JSON.stringify(saved)).items[0].run, "a");
        delete saved.items[0].run;
        compare(N.parseState(JSON.stringify(saved)).items[0].run, "");
    }

    function test_parseStateClipsOrDropsABadRun() {
        const saved = JSON.parse(N.serialize({ dnd: false, next: 2, items: [rec({ id: 1, run: "a" })] }));
        saved.items[0].run = 5;
        compare(N.parseState(JSON.stringify(saved)).items[0].run, "");
        saved.items[0].run = "r".repeat(N.MAX_NAME + 50);
        compare(N.parseState(JSON.stringify(saved)).items[0].run, "r".repeat(N.MAX_NAME));
    }

    function test_otherOwnerSelf() {
        compare(N.otherOwner("self=2046990\nowner=2046990\ncmd=qs -c gutter \n"), null);
    }

    function test_otherOwnerNamesTheHolder() {
        compare(N.otherOwner("self=2046990\nowner=88\ncmd=dunst \n"), "dunst");
        compare(N.otherOwner("self=2046990\nowner=1579\ncmd=/usr/bin/qs -c something -n -d\n"), "/usr/bin/qs -c something -n -d");
        // No readable command line: the pid says which.
        compare(N.otherOwner("self=2046990\nowner=88\ncmd=\n"), "pid 88");
        compare(N.otherOwner("self=2046990\nowner=88\n"), "pid 88");
    }

    function test_otherOwnerNone() {
        compare(N.otherOwner("self=2046990\n"), null);
    }

    function test_otherOwnerUnknown() {
        compare(N.otherOwner(""), null);
        compare(N.otherOwner("owner=1579\ncmd=dunst\n"), null);
    }

    function test_ownerCommand() {
        const c = N.ownerCommand();
        compare(c.slice(0, 2), ["sh", "-c"]);
        // Without busctl the output is empty, which otherOwner() takes as no other holder.
        verify(c[2].startsWith("command -v busctl >/dev/null || exit 0; echo self=$PPID"));
        verify(c[2].indexOf("busctl --user status org.freedesktop.Notifications") !== -1);
        verify(c[2].indexOf("/proc/") !== -1);
    }

    // The argument is Lua source, so a backslash of the regex is doubled in it.
    function test_focusCommandEscapes() {
        compare(N.focusCommand(rec({ desktopEntry: "org.telegram.desktop" })), ["hyprctl", "dispatch", 'hl.dsp.focus({ window = "class:(?i)^org\\\\.telegram\\\\.desktop$" })']);
        compare(N.focusCommand(rec({ desktopEntry: "", appName: "Zen" }))[2], 'hl.dsp.focus({ window = "class:(?i)^Zen$" })');
        compare(N.focusCommand(rec({ desktopEntry: 'a"b', appName: "x" }))[2], 'hl.dsp.focus({ window = "class:(?i)^a\\"b$" })');
        compare(N.focusCommand(rec({ desktopEntry: "", appName: "" })), null);
    }

    // A live notification is reached by its default action, else by focusing its app's window; the focus, live or
    // not, needs a window of the app's class to be open, or the click reaches nothing.
    function test_activation() {
        const named = rec({ desktopEntry: "org.telegram.desktop" });
        const open = ["org.telegram.desktop"];
        compare(N.activation(named, true, true, []), { action: true });
        compare(N.activation(named, true, true, open), { action: true });
        compare(N.activation(named, true, false, open), { command: N.focusCommand(named) });
        // No window of the app to focus: nothing to do, though the notification is live.
        compare(N.activation(named, true, false, []), null);
        compare(N.activation(named, true, false, ["kitty"]), null);
        compare(N.activation(named, true, false), null);
        compare(N.activation(rec({ desktopEntry: "", appName: "" }), true, false, [""]), null);
        compare(N.activation(rec({ desktopEntry: "", appName: "" }), true, true, []), { action: true });
        // The action counts only while the notification is live: otherwise it is the window rule alone.
        compare(N.activation(named, false, true, []), null);
        compare(N.activation(named, false, true, open), { command: N.focusCommand(named) });
        // A live record is held to the same window rule: the class has to be the app's whole name.
        const plain = rec({ desktopEntry: "", appName: "Firefox" });
        compare(N.activation(plain, true, false, ["firefox"]), { command: N.focusCommand(plain) });
        compare(N.activation(plain, true, false, ["firefox-esr"]), null);
    }

    function test_activationOfARecordThatIsNotLive() {
        const named = rec({ desktopEntry: "org.telegram.desktop", appName: "Telegram" });
        const open = ["kitty", "org.telegram.desktop"];
        compare(N.activation(named, false, false, open), { command: N.focusCommand(named) });
        compare(N.activation(named, false, false, ["kitty"]), null);
        compare(N.activation(named, false, false, []), null);
        // The focus command matches the class without regard to case, so the check does too.
        compare(N.activation(named, false, false, ["ORG.Telegram.Desktop"]), { command: N.focusCommand(named) });
        // The desktop entry names the window when there is one, not the app's display name.
        compare(N.activation(named, false, false, ["Telegram"]), null);
        const plain = rec({ desktopEntry: "", appName: "Firefox" });
        compare(N.activation(plain, false, false, ["firefox"]), { command: N.focusCommand(plain) });
        // A class that only contains the name, or is not text, is not the window.
        compare(N.activation(plain, false, false, ["firefox-esr", "", null, 3]), null);
        // Nothing to name the app by: nothing to focus.
        compare(N.activation(rec({ desktopEntry: "", appName: "" }), false, false, [""]), null);
        // No window list at all is no window.
        compare(N.activation(named, false, false), null);
    }

    // Applies syncOps the way the history section does, to a plain array.
    function applyOps(have, ops) {
        const cur = have.slice();
        for (const o of ops) {
            if (o.op === "remove")
                cur.splice(o.at, 1);
            else if (o.op === "insert")
                cur.splice(o.at, 0, o.id);
            else
                cur.splice(o.to, 0, cur.splice(o.from, 1)[0]);
        }
        return cur;
    }

    function test_syncOpsReachesTheWantedIds() {
        const cases = [
            [[], []],
            [[], [3, 2, 1]],
            [[3, 2, 1], []],
            [[3, 2, 1], [3, 2, 1]],
            [[3, 2, 1], [4, 3, 2, 1]],
            [[3, 2, 1], [3, 1]],
            [[3, 2, 1], [1, 3, 2]],
            [[3, 2, 1], [5, 1, 4, 3]],
            [[1, 2, 3, 4], [4, 3, 2, 1]],
            [[3, 2, 1], [3, 3, 2, 2, 1]],
            [[5, 4], [2, 1]]
        ];
        for (const [have, want] of cases) {
            const dedup = want.filter((id, i) => want.indexOf(id) === i);
            compare(applyOps(have, N.syncOps(have, want)), dedup, `${have} -> ${want}`);
        }
    }

    // What stays is not touched: a new entry on top is one insert, a dismissed one is one remove.
    function test_syncOpsLeavesWhatStays() {
        compare(N.syncOps([3, 2, 1], [4, 3, 2, 1]), [{ op: "insert", at: 0, id: 4 }]);
        compare(N.syncOps([3, 2, 1], [3, 1]), [{ op: "remove", at: 1 }]);
        compare(N.syncOps([3, 2, 1], [3, 2, 1]), []);
        // An in-place update (replaces_id) moves its entry to the top.
        compare(N.syncOps([3, 2, 1], [1, 3, 2]), [{ op: "move", from: 2, to: 0 }]);
    }

    // A bubble shows only with the screen not locked and no preview open.
    function test_bubblesAllowed() {
        verify(N.bubblesAllowed(false, false));
        verify(!N.bubblesAllowed(true, false));
        verify(!N.bubblesAllowed(false, true));
        verify(!N.bubblesAllowed(true, true));
    }

    // After a lock what waits is what arrived within the last 60 s; order is kept, ids without a record go.
    function test_freshQueueDropsOldOnes() {
        const now = 1000000;
        const records = {
            1: rec({ id: 1, at: now - 61000 }),
            2: rec({ id: 2, at: now - 60000 }),
            3: rec({ id: 3, at: now - 5000 }),
            4: rec({ id: 4, at: now })
        };
        const find = id => records[id] ?? null;
        compare(N.freshQueue([1, 2, 3, 4], find, now), [2, 3, 4]);
        compare(N.freshQueue([4, 1, 3], find, now), [4, 3]);
        compare(N.freshQueue([], find, now), []);
        compare(N.freshQueue([1], find, now), []);
        compare(N.freshQueue([9, 3], find, now), [3]);
        compare(N.freshQueue([2, 3, 4], find, now, 1000), [4]);
    }

    function test_freshQueueKeepsInput() {
        const q = [1, 2];
        const find = id => rec({ id, at: 0 });
        compare(N.freshQueue(q, find, 10 * 60000), []);
        compare(q, [1, 2]);
    }

    // The queue after a lock: `resumePlan` says what leaves, what stays and whether the head shows again.
    function plan(queue, head, ages) {
        const now = 1000000;
        const records = {};
        for (const id in ages)
            records[id] = rec({ id: Number(id), at: now - ages[id] });
        return N.resumePlan(queue, head, id => records[id] ?? null, now);
    }

    function test_resumePlanEmptyQueue() {
        compare(plan([], 0, {}), { queue: [], dropped: [], showHead: false });
        // A head that is gone with nothing behind it does not show.
        compare(plan([], 5, {}), { queue: [], dropped: [], showHead: false });
    }

    function test_resumePlanAllFresh() {
        compare(plan([3, 1, 2], 3, { 1: 1000, 2: 2000, 3: 3000 }), { queue: [3, 1, 2], dropped: [], showHead: true });
    }

    function test_resumePlanSomeStale() {
        const p = plan([1, 2, 3, 4], 1, { 1: 1000, 2: 61000, 3: 2000, 4: 90000 });
        compare(p.queue, [1, 3]);
        compare(p.dropped, [2, 4]);
        verify(p.showHead);
    }

    // The head went stale: the next fresh one is the new head, and shows through the head's own change handler.
    function test_resumePlanHeadDropped() {
        const p = plan([1, 2], 1, { 1: 61000, 2: 1000 });
        compare(p.queue, [2]);
        compare(p.dropped, [1]);
        verify(!p.showHead);
    }

    function test_resumePlanEverythingDropped() {
        const p = plan([1, 2], 1, { 1: 61000, 2: 70000 });
        compare(p.queue, []);
        compare(p.dropped, [1, 2]);
        verify(!p.showHead);
    }

    // A queued id with no record goes like a stale one.
    function test_resumePlanMissingRecordDropped() {
        const p = plan([9, 2], 9, { 2: 1000 });
        compare(p.queue, [2]);
        compare(p.dropped, [9]);
        verify(!p.showHead);
    }

    // The caller always passes the queue's front as `head`; if it ever differed, the front is a different bubble than the one
    // that was up, and nothing shows here (a change of head shows through the head's own change handler).
    function test_resumePlanNewHeadNotShownTwice() {
        const p = plan([2, 1], 1, { 1: 1000, 2: 1000 });
        compare(p.queue, [2, 1]);
        verify(!p.showHead);
    }

    function test_resumePlanKeepsInput() {
        const q = [1, 2];
        N.resumePlan(q, 1, () => null, 10 * 60000);
        compare(q, [1, 2]);
    }

    function test_keepTransientPutsItInFront() {
        const old = rec({ id: 1, serverId: 11, summary: "old" });
        const kept = N.keepTransient([old], rec({ id: 2, serverId: 12, summary: "new", transient: true, live: true }));
        compare(kept.history.map(h => h.id), [2, 1]);
        compare(kept.id, 2);
        compare(kept.history[0].transient, false);
        compare(kept.history[0].live, true);
        compare(kept.history[0].kept, true);
        compare(kept.gone, []);
    }

    function test_keepTransientIsRead() {
        const kept = N.keepTransient([rec({ id: 1, serverId: 11, summary: "old", read: false })], rec({ id: 2, serverId: 12, summary: "new", transient: true, read: false }));
        compare(kept.history[0].read, true);
        compare(N.unreadCount(kept.history), 1);
    }

    function test_keepTransientRespectsTheCap() {
        const kept = N.keepTransient([rec({ id: 1, serverId: 21, summary: "a" }), rec({ id: 2, serverId: 22, summary: "b" }), rec({ id: 3, serverId: 23, summary: "c" })], rec({ id: 4, serverId: 24, summary: "d", transient: true }), 3);
        compare(kept.history.map(h => h.id), [4, 1, 2]);
        compare(kept.gone, [3]);
    }

    function test_keepTransientMergesARepeat() {
        const h = [rec({ id: 1, serverId: 31, summary: "same", count: 2 }), rec({ id: 2, serverId: 32, summary: "other" })];
        const kept = N.keepTransient(h, rec({ id: 3, serverId: 33, summary: "same", transient: true }));
        compare(kept.history.map(e => e.id), [3, 2]);
        compare(kept.history[0].count, 3);
        compare(kept.gone, [1]);
        compare(kept.id, 3);
    }

    function test_keepTransientTakesTheIdOfALiveUpdate() {
        const h = [rec({ id: 1, serverId: 9, summary: "dl 10%", live: true, count: 2 })];
        const kept = N.keepTransient(h, rec({ id: 5, serverId: 9, summary: "dl 20%", transient: true, live: true }));
        compare(kept.id, 1);
        compare(kept.history.map(e => e.id), [1]);
        compare(kept.history[0].summary, "dl 20%");
        compare(kept.history[0].read, true);
        compare(kept.history[0].kept, true);
        compare(kept.gone, []);
    }

    function test_keepTransientLeavesItsInput() {
        const r = rec({ id: 2, transient: true });
        const h = [rec({ id: 1, summary: "old" })];
        N.keepTransient(h, r);
        compare(r.transient, true);
        compare(r.kept, false);
        compare(h.length, 1);
    }

    function test_rememberKeepsTheKeptMark() {
        const h = N.keepTransient([], rec({ id: 1, serverId: 9, summary: "dl 0%", transient: true, live: true })).history;
        const update = N.remember(h, rec({ id: 7, serverId: 9, summary: "dl 50%", live: true })).history;
        compare(update[0].id, 1);
        compare(update[0].kept, true);
    }

    function test_keptSurvivesARestart() {
        const items = [rec({ id: 1, summary: "a", kept: true }), rec({ id: 2, summary: "b" })];
        const s = N.parseState(N.serialize({ dnd: false, next: 3, items }));
        compare(s.items[0].kept, true);
        compare(s.items[1].kept, false);
    }

    function test_restoreItemWithoutKeptIsNotKept() {
        const saved = JSON.parse(N.serialize({ dnd: false, next: 2, items: [rec({ id: 1 })] }));
        delete saved.items[0].kept;
        compare(N.parseState(JSON.stringify(saved)).items[0].kept, false);
    }

    // Server ids restart with the server: a held-over transient one must not take an unrelated old record.
    function test_adoptTargetTransientNeedsAKeptRecord() {
        const stale = rec({ id: 1, serverId: 4, run: "a", live: false });
        const kept = rec({ id: 2, serverId: 4, run: "a", live: false, kept: true });
        compare(N.adoptTarget([stale], 4, "a", true), undefined);
        compare(N.adoptTarget([stale, kept], 4, "a", true).id, 2);
        compare(N.adoptTarget([stale], 4, "a", false).id, 1);
    }

    function test_adoptEntryIsNeverTransientAndStaysKept() {
        const old = rec({ id: 5, serverId: 7, run: "a", live: false, kept: true, count: 2, read: true });
        const entry = N.adoptEntry(old, N.fromNotification(note({ id: 7, summary: "New", transient: true }), old.id, old.at));
        compare(entry.transient, false);
        compare(entry.kept, true);
        compare(entry.count, 2);
        compare(N.adoptEntry(rec({ id: 6, live: false }), N.fromNotification(note({ id: 8, summary: "x" }), 6, 0)).kept, false);
    }

    function test_hoverCountCountsBubbles() {
        compare(N.hoverCount(0, true), 1);
        compare(N.hoverCount(1, true), 2);
        compare(N.hoverCount(2, false), 1);
        // Moving straight from one bubble onto another: the leave arrives with the enter already counted, and
        // the other bubble still holds the timer.
        compare(N.hoverCount(N.hoverCount(1, true), false), 1);
    }

    function test_hoverCountNeverGoesNegative() {
        compare(N.hoverCount(0, false), 0);
    }

    function test_queueMoveReplacesTheId() {
        compare(N.queueMove([1, 2, 3], 2, 9), [1, 9, 3]);
    }

    function test_queueMoveToAQueuedIdKeepsItsFirstPlace() {
        compare(N.queueMove([1, 2, 3], 3, 1), [1, 2]);
        compare(N.queueMove([1, 2, 3], 1, 3), [3, 2]);
    }

    function test_queueMoveOfAnAbsentIdChangesNothing() {
        compare(N.queueMove([1, 2], 5, 9), [1, 2]);
    }

    function test_queueMoveLeavesItsInput() {
        const q = [1, 2, 3];
        N.queueMove(q, 2, 9);
        compare(q, [1, 2, 3]);
    }

    function test_inHistoryIsByRecordId() {
        const h = [rec({ id: 3 })];
        verify(N.inHistory(h, 3));
        verify(!N.inHistory(h, 4));
        verify(!N.inHistory(h, 0));
        verify(!N.inHistory([], 3));
    }
}
