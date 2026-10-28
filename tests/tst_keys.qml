import QtQuick
import QtTest
import "../lib/keys.js" as K
import "../lib/activities.js" as A
import "../lib/glyphs.js" as G

TestCase {
    name: "Keys"

    function test_parseLocks() {
        compare(K.parseLocks("caps=1\nnum=0\n"), { caps: true, num: false });
        compare(K.parseLocks("caps=0\nnum=1"), { caps: false, num: true });
    }

    function test_parseLocksKeepsWhatItReads() {
        compare(K.parseLocks("num=1\n"), { caps: false, num: true });
    }

    function test_parseLocksWithoutAReadingIsNull() {
        compare(K.parseLocks(""), null);
        compare(K.parseLocks("sh: nonsense\ncaps=2\n"), null);
    }

    function test_firstReadingChangesNothing() {
        compare(K.lockChanges(null, { caps: true, num: true }), []);
        compare(K.lockChanges({ caps: true, num: true }, null), []);
    }

    function test_changesNameTheKeyAndItsNewState() {
        const off = { caps: false, num: false };
        compare(K.lockChanges(off, { caps: true, num: false }), [{ key: "caps", on: true }]);
        compare(K.lockChanges({ caps: true, num: true }, { caps: true, num: false }), [{ key: "num", on: false }]);
        compare(K.lockChanges(off, { caps: true, num: true }), [{ key: "caps", on: true }, { key: "num", on: true }]);
        compare(K.lockChanges(off, off), []);
    }

    function test_layoutChangedNeedsTwoKnownNames() {
        verify(K.layoutChanged("English (US)", "Swedish"));
        verify(!K.layoutChanged("", "Swedish"));
        verify(!K.layoutChanged("Swedish", ""));
        verify(!K.layoutChanged("Swedish", "Swedish"));
    }

    function test_quietWhileLocked() {
        verify(K.allowed(false, false));
        verify(!K.allowed(true, false));
        verify(!K.allowed(false, true));
    }

    function test_everyKindHasAnActivityATabAndAName() {
        const ids = {};
        for (const kind of ["layout", "caps", "num"]) {
            verify(K.activityId(kind) !== "", kind);
            verify(K.tab(kind) !== "", kind);
            verify(K.name(kind) !== "", kind);
            ids[K.activityId(kind)] = true;
        }
        compare(Object.keys(ids).length, 3);
        compare(K.activityId("nonsense"), "");
    }

    function test_iconsHaveGlyphs() {
        verify(G.has(K.icon("layout", false)));
        for (const on of [true, false])
            verify(G.has(K.icon("caps", on)));
        verify(K.icon("num", true) !== K.icon("num", false));
    }

    // The keys HUD takes the volume HUD's place at the top of the queue: the newest of the two shows.
    function test_keysShareTheHudPriority() {
        compare(A.PRIORITY.keys, A.PRIORITY.hud);
        const list = [{ id: "volume", priority: A.PRIORITY.hud, expiresAt: 5000, section: "", seq: 1 }, { id: "capsLock", priority: A.PRIORITY.keys, expiresAt: 5000, section: "", seq: 2 }];
        compare(A.top(list, 1000).id, "capsLock");
        verify(A.PRIORITY.keys > A.PRIORITY.timerDone);
    }
}
