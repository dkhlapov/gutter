import QtQuick
import QtTest
import "../lib/activities.js" as A

TestCase {
    name: "Activities"

    function e(id, priority, expiresAt, seq) {
        return { id, priority, expiresAt, section: "", seq };
    }

    function test_topPicksHighestPriority() {
        const list = [e("timer", 30, null, 1), e("volume", 100, 5000, 2)];
        compare(A.top(list, 1000).id, "volume");
    }

    function test_tieGoesToMostRecent() {
        const list = [e("volume", 100, 5000, 1), e("brightness", 100, 5000, 2)];
        compare(A.top(list, 1000).id, "brightness");
    }

    function test_expiredEntriesIgnored() {
        const list = [e("timer", 30, null, 1), e("volume", 100, 1500, 2)];
        compare(A.top(list, 2000).id, "timer");
        compare(A.prune(list, 2000).length, 1);
    }

    function test_emptyGivesNull() {
        compare(A.top([], 0), null);
    }

    function test_upsertReplacesSameId() {
        let list = A.upsert([], e("volume", 100, 1000, 1));
        list = A.upsert(list, e("volume", 100, 3000, 2));
        compare(list.length, 1);
        compare(list[0].expiresAt, 3000);
    }

    function test_remove() {
        compare(A.remove([e("a", 1, null, 1), e("b", 1, null, 2)], "a").map(x => x.id), ["b"]);
    }

    function test_nextExpiry() {
        const list = [e("a", 1, null, 1), e("b", 1, 3000, 2), e("c", 1, 2000, 3), e("d", 1, 500, 4)];
        compare(A.nextExpiry(list, 1000), 2000);
        compare(A.nextExpiry([e("a", 1, null, 1)], 1000), null);
    }

    // Music playing and an agent working are long-running: they never take the island body.
    function test_longRunningActivitiesAreNotRegistered() {
        for (const id of ["playing", "agents", "agentsWaiting"])
            verify(!(id in A.PRIORITY), id);
    }

    function test_shortActivitiesKeepTheirOrder() {
        const p = A.PRIORITY;
        verify(p.hud > p.timerDone && p.timerDone > p.agentDone && p.agentDone > p.agentLimit);
        verify(p.agentLimit > p.notification && p.notification > p.trackChange && p.trackChange > p.timer && p.timer > p.stopwatch);
    }
}
