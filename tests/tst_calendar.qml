import QtQuick
import QtTest
import "../lib/calendar.js" as Cal

TestCase {
    name: "Calendar"

    function test_october2026MondayStart() {
        const rows = Cal.monthRows(2026, 9, 1);
        compare(rows.length, 5);
        compare(rows.map(r => r.week), [40, 41, 42, 43, 44]);
        compare(rows[0].cells[0], { year: 2026, month: 8, day: 28, inMonth: false, weekday: 1 });
        compare(rows[0].cells[3], { year: 2026, month: 9, day: 1, inMonth: true, weekday: 4 });
        compare(rows[4].cells[6], { year: 2026, month: 10, day: 1, inMonth: false, weekday: 0 });
    }

    // With Sunday first, the week number comes from the row's Monday.
    function test_october2026SundayStart() {
        const rows = Cal.monthRows(2026, 9, 0);
        compare(rows[0].cells[0].day, 27);
        compare(rows[0].cells[4], { year: 2026, month: 9, day: 1, inMonth: true, weekday: 4 });
        compare(rows[0].week, 40);
    }

    function test_rowCountFollowsTheMonth() {
        compare(Cal.monthRows(2021, 1, 1).length, 4); // Feb 2021: starts Monday, 28 days
        compare(Cal.monthRows(2026, 7, 1).length, 6); // Aug 2026: starts Saturday
    }

    function test_monthStartingOnWeekStartHasNoLeadingDays() {
        compare(Cal.monthRows(2026, 5, 1)[0].cells[0], { year: 2026, month: 5, day: 1, inMonth: true, weekday: 1 });
    }

    function test_isoWeekAtYearEdges() {
        compare(Cal.isoWeek(new Date(2026, 11, 31)), 53);
        compare(Cal.isoWeek(new Date(2027, 0, 1)), 53);
        compare(Cal.isoWeek(new Date(2027, 0, 4)), 1);
        compare(Cal.isoWeek(new Date(2024, 11, 30)), 1);
        compare(Cal.isoWeek(new Date(2026, 9, 14)), 42);
    }

    function test_dayOfYear() {
        compare(Cal.dayOfYear(new Date(2026, 9, 14)), 287);
        compare(Cal.dayOfYear(new Date(2026, 0, 1)), 1);
        compare(Cal.dayOfYear(new Date(2026, 2, 1)), 60);
        compare(Cal.dayOfYear(new Date(2024, 2, 1)), 61);
        compare(Cal.dayOfYear(new Date(2024, 11, 31)), 366);
    }

    function test_daysInYear() {
        compare(Cal.daysInYear(2024), 366);
        compare(Cal.daysInYear(2026), 365);
        compare(Cal.daysInYear(1900), 365);
        compare(Cal.daysInYear(2000), 366);
    }

    function test_startOfDay() {
        const d = Cal.startOfDay(new Date(2026, 9, 14, 17, 42, 8));
        compare([d.getFullYear(), d.getMonth(), d.getDate(), d.getHours(), d.getMinutes()], [2026, 9, 14, 0, 0]);
    }

    function test_weekdays() {
        compare(Cal.weekdays(1), [1, 2, 3, 4, 5, 6, 0]);
        compare(Cal.weekdays(0), [0, 1, 2, 3, 4, 5, 6]);
    }

    function test_sameDay() {
        verify(Cal.sameDay({ year: 2026, month: 9, day: 14 }, new Date(2026, 9, 14, 23, 59)));
        verify(!Cal.sameDay({ year: 2026, month: 9, day: 14 }, new Date(2026, 9, 15)));
    }

    function test_shiftMonthWrapsYears() {
        compare(Cal.shiftMonth(2026, 11, 1), { year: 2027, month: 0 });
        compare(Cal.shiftMonth(2026, 0, -1), { year: 2025, month: 11 });
    }

    function test_handAngles() {
        compare(Cal.handAngles(0, 0, 0), { hour: 0, minute: 0, second: 0 });
        compare(Cal.handAngles(17, 42, 8), { hour: 171, minute: 252.8, second: 48 });
        compare(Cal.handAngles(12, 30, 0).hour, 15); // 12 wraps to the top
    }
}
