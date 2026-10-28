import QtQuick
import QtTest
import "../lib/agentUsage.js" as U

TestCase {
    name: "AgentUsage"

    function test_money() {
        compare(U.money(14.0123), "$14.01");
        compare(U.money(0), "$0.00");
        compare(U.money(1234.5), "$1,235");
        compare(U.money(12345), "$12.3K");
    }

    function test_tokens() {
        compare(U.tokens(35123456), "35M");
        compare(U.tokens(1460000), "1.5M");
        compare(U.tokens(10400), "10K");
        compare(U.tokens(950), "950");
        compare(U.tokens(2.5e9), "2.5B");
    }

    function test_duration() {
        compare(U.duration(2 * 3600 + 36 * 60), "2h 36m");
        compare(U.duration(36 * 60 + 10), "36m");
        compare(U.duration(20), "1m");
        compare(U.duration(76 * 3600), "3d 4h");
    }

    function test_clock() {
        compare(U.clock(248000), "4:08");
        compare(U.clock(3723000), "1:02:03");
    }

    function test_limits() {
        const file = { t: 5, rate_limits: { five_hour: { used_percentage: 64, resets_at: 1000 + 9360 }, seven_day: { used_percentage: 29, resets_at: 500 } } };
        const l = U.limits(file, 1000 * 1000);
        compare(l.session.pct, 64);
        compare(l.session.resetsIn, 9360);
        // Past its reset with no newer report: unknown, not 0 %.
        compare(l.week.pct, null);
        compare(l.week.resetsIn, -1);
        verify(l.week.renewed);
        compare(U.limits(null, 0).session, null);
        compare(U.limits({ rate_limits: { five_hour: { used_percentage: 10 } } }, 0).week, null);
    }

    function test_limitsStale() {
        // A week-old file (every window reset since): both unknown, neither a reading of 0.
        const file = { t: 1, rate_limits: { five_hour: { used_percentage: 37, resets_at: 100 }, seven_day: { used_percentage: 88, resets_at: 200 } } };
        const l = U.limits(file, 1000 * 1000);
        verify(l.session.renewed);
        verify(l.week.renewed);
        compare(l.session.pct, null);
        compare(l.week.pct, null);
        // Reset exactly now counts as passed; a window with no reset time keeps its reading.
        verify(U.limits(file, 100 * 1000).session.renewed);
        const open = U.limits({ t: 1, rate_limits: { five_hour: { used_percentage: 37 } } }, 1000 * 1000).session;
        compare(open.pct, 37);
        verify(!open.renewed);
    }

    function test_limitsModel() {
        const rl = { five_hour: { used_percentage: 5, resets_at: 5000 }, seven_day_model: { used_percentage: 4, resets_at: 5000, name: "Fable" } };
        const l = U.limits({ t: 1, rate_limits: rl }, 1000 * 1000);
        compare(l.model.pct, 4);
        compare(l.model.name, "Fable");
        compare(U.limits({ t: 1, rate_limits: { five_hour: rl.five_hour } }, 0).model, null);
        // Reset since the report: unknown, like the other windows.
        verify(U.limits({ t: 1, rate_limits: rl }, 6000 * 1000).model.renewed);
    }

    function test_newest() {
        const bridge = { t: 100, rate_limits: {} };
        const api = { t: 200, rate_limits: {} };
        compare(U.newest(bridge, api), api);
        compare(U.newest(api, bridge), api);
        compare(U.newest(bridge, null), bridge);
        compare(U.newest(null, api), api);
        compare(U.newest(null, null), null);
        // Equal times: the first (the bridge) stays; a file without a time loses to one with it.
        const same = { t: 100 };
        compare(U.newest(bridge, same), bridge);
        compare(U.newest({ rate_limits: {} }, bridge), bridge);
    }

    function test_fetchDelay() {
        compare(U.fetchDelay(0, 0), 180000);
        compare(U.fetchDelay(1, 0), 360000);
        compare(U.fetchDelay(2, 0), 720000);
        compare(U.fetchDelay(50, 0), 1800000);
        // Retry-After wins when longer, and is capped like everything else.
        compare(U.fetchDelay(0, 600), 600000);
        compare(U.fetchDelay(1, 30), 360000);
        compare(U.fetchDelay(0, 99999), 1800000);
        compare(U.fetchDelay(0, undefined), 180000);
    }

    function test_pace() {
        compare(U.pace({ pct: 10, resetsIn: 9000, renewed: false }, 18000), 0.5);
        compare(U.pace({ pct: null, resetsIn: -1, renewed: true }, 18000), -1);
        compare(U.pace(null, 18000), -1);
    }

    function test_crossed() {
        compare(U.crossed(70, 82), 80);
        compare(U.crossed(82, 85), 0);
        compare(U.crossed(70, 99), 95);
        compare(U.crossed(99, 10), 0);
    }

    function test_limitAlerts() {
        // Start-up mid-window: seeded, no alert.
        let r = U.limitAlerts({}, [{ key: "Session:10", pct: 85 }], true);
        compare(r.hits, [0]);
        compare(r.seen["Session:10"], 85);
        // The same window climbing past 95 alerts once.
        r = U.limitAlerts(r.seen, [{ key: "Session:10", pct: 96 }], false);
        compare(r.hits, [95]);
        r = U.limitAlerts(r.seen, [{ key: "Session:10", pct: 97 }], false);
        compare(r.hits, [0]);
        // A new window already past 80 at its first reading alerts, and the old key is pruned.
        r = U.limitAlerts(r.seen, [{ key: "Session:20", pct: 82 }, { key: "Week:30", pct: 10 }], false);
        compare(r.hits, [80, 0]);
        compare(Object.keys(r.seen).sort(), ["Session:20", "Week:30"]);
        // A dip (stale reading) does not re-arm the threshold.
        r = U.limitAlerts(r.seen, [{ key: "Session:20", pct: 70 }], false);
        r = U.limitAlerts(r.seen, [{ key: "Session:20", pct: 83 }], false);
        compare(r.hits, [0]);
        compare(U.limitAlerts(null, [], true).hits, []);
    }

    function test_heatLevel() {
        compare(U.heatLevel(0, 10), 0);
        compare(U.heatLevel(0.1, 10), 1);
        compare(U.heatLevel(10, 10), 4);
        compare(U.heatLevel(6, 10), 3);
    }
}
