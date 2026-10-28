import QtQuick
import QtTest
import "../lib/config.js" as ConfigLib

TestCase {
    name: "Config"

    function test_defaultsMatchVorssaint() {
        const d = ConfigLib.defaults();
        compare(d.openOnHover, false);
        compare(d.hoverDelay, 250);
        compare(d.hideInFullscreen, true);
        compare(d.idleContent, "music");
        compare(d.opensActivity, true);
        compare(d.width, 200);
        compare(d.gestures, true);
        compare(d.notifications, true);
        compare(d.sections, ["overview", "music", "calendar", "system", "weather", "tools", "agents", "shelf", "clipboard", "mixer", "notifications"]);
        compare(d.configVersion, 8);
        compare(d.weather.location, "");
        compare(d.weather.units, "metric");
        compare(d.worldClocks, ConfigLib.WORLD_CLOCKS);
    }

    function test_themeDefaults() {
        const d = ConfigLib.defaults();
        compare(d.theme.mode, "sun");
        compare(d.theme.schedule.light, "07:00");
        compare(d.theme.schedule.dark, "20:00");
    }

    function test_themeInvalidValuesFallBackWithWarning() {
        const r = ConfigLib.merge({ theme: { mode: "dusk", schedule: { light: "6:30", dark: "25:00" } } });
        compare(r.config.theme.mode, "sun");
        compare(r.config.theme.schedule.light, "07:00");
        compare(r.config.theme.schedule.dark, "20:00");
        compare(r.warnings.length, 3);
    }

    function test_themeValidValuesKept() {
        const r = ConfigLib.merge({ theme: { mode: "schedule", schedule: { light: "06:30", dark: "23:59" } } });
        compare(r.config.theme.mode, "schedule");
        compare(r.config.theme.schedule.light, "06:30");
        compare(r.config.theme.schedule.dark, "23:59");
        compare(r.warnings.length, 0);
    }

    function test_dropsHideUntilHoverAndAllMonitors() {
        const r = ConfigLib.merge({ hideUntilHover: true, allMonitors: true });
        compare(r.config.hideUntilHover, undefined);
        compare(r.config.allMonitors, undefined);
        compare(r.warnings.length, 0);
    }

    function test_emptyObjectGivesDefaults() {
        const r = ConfigLib.merge({});
        compare(r.config, ConfigLib.defaults());
        compare(r.warnings.length, 0);
    }

    function test_keepsValidValues() {
        const r = ConfigLib.merge({ openOnHover: true, width: 260, idleContent: "clock", weather: { units: "imperial" } });
        compare(r.config.openOnHover, true);
        compare(r.config.width, 260);
        compare(r.config.idleContent, "clock");
        compare(r.config.weather.units, "imperial");
        compare(r.config.weather.location, "");
    }

    function test_invalidValuesFallBackWithWarning() {
        const r = ConfigLib.merge({ openOnHover: "yes", width: 5000, idleContent: "battery", sections: ["music", "bogus"] });
        compare(r.config.openOnHover, false);
        compare(r.config.width, 200);
        compare(r.config.idleContent, "music");
        compare(r.config.sections, ConfigLib.SECTIONS);
        compare(r.warnings.length, 4);
    }

    function test_duplicateOrEmptySectionsRejected() {
        compare(ConfigLib.merge({ sections: [] }).config.sections.length, ConfigLib.SECTIONS.length);
        compare(ConfigLib.merge({ sections: ["music", "music"] }).config.sections.length, ConfigLib.SECTIONS.length);
        compare(ConfigLib.merge({ sections: ["weather", "music"] }).config.sections, ["weather", "music"]);
    }

    function test_unknownKeysIgnored() {
        const r = ConfigLib.merge({ foo: 1 });
        verify(r.config.foo === undefined);
        compare(r.warnings.length, 0);
    }

    function test_parseRejectsBadJson() {
        compare(ConfigLib.parse("{ \"width\": "), null);
        compare(ConfigLib.parse("{\"width\": 300}").config.width, 300);
    }

    function test_defaultsAreFreshCopies() {
        const a = ConfigLib.defaults();
        a.sections.push("x");
        compare(ConfigLib.defaults().sections.length, ConfigLib.SECTIONS.length);
    }

    function test_worldClocksDefault() {
        compare(ConfigLib.defaults().worldClocks, [
            { label: "New York", tz: "America/New_York" },
            { label: "London", tz: "Europe/London" },
            { label: "Tokyo", tz: "Asia/Tokyo" },
            { label: "UTC", tz: "UTC" }
        ]);
    }

    // Padding skips defaults whose zone is already configured.
    function test_worldClocksPadded() {
        const r = ConfigLib.merge({ worldClocks: [{ label: "LDN", tz: "Europe/London" }] });
        compare(r.config.worldClocks.map(c => c.label), ["LDN", "New York", "Tokyo", "UTC"]);
        compare(r.warnings.length, 0);
    }

    function test_worldClocksTruncatedWithWarning() {
        const five = ["UTC", "Asia/Tokyo", "Europe/Paris", "Europe/Berlin", "Asia/Kolkata"].map(tz => ({ label: tz, tz }));
        const r = ConfigLib.merge({ worldClocks: five });
        compare(r.config.worldClocks.map(c => c.tz), ["UTC", "Asia/Tokyo", "Europe/Paris", "Europe/Berlin"]);
        compare(r.warnings.length, 1);
    }

    function test_worldClocksInvalidEntriesDropped() {
        const r = ConfigLib.merge({ worldClocks: [{ label: "X" }, { label: "Y", tz: "Asia/Tokyo" }] });
        compare(r.config.worldClocks.map(c => c.label), ["Y", "New York", "London", "UTC"]);
        compare(r.warnings.length, 1);
        const s = ConfigLib.merge({ worldClocks: "nope" });
        compare(s.config.worldClocks, ConfigLib.WORLD_CLOCKS);
        compare(s.warnings.length, 1);
    }

    function test_worldClocksAreCopies() {
        const a = ConfigLib.defaults();
        a.worldClocks[0].label = "changed";
        compare(ConfigLib.defaults().worldClocks[0].label, "New York");
    }

    // A version 7 config gains only Notifications.
    function test_migrateVersion7AddsNotificationsOnly() {
        const r = ConfigLib.parse(JSON.stringify({ configVersion: 7, sections: ["music", "mixer"] }));
        compare(r.config.sections, ["music", "mixer", "notifications"]);
        compare(r.rewrite, { configVersion: 8, sections: ["music", "mixer", "notifications"] });
    }

    function test_migrateKeepsAnExistingNotificationsSection() {
        const m = ConfigLib.migrate({ configVersion: 7, sections: ["notifications", "music"] });
        compare(m.raw.sections, ["notifications", "music"]);
        compare(m.raw.configVersion, 8);
        verify(m.changed);
    }

    // A version 6 config gains only Mixer.
    function test_migrateVersion6AddsMixerOnly() {
        const r = ConfigLib.parse(JSON.stringify({ configVersion: 6, sections: ["music"] }));
        compare(r.config.sections, ["music", "mixer", "notifications"]);
        compare(r.rewrite, { configVersion: 8, sections: ["music", "mixer", "notifications"] });
    }

    // Review focus 1: a sub-project 1 config gains Overview in front and Tools at the end, exactly once.
    function test_migrateInsertsOverviewOnce() {
        const r = ConfigLib.parse(JSON.stringify({ sections: ["weather", "music"], width: 260 }));
        compare(r.config.sections, ["overview", "weather", "music", "tools", "agents", "shelf", "clipboard", "mixer", "notifications"]);
        compare(r.rewrite, { sections: ["overview", "weather", "music", "tools", "agents", "shelf", "clipboard", "mixer", "notifications"], width: 260, configVersion: 8 });
        const again = ConfigLib.parse(JSON.stringify(r.rewrite));
        compare(again.config.sections, ["overview", "weather", "music", "tools", "agents", "shelf", "clipboard", "mixer", "notifications"]);
        compare(again.rewrite, null);
    }

    // A version 2 config gains Tools and Agents; an Overview removed by the user stays removed.
    function test_migrateVersion2AddsToolsAndAgents() {
        const r = ConfigLib.parse(JSON.stringify({ configVersion: 2, sections: ["music", "system"] }));
        compare(r.config.sections, ["music", "system", "tools", "agents", "shelf", "clipboard", "mixer", "notifications"]);
        compare(r.rewrite, { configVersion: 8, sections: ["music", "system", "tools", "agents", "shelf", "clipboard", "mixer", "notifications"] });
    }

    // A version 3 config gains only Agents; a Tools tab removed by the user stays removed.
    function test_migrateVersion3AddsAgentsOnly() {
        const r = ConfigLib.parse(JSON.stringify({ configVersion: 3, sections: ["music"] }));
        compare(r.config.sections, ["music", "agents", "shelf", "clipboard", "mixer", "notifications"]);
        compare(r.rewrite, { configVersion: 8, sections: ["music", "agents", "shelf", "clipboard", "mixer", "notifications"] });
    }

    // A version 4 config gains only Shelf; an Agents tab removed by the user stays removed.
    function test_migrateVersion4AddsShelfOnly() {
        const r = ConfigLib.parse(JSON.stringify({ configVersion: 4, sections: ["music"] }));
        compare(r.config.sections, ["music", "shelf", "clipboard", "mixer", "notifications"]);
        compare(r.rewrite, { configVersion: 8, sections: ["music", "shelf", "clipboard", "mixer", "notifications"] });
    }

    // A version 5 config gains only Clipboard.
    function test_migrateVersion5AddsClipboardOnly() {
        const r = ConfigLib.parse(JSON.stringify({ configVersion: 5, sections: ["music"] }));
        compare(r.config.sections, ["music", "clipboard", "mixer", "notifications"]);
        compare(r.rewrite, { configVersion: 8, sections: ["music", "clipboard", "mixer", "notifications"] });
    }

    // Review focus 1: removing a tab after the migration sticks.
    function test_removedTabsStayRemoved() {
        const r = ConfigLib.parse(JSON.stringify({ configVersion: 8, sections: ["music", "system"] }));
        compare(r.config.sections, ["music", "system"]);
        compare(r.rewrite, null);
    }

    function test_migrateKeepsExistingTools() {
        const m = ConfigLib.migrate({ configVersion: 2, sections: ["tools", "music"] });
        compare(m.raw.sections, ["tools", "music", "agents", "shelf", "clipboard", "mixer", "notifications"]);
    }

    function test_migrateWithoutSectionsOnlyStampsVersion() {
        const r = ConfigLib.parse(JSON.stringify({ width: 300 }));
        compare(r.config.sections, ConfigLib.SECTIONS);
        compare(r.rewrite, { width: 300, configVersion: 8 });
    }

    function test_migrateKeepsExistingOverview() {
        const m = ConfigLib.migrate({ sections: ["music", "overview"] });
        compare(m.raw.sections, ["music", "overview", "tools", "agents", "shelf", "clipboard", "mixer", "notifications"]);
        verify(m.changed);
    }

    // An explicit configVersion 1 is a sub-project 1 config like one with no stamp.
    function test_migrateExplicitVersion1() {
        const all = ["overview", "weather", "music", "tools", "agents", "shelf", "clipboard", "mixer", "notifications"];
        const r = ConfigLib.parse(JSON.stringify({ configVersion: 1, sections: ["weather", "music"] }));
        compare(r.config.sections, all);
        compare(r.rewrite, { configVersion: 8, sections: all });
    }

    // The rewrite keeps every other key and value as the user wrote them, known or not. The "6:30" is invalid on
    // purpose: merge falls back to 07:00 with a warning, the rewrite keeps it verbatim.
    function test_migrateCarriesOtherKeysUntouched() {
        const raw = { configVersion: 7, width: 260, theme: { mode: "dark", schedule: { light: "6:30" } }, unknownKey: { a: [1, 2] }, sections: ["music"] };
        const r = ConfigLib.parse(JSON.stringify(raw));
        compare(r.rewrite, { configVersion: 8, width: 260, theme: { mode: "dark", schedule: { light: "6:30" } }, unknownKey: { a: [1, 2] }, sections: ["music", "notifications"] });
        compare(r.config.width, 260);
        compare(r.config.theme.mode, "dark");
        compare(r.config.theme.schedule.light, "07:00");
        compare(r.warnings.length, 1);
        verify(r.config.unknownKey === undefined);
    }

    // The user's own order and subset survive: merge keeps it as is, a migration only appends what is new.
    function test_sectionsOrderAndSubsetCarryThrough() {
        const kept = ConfigLib.parse(JSON.stringify({ configVersion: 8, sections: ["weather", "music"] }));
        compare(kept.config.sections, ["weather", "music"]);
        compare(kept.rewrite, null);
        const migrated = ConfigLib.parse(JSON.stringify({ configVersion: 7, sections: ["weather", "music"] }));
        compare(migrated.config.sections, ["weather", "music", "notifications"]);
        compare(migrated.rewrite.sections, ["weather", "music", "notifications"]);
    }

    // Merge rejects a list with a name it does not know (the defaults stand, with a warning); the rewrite still
    // carries the user's raw list, so the file is not made to lose it.
    function test_migrateUnknownSectionRejectedByMergeButCarried() {
        const r = ConfigLib.parse(JSON.stringify({ configVersion: 7, sections: ["weather", "bogus"] }));
        compare(r.config.sections, ConfigLib.SECTIONS);
        compare(r.warnings.length, 1);
        compare(r.rewrite, { configVersion: 8, sections: ["weather", "bogus", "notifications"] });
    }

    function test_migrateIgnoresNonObjects() {
        compare(ConfigLib.migrate([1, 2]).changed, false);
        compare(ConfigLib.migrate(null).changed, false);
        compare(ConfigLib.parse("[]").rewrite, null);
    }

    function test_first_run_writes_the_defaults() {
        const text = ConfigLib.firstRun();
        verify(text.length > 0);
        verify(text.endsWith("}\n"));
        compare(JSON.parse(text), ConfigLib.defaults());
        // An argument (the old Island text) is ignored.
        compare(ConfigLib.firstRun(JSON.stringify({ hoverDelay: 400 })), text);
    }

    // The seeded config and a migration rewrite share one format: two spaces, final newline.
    function test_first_run_is_indented_by_two_spaces() {
        const text = ConfigLib.firstRun();
        verify(text.startsWith('{\n  "'));
        compare(text, ConfigLib.serialize(ConfigLib.defaults()));
    }

    function test_serialize_ends_with_newline_and_round_trips() {
        const config = { width: 300, sections: ["music", "mixer"], theme: { mode: "dark" } };
        const text = ConfigLib.serialize(config);
        compare(JSON.parse(text), config);
        compare(text, '{\n  "width": 300,\n  "sections": [\n    "music",\n    "mixer"\n  ],\n  "theme": {\n    "mode": "dark"\n  }\n}\n');
    }

    function test_serialize_of_a_migration_rewrite() {
        const r = ConfigLib.parse(JSON.stringify({ width: 300 }));
        const text = ConfigLib.serialize(r.rewrite);
        compare(text, '{\n  "width": 300,\n  "configVersion": 8\n}\n');
        // What the migration writes back parses to no further change.
        compare(ConfigLib.parse(text).rewrite, null);
    }

    function test_shadowDefaults() {
        const d = ConfigLib.defaults();
        compare(d.shadow.color, "teal");
        compare(d.shadow.keyline, 0);
        compare(d.shadow.offset, 3);
    }

    function test_shadowValidValues() {
        let r = ConfigLib.merge({ shadow: { color: "focusBorder", keyline: 2, offset: 8 } });
        compare(r.config.shadow, { color: "focusBorder", keyline: 2, offset: 8 });
        compare(r.warnings.length, 0);
        r = ConfigLib.merge({ shadow: { color: "ink", offset: 0 } });
        compare(r.config.shadow, { color: "ink", keyline: 0, offset: 0 });
        compare(r.warnings.length, 0);
        compare(ConfigLib.merge({ shadow: { color: "coral" } }).config.shadow.color, "coral");
    }

    function test_shadowUnknownColourFallsBack() {
        const r = ConfigLib.merge({ shadow: { color: "chartreuse", keyline: 1, offset: 5 } });
        compare(r.config.shadow, { color: "teal", keyline: 1, offset: 5 });
        compare(r.warnings.length, 1);
    }

    function test_shadowKeylineOutOfRange() {
        for (const k of [3, -1]) {
            const r = ConfigLib.merge({ shadow: { keyline: k, offset: 5 } });
            compare(r.config.shadow.keyline, 0, `keyline ${k}`);
            compare(r.config.shadow.offset, 5, `offset with keyline ${k}`);
            compare(r.warnings.length, 1, `warnings for keyline ${k}`);
        }
    }

    function test_shadowNegativeOffset() {
        for (const o of [-2, 9, "4"]) {
            const r = ConfigLib.merge({ shadow: { offset: o } });
            compare(r.config.shadow.offset, 3, `offset ${o}`);
            compare(r.warnings.length, 1, `warnings for offset ${o}`);
        }
    }

    function test_shadowFractionRounds() {
        const r = ConfigLib.merge({ shadow: { offset: 2.6, keyline: 1.4 } });
        compare(r.config.shadow.offset, 3);
        compare(r.config.shadow.keyline, 1);
        compare(r.warnings.length, 0);
    }

    function test_shadowNotAnObject() {
        const r = ConfigLib.merge({ shadow: "teal" });
        compare(r.config.shadow, { color: "teal", keyline: 0, offset: 3 });
    }

    function test_launcherDefaults() {
        const d = ConfigLib.defaults();
        compare(d.launcher.terminal, "foot");
        compare(d.launcher.maxRows, 8);
    }

    function test_launcherValidValues() {
        const r = ConfigLib.merge({ launcher: { maxRows: 12, terminal: "kitty" } });
        compare(r.config.launcher, { terminal: "kitty", maxRows: 12 });
        compare(r.warnings.length, 0);
    }

    function test_launcherOneValidField() {
        const rows = ConfigLib.merge({ launcher: { maxRows: 6 } });
        compare(rows.config.launcher, { terminal: "foot", maxRows: 6 });
        compare(rows.warnings.length, 0);
        const term = ConfigLib.merge({ launcher: { terminal: "kitty" } });
        compare(term.config.launcher, { terminal: "kitty", maxRows: 8 });
        compare(term.warnings.length, 0);
    }

    function test_launcherMaxRowsOutOfRange() {
        for (const n of [3, 13]) {
            const r = ConfigLib.merge({ launcher: { maxRows: n } });
            compare(r.config.launcher.maxRows, 8, `maxRows ${n}`);
            compare(r.config.launcher.terminal, "foot", `terminal with maxRows ${n}`);
            compare(r.warnings.length, 1, `warnings for maxRows ${n}`);
        }
        const kept = ConfigLib.merge({ launcher: { maxRows: 13, terminal: "kitty" } });
        compare(kept.config.launcher, { terminal: "kitty", maxRows: 8 });
        compare(kept.warnings.length, 1);
    }

    function test_launcherTerminalNotAString() {
        const r = ConfigLib.merge({ launcher: { terminal: 5 } });
        compare(r.config.launcher.terminal, "foot");
        compare(r.config.launcher.maxRows, 8);
        compare(r.warnings.length, 1);
        const kept = ConfigLib.merge({ launcher: { terminal: 5, maxRows: 12 } });
        compare(kept.config.launcher, { terminal: "foot", maxRows: 12 });
        compare(kept.warnings.length, 1);
    }

    function test_lockscreenDefaults() {
        const d = ConfigLib.defaults();
        compare(d.lockscreen, {
            enabled: true,
            idle: { lock: 180, screenOff: 300, inhibitWhenAudio: true, lockBeforeSleep: true },
            fingerprint: true
        });
    }

    function test_lockscreenPartialKeepsOtherDefaults() {
        const r = ConfigLib.merge({ lockscreen: { idle: { lock: 60 } } });
        compare(r.config.lockscreen.idle.lock, 60);
        compare(r.config.lockscreen.idle.screenOff, 300);
        compare(r.config.lockscreen.idle.inhibitWhenAudio, true);
        compare(r.config.lockscreen.idle.lockBeforeSleep, true);
        compare(r.config.lockscreen.enabled, true);
        compare(r.config.lockscreen.fingerprint, true);
        compare(r.warnings.length, 0);
    }

    function test_lockscreenIdleLockInvalid() {
        for (const n of [-1, 86401, "x"]) {
            const r = ConfigLib.merge({ lockscreen: { idle: { lock: n } } });
            compare(r.config.lockscreen.idle.lock, 180, `lock ${n}`);
            compare(r.warnings.length, 1, `warnings for lock ${n}`);
        }
    }

    function test_lockscreenEnabledNotABool() {
        const r = ConfigLib.merge({ lockscreen: { enabled: "yes" } });
        compare(r.config.lockscreen.enabled, true);
        compare(r.warnings.length, 1);
    }

    function test_lockscreenZeroIsKept() {
        const r = ConfigLib.merge({ lockscreen: { idle: { screenOff: 0, lock: 0 } } });
        compare(r.config.lockscreen.idle.screenOff, 0);
        compare(r.config.lockscreen.idle.lock, 0);
        compare(r.warnings.length, 0);
    }
}
