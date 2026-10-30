import QtQuick
import QtTest
import "../lib/workspaces.js" as WS

TestCase {
    name: "Workspaces"

    Component {
        id: realModel

        ListModel {
            dynamicRoles: true
        }
    }

    readonly property var accents: ["navy", "teal", "magenta", "coral", "sun", "lime", "pink"]

    function test_group_first() {
        compare(WS.groupFirst(3), 1);
        compare(WS.groupFirst(14), 11);
        compare(WS.groupFirst(23), 21);
        compare(WS.groupFirst(0), 1);
        compare(WS.groupFirst(-98), 1);
    }
    function test_accent_cycles_and_groups_match() {
        compare(WS.accentFor(1, accents), "navy");
        compare(WS.accentFor(8, accents), "navy");
        compare(WS.accentFor(11, accents), WS.accentFor(1, accents));
    }
    function test_step_wraps_in_group() {
        compare(WS.step(10, 1, 1), 1);
        compare(WS.step(11, 11, -1), 20);
        compare(WS.step(14, 11, 1), 15);
    }
    function test_cells() {
        const c = WS.cells(1, [{ id: 1, name: "1", windows: 2, urgent: false }, { id: 3, name: "3", windows: 1, urgent: true },
                              { id: 5, name: "5", windows: 0, urgent: false }, { id: -98, name: "special:music", windows: 1, urgent: false }], 1, accents);
        compare(c.length, 11);
        compare(c[0].state, "active");
        compare(c[1].state, "empty");
        compare(c[2].state, "urgent");
        compare(c[4].state, "empty");
        compare(c[10].label, "music");
        compare(c[10].accent, "magenta");
    }
    function test_cell_states_occupied_and_urgent_precedence() {
        const c = WS.cells(1, [{ id: 2, name: "2", windows: 3, urgent: false }, { id: 4, name: "4", windows: 1, urgent: true },
                              { id: 6, name: "6", windows: 0, urgent: true }], 4, accents);
        compare(c[1].state, "occupied");
        compare(c[3].state, "urgent"); // urgent and active
        compare(c[5].state, "urgent"); // urgent while empty
        compare(c[0].state, "empty");
    }
    function test_active_without_windows_is_active() {
        const c = WS.cells(11, [], 13, accents);
        compare(c[2].state, "active");
        compare(c[2].accent, WS.accentFor(13, accents));
    }
    function test_step_with_active_outside_group() {
        compare(WS.step(3, 11, 1), 14);
        compare(WS.step(25, 11, -1), 14);
    }
    function test_special_states() {
        const c = WS.cells(1, [{ id: -98, name: "special:music", windows: 2, urgent: false }, { id: -97, name: "special:term", windows: 1, urgent: true },
                              { id: -96, name: "special:idle", windows: 0, urgent: false }], 1, accents);
        compare(c.length, 13);
        compare(c[10].state, "occupied");
        compare(c[11].state, "urgent");
        compare(c[11].label, "term");
        compare(c[12].state, "empty");
        compare(c[12].accent, "magenta");
    }
    function test_open_special_is_active_and_covers_the_regular_one() {
        const ws = [{ id: 1, name: "1", windows: 2, urgent: false }, { id: 2, name: "2", windows: 0, urgent: false },
                    { id: -98, name: "special:communication", windows: 1, urgent: false }, { id: -97, name: "special:music", windows: 1, urgent: false }];
        const c = WS.cells(1, ws, 1, accents, "special:communication");
        compare(c[0].state, "occupied"); // still has windows, but the special is in view
        compare(c[10].state, "active");
        compare(c[11].state, "occupied"); // open elsewhere: not this monitor's
        const empty = WS.cells(1, ws, 2, accents, "special:communication");
        compare(empty[1].state, "empty");
    }
    function test_no_special_keeps_the_regular_one_active() {
        const ws = [{ id: 1, name: "1", windows: 2, urgent: false }, { id: -98, name: "special:music", windows: 1, urgent: false }];
        compare(WS.cells(1, ws, 1, accents, "")[0].state, "active");
        compare(WS.cells(1, ws, 1, accents)[0].state, "active");
        compare(WS.cells(1, ws, 1, accents, "")[1 + 9].state, "occupied");
    }
    function test_urgent_special_stays_urgent_when_open() {
        const c = WS.cells(1, [{ id: -98, name: "special:todo", windows: 1, urgent: true }], 1, accents, "special:todo");
        compare(c[10].state, "urgent");
    }
    function test_special_icon() {
        compare(WS.specialIcon("special:communication"), "\u{f028c}");
        compare(WS.specialIcon("music"), "\u{f075a}");
        compare(WS.specialIcon("special:game"), "\u{f0297}");
        compare(WS.specialIcon("special:sysmon"), "\u{f0a07}");
        compare(WS.specialIcon("special:todo"), "\u{f0756}");
        compare(WS.specialIcon("special:special"), "\u{f0ae2}");
        compare(WS.specialIcon("special:hidden"), "\u{f0209}");
        // An unknown name shows its first letter.
        compare(WS.specialIcon("special:notes"), "N");
        compare(WS.specialIcon("special:"), "");
        compare(WS.specialIcon(""), "");
    }
    function test_cells_carry_apps() {
        const ws = [{ id: 2, name: "2", windows: 2, urgent: false, apps: ["firefox", "kitty"] }, { id: -98, name: "special:music", windows: 1, urgent: false, apps: ["spotify"] }];
        const c = WS.cells(1, ws, 1, accents, "");
        compare(c[0].apps, []);
        compare(c[1].apps, ["firefox", "kitty"]);
        compare(c[10].apps, ["spotify"]);
        compare(c[10].name, "special:music");
    }
    function test_cells_count() {
        const c = WS.cells(6, [{ id: -98, name: "special:music", windows: 1, urgent: false }], 7, accents, "", 5);
        compare(c.length, 6);
        compare(c[0].id, 6);
        compare(c[4].id, 10);
        compare(c[1].state, "active");
        compare(c[5].label, "music");
    }
    function test_page_first() {
        compare(WS.pageFirst(1, 1), 1);
        compare(WS.pageFirst(1, 5), 1);
        compare(WS.pageFirst(1, 6), 6);
        compare(WS.pageFirst(1, 10), 6);
        compare(WS.pageFirst(11, 14), 11);
        compare(WS.pageFirst(11, 16), 16);
        compare(WS.pageFirst(11, 20), 16);
        // Outside the group (or unknown): the first half.
        compare(WS.pageFirst(1, 12), 1);
        compare(WS.pageFirst(11, 3), 11);
        compare(WS.pageFirst(1, 0), 1);
        compare(WS.pageFirst(1, -98), 1);
    }
    function test_app_summary() {
        compare(WS.appSummary([], 4), { apps: [], more: 0 });
        compare(WS.appSummary(["kitty", "firefox", "kitty"], 4), { apps: ["kitty", "firefox"], more: 0 });
        compare(WS.appSummary(["Kitty", "kitty", "", null, "steam"], 4), { apps: ["Kitty", "steam"], more: 0 });
        compare(WS.appSummary(["a", "b", "c", "d", "e", "f"], 4), { apps: ["a", "b", "c", "d"], more: 2 });
        compare(WS.appSummary(["a", "b", "c", "d"], 4).more, 0);
    }
    function test_lua_string_escapes() {
        compare(WS.luaString("music"), '"music"');
        compare(WS.luaString('a"b'), '"a\\"b"');
        compare(WS.luaString("a\\b"), '"a\\\\b"');
        compare(WS.luaString("a\nb\rc"), '"a\\nb\\rc"');
        // A name that tries to close the string and the call stays one string literal.
        compare(WS.luaString('x" }) os.execute("y'), '"x\\" }) os.execute(\\"y"');
    }
    function test_focus_command() {
        compare(WS.focusCommand("4"), 'hl.dsp.focus({ workspace = "4" })');
        compare(WS.focusCommand('we"ird'), 'hl.dsp.focus({ workspace = "we\\"ird" })');
    }
    // A click on a monitor's bar shows the workspace on that monitor: focusing it by id alone would hop to whichever
    // monitor holds it (workspace 1 on DP-2 sends a click on DP-1's bar there).
    function test_focus_command_on_monitor() {
        const command = WS.focusCommand("1", "DP-1");
        compare(command, '(function() local ws = hl.get_workspace("1") hl.dispatch(hl.dsp.focus({ monitor = "DP-1" })) '
            + 'if ws and ws.monitor and ws.monitor.name ~= "DP-1" then hl.dispatch(hl.dsp.workspace.move({ workspace = "1", monitor = "DP-1" })) end '
            + 'return hl.dsp.focus({ workspace = "1" }) end)()');
        // Without a monitor it stays the plain focus.
        compare(WS.focusCommand("1", ""), 'hl.dsp.focus({ workspace = "1" })');
        // Names are escaped wherever they appear.
        const tricky = WS.focusCommand('a"b', 'c"d');
        verify(tricky.indexOf('monitor = "c\\"d"') > 0);
        verify(tricky.indexOf('workspace = "a\\"b"') > 0);
        verify(tricky.indexOf('"a"b"') < 0 && tricky.indexOf('"c"d"') < 0);
    }
    function test_toggle_special_command() {
        compare(WS.toggleSpecialCommand("special:music"), 'hl.dsp.workspace.toggle_special("music")');
        compare(WS.toggleSpecialCommand("music"), 'hl.dsp.workspace.toggle_special("music")');
        compare(WS.toggleSpecialCommand('a"b'), 'hl.dsp.workspace.toggle_special("a\\"b")');
    }

    // A stand-in for a ListModel: the rows, and the calls the sync makes.
    function fakeModel() {
        return {
            rows: [], calls: [],
            get count() { return this.rows.length; },
            get: function (i) { return this.rows[i]; },
            set: function (i, row) { this.calls.push("set" + i); this.rows[i] = row; },
            append: function (row) { this.calls.push("append"); this.rows.push(row); },
            remove: function (i, n) { this.calls.push("remove" + i + "," + n); this.rows.splice(i, n); }
        };
    }
    function test_sync_list_fills_and_leaves_equal_rows() {
        const m = fakeModel();
        WS.syncList(m, ["a", "b"], "id");
        compare(m.rows.map(r => r.id), ["a", "b"]);
        m.calls = [];
        WS.syncList(m, ["a", "b"], "id");
        compare(m.calls, []);
    }
    function test_sync_list_sets_changed_rows_only() {
        const m = fakeModel();
        WS.syncList(m, [{ n: 1 }, { n: 2 }], "cell");
        m.calls = [];
        WS.syncList(m, [{ n: 1 }, { n: 3 }], "cell");
        compare(m.calls, ["set1"]);
        compare(m.rows[1].cell.n, 3);
    }
    function test_sync_list_grows_and_shrinks_at_the_end() {
        const m = fakeModel();
        WS.syncList(m, ["a", "b", "c"], "id");
        m.calls = [];
        WS.syncList(m, ["a", "b"], "id");
        compare(m.calls, ["remove2,1"]);
        m.calls = [];
        WS.syncList(m, ["a", "b", "z"], "id");
        compare(m.calls, ["append"]);
        WS.syncList(m, [], "id");
        compare(m.rows.length, 0);
    }
    function test_sync_list_ignores_key_order() {
        const m = fakeModel();
        WS.syncList(m, [{ a: 1, b: { y: 2, x: [3, { q: 1, p: 2 }] } }], "cell");
        m.calls = [];
        WS.syncList(m, [{ b: { x: [3, { p: 2, q: 1 }], y: 2 }, a: 1 }], "cell");
        compare(m.calls, []);
    }

    // Against a real ListModel, what a Repeater's delegates see: no change signal for a list that has not changed, one
    // for a changed row. (A ListModel does not signal a set of equal values, so this does not tell whether syncList
    // skipped the set; the fake model above does.)
    function test_sync_list_real_model_sets_changed_rows_only() {
        const model = createTemporaryObject(realModel, this);
        let changed = 0;
        model.dataChanged.connect(() => changed++);
        const cell = (id, state) => ({ id, label: String(id), state, accent: "sun", apps: ["foot"] });
        WS.syncList(model, [cell(1, "empty"), cell(2, "active")], "cell");
        const filled = changed;
        WS.syncList(model, [cell(1, "empty"), cell(2, "active")], "cell");
        compare(changed, filled);
        WS.syncList(model, [cell(1, "empty"), cell(2, "urgent")], "cell");
        compare(changed, filled + 1);
        compare(model.get(1).cell.state, "urgent");
        WS.syncList(model, [cell(1, "empty")], "cell");
        compare(model.count, 1);
    }
}
