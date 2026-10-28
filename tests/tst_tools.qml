import QtQuick
import QtTest
import "../lib/tools.js" as T

TestCase {
    name: "Tools"

    function test_clockRoundsUp() {
        compare(T.clock(0), "0:00");
        compare(T.clock(1), "0:01");
        compare(T.clock(299001), "5:00");
        compare(T.clock(299000), "4:59");
        compare(T.clock(3723000), "1:02:03");
        compare(T.clock(-5), "0:00");
    }

    function test_stopwatchClockShowsTenths() {
        compare(T.stopwatchClock(0), "0:00.0");
        compare(T.stopwatchClock(7390), "0:07.3");
        compare(T.stopwatchClock(3723450), "1:02:03.4");
    }

    function test_spoken() {
        compare(T.spoken(45000), "45 s");
        compare(T.spoken(300000), "5 min");
        compare(T.spoken(5400000), "1 h 30 min");
        compare(T.spoken(7200000), "2 h");
    }

    // Minutes round before hours split off: never "60 min" or "1 h 60 min".
    function test_spokenRoundsUpToTheHour() {
        compare(T.spoken(3570000), "1 h");
        compare(T.spoken(7170000), "2 h");
        compare(T.spoken(3660000), "1 h 1 min");
        compare(T.spoken(89000), "1 min");
    }

    function test_timerRunsAndFinishes() {
        let t = T.timerStart(60000, 1000);
        compare(t.state, "running");
        compare(T.timerLeft(t, 31000), 30000);
        compare(T.timerFraction(t, 31000), 0.5);
        compare(T.timerCheck(t, 60999).state, "running");
        t = T.timerCheck(t, 61000);
        compare(t.state, "done");
        compare(t.durationMs, 60000);
        compare(T.timerLeft(t, 70000), 0);
    }

    function test_timerZeroIsIdle() {
        compare(T.timerStart(0, 1000).state, "idle");
    }

    function test_timerCappedAtADay() {
        compare(T.timerStart(T.MAX_TIMER_MS * 2, 0).durationMs, T.MAX_TIMER_MS);
    }

    function test_timerPauseKeepsTimeLeft() {
        let t = T.timerStart(60000, 0);
        t = T.timerPause(t, 20000);
        compare(t.state, "paused");
        compare(T.timerLeft(t, 99999), 40000);
        // Paused timers never finish.
        compare(T.timerCheck(t, 999999).state, "paused");
        t = T.timerResume(t, 100000);
        compare(t.state, "running");
        compare(t.endsAt, 140000);
    }

    function test_timerToggle() {
        let t = T.timerStart(60000, 0);
        t = T.timerToggle(t, 10000);
        compare(t.state, "paused");
        t = T.timerToggle(t, 20000);
        compare(t.state, "running");
        compare(T.timerLeft(t, 20000), 50000);
        // Idle and done timers are left alone.
        compare(T.timerToggle(T.timerIdle(), 0).state, "idle");
    }

    function test_timerAddLengthensTotal() {
        let t = T.timerStart(60000, 0);
        t = T.timerAdd(t, 60000, 30000);
        compare(T.timerLeft(t, 30000), 90000);
        compare(t.durationMs, 120000);
        t = T.timerAdd(T.timerPause(t, 30000), 60000, 40000);
        compare(t.state, "paused");
        compare(t.leftMs, 150000);
        // +1 min with no timer starts a one-minute timer.
        compare(T.timerAdd(T.timerIdle(), 60000, 5).endsAt, 60005);
    }

    function test_stopwatchAccumulatesAcrossPauses() {
        let sw = T.stopwatchIdle();
        verify(!T.stopwatchActive(sw));
        sw = T.stopwatchToggle(sw, 1000);
        compare(T.stopwatchElapsed(sw, 4000), 3000);
        sw = T.stopwatchToggle(sw, 4000);
        compare(T.stopwatchElapsed(sw, 99000), 3000);
        verify(T.stopwatchActive(sw));
        sw = T.stopwatchToggle(sw, 100000);
        compare(T.stopwatchElapsed(sw, 102000), 5000);
    }

    function test_stopwatchLapsNewestFirst() {
        let sw = T.stopwatchToggle(T.stopwatchIdle(), 0);
        sw = T.stopwatchLap(sw, 1500);
        sw = T.stopwatchLap(sw, 4000);
        compare(sw.laps, [4000, 1500]);
        // No laps while paused.
        compare(T.stopwatchLap(T.stopwatchToggle(sw, 5000), 6000).laps.length, 2);
    }

    function test_notesParseValidates() {
        compare(T.notesParse("{"), null);
        compare(T.notesParse("[]"), T.notesEmpty());
        compare(T.notesParse(JSON.stringify({ notes: [] })), T.notesEmpty());
        const s = T.notesParse(JSON.stringify({ notes: [{ text: "a" }, { bogus: 1 }, { text: "b" }], current: 7 }));
        compare(s.notes, [{ text: "a" }, { text: "b" }]);
        compare(s.current, 1);
    }

    function test_notesParseCapsCount() {
        const many = [];
        for (let i = 0; i < 12; i++)
            many.push({ text: String(i) });
        compare(T.notesParse(JSON.stringify({ notes: many })).notes.length, T.MAX_NOTES);
    }

    function test_notesTitle() {
        compare(T.notesTitle("", 0), "Note 1");
        compare(T.notesTitle("\n  \n  Shopping list \nmilk", 2), "Shopping list");
        compare(T.notesTitle("## Ideas", 0), "Ideas");
    }

    function test_notesAddAndSelect() {
        let s = T.notesAdd(T.notesEmpty());
        compare(s.notes.length, 2);
        compare(s.current, 1);
        s = T.notesSelect(s, 9);
        compare(s.current, 1);
        s = T.notesSetText(s, 0, "hello");
        compare(s.notes[0].text, "hello");
        compare(s.current, 1);
    }

    function test_notesAddStopsAtMax() {
        let s = T.notesEmpty();
        for (let i = 0; i < 20; i++)
            s = T.notesAdd(s);
        compare(s.notes.length, T.MAX_NOTES);
    }

    function test_notesRemoveKeepsSelectionSensible() {
        const s = { notes: [{ text: "a" }, { text: "b" }, { text: "c" }], current: 1 };
        // Before the current note: the selection follows its note.
        compare(T.notesRemove(s, 0), { notes: [{ text: "b" }, { text: "c" }], current: 0 });
        // The current note: the next one takes its place.
        compare(T.notesRemove(s, 1), { notes: [{ text: "a" }, { text: "c" }], current: 1 });
        // The current note when it is last: the one before it.
        compare(T.notesRemove({ notes: s.notes, current: 2 }, 2).current, 1);
        // After the current note: unchanged.
        compare(T.notesRemove(s, 2).current, 1);
        // The only note is cleared, not removed.
        compare(T.notesRemove({ notes: [{ text: "x" }], current: 0 }, 0), T.notesEmpty());
    }
}
