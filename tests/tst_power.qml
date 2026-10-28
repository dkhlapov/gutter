import QtQuick
import QtTest
import "../lib/power.js" as Power

TestCase {
    name: "Power"

    readonly property string busctl: 'CanSuspend s "yes"\nCanHibernate s "na"\nCanReboot s "yes"\nCanPowerOff s "challenge"\n'

    function ids(list) {
        return list.map(e => e.id).join(",");
    }

    function test_parse_can() {
        const can = Power.parseCan(busctl);
        compare(can.CanSuspend, "yes");
        compare(can.CanHibernate, "na");
        compare(can.CanPowerOff, "challenge");
        compare(Object.keys(Power.parseCan("")).length, 0);
        compare(Object.keys(Power.parseCan("garbage\nCanFly x 1")).length, 0);
    }
    function test_entries_in_order_and_unavailable_ones_hidden() {
        compare(ids(Power.entries(Power.parseCan(busctl))), "lock,logout,suspend,reboot,poweroff");
        compare(ids(Power.entries({ CanSuspend: "yes", CanHibernate: "yes", CanReboot: "yes", CanPowerOff: "yes" })), "lock,logout,suspend,hibernate,reboot,poweroff");
        compare(ids(Power.entries({ CanSuspend: "no", CanHibernate: "no", CanReboot: "yes", CanPowerOff: "yes" })), "lock,logout,reboot,poweroff");
    }
    function test_unknown_answers() {
        // Before logind has answered: everything but hibernate, which only shows once it is known to work.
        compare(ids(Power.entries({})), "lock,logout,suspend,reboot,poweroff");
    }
    function test_confirm_only_what_ends_the_session() {
        const byId = {};
        Power.entries({ CanHibernate: "yes" }).forEach(e => byId[e.id] = e);
        verify(!byId.lock.confirm);
        verify(!byId.suspend.confirm);
        verify(!byId.hibernate.confirm);
        verify(byId.logout.confirm);
        verify(byId.reboot.confirm);
        verify(byId.poweroff.confirm);
        verify(byId.poweroff.label !== "" && byId.poweroff.icon !== "");
    }
    function test_commands() {
        compare(Power.command("lock", "3"), []);
        compare(Power.command("logout", "3"), ["loginctl", "terminate-session", "3"]);
        compare(Power.command("logout", ""), ["loginctl", "terminate-user", ""]);
        compare(Power.command("suspend", "3"), ["systemctl", "suspend"]);
        compare(Power.command("hibernate", "3"), ["systemctl", "hibernate"]);
        compare(Power.command("reboot", "3"), ["systemctl", "reboot"]);
        compare(Power.command("poweroff", "3"), ["systemctl", "poweroff"]);
        compare(Power.command("selfdestruct", "3"), []);
    }
    function test_choose() {
        const logout = { id: "logout", confirm: true };
        const reboot = { id: "reboot", confirm: true };
        const suspend = { id: "suspend", confirm: false };
        const lock = { id: "lock", confirm: false };
        compare(Power.choose(logout, ""), { run: false, confirming: "logout" });
        compare(Power.choose(logout, "logout"), { run: true, confirming: "" });
        compare(Power.choose(reboot, "logout"), { run: false, confirming: "reboot" });
        compare(Power.choose(suspend, "logout"), { run: true, confirming: "" });
        compare(Power.choose(lock, ""), { run: true, confirming: "" });
    }
    // Choosing the lock asks Gutter's lock screen; in a dry run it never does, whatever else happens.
    function test_route_lock() {
        compare(Power.route("lock", false, "3"), { act: "lock", command: [], log: "" });
        compare(Power.route("lock", true, "3"), { act: "log", command: [], log: "gutter: power (dry run): lock" });
        compare(Power.route("lock", true, "").act, "log");
        verify(Power.route("lock", true, "3").act !== "lock");
    }
    function test_route_commands() {
        compare(Power.route("suspend", false, "3"), { act: "exec", command: ["systemctl", "suspend"], log: "" });
        compare(Power.route("logout", false, "3"), { act: "exec", command: ["loginctl", "terminate-session", "3"], log: "" });
        compare(Power.route("logout", false, ""), { act: "exec", command: ["loginctl", "terminate-user", ""], log: "" });
    }
    // A dry run never runs a command; every line has the same shape: the id, then the command where there is one.
    function test_route_dry_run_logs_one_shape() {
        compare(Power.route("suspend", true, "3"), { act: "log", command: ["systemctl", "suspend"], log: 'gutter: power (dry run): suspend ["systemctl","suspend"]' });
        compare(Power.route("logout", true, "3").log, 'gutter: power (dry run): logout ["loginctl","terminate-session","3"]');
        for (const e of Power.entries({ CanHibernate: "yes" })) {
            const r = Power.route(e.id, true, "3");
            compare(r.act, "log");
            verify(r.log.startsWith("gutter: power (dry run): " + e.id), r.log);
        }
    }
    function test_route_unknown_does_nothing() {
        compare(Power.route("selfdestruct", false, "3"), { act: "none", command: [], log: "" });
        compare(Power.route("selfdestruct", true, "3"), { act: "none", command: [], log: "" });
        compare(Power.route("", false, "3").act, "none");
        compare(Power.route("__proto__", true, "3").act, "none");
    }
    function test_choose_without_confirm_runs_at_once() {
        // An entry with no `confirm` at all counts as not needing one, whatever is pending.
        const bare = { id: "x" };
        compare(Power.choose(bare, ""), { run: true, confirming: "" });
        compare(Power.choose(bare, "logout"), { run: true, confirming: "" });
        compare(Power.choose(bare, "x"), { run: true, confirming: "" });
        compare(Power.choose({ id: "x", confirm: undefined }, "logout"), { run: true, confirming: "" });
    }
    function test_can_query_asks_every_method() {
        const cmd = Power.canQuery().join(" ");
        verify(cmd.indexOf("CanSuspend") >= 0 && cmd.indexOf("CanHibernate") >= 0 && cmd.indexOf("CanReboot") >= 0 && cmd.indexOf("CanPowerOff") >= 0);
    }
}
