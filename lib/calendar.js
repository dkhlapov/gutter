.pragma library

// ISO 8601 week: weeks start on Monday; week 1 holds the year's first Thursday.
function isoWeek(date) {
    const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
    const day = d.getUTCDay() || 7;
    d.setUTCDate(d.getUTCDate() + 4 - day);
    return Math.ceil(((d - Date.UTC(d.getUTCFullYear(), 0, 1)) / 86400000 + 1) / 7);
}

function dayOfYear(date) {
    return Math.round((Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) - Date.UTC(date.getFullYear(), 0, 1)) / 86400000) + 1;
}

function daysInYear(year) {
    return new Date(year, 1, 29).getMonth() === 1 ? 366 : 365;
}

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

// Only the rows the month needs (4–6); each row carries the ISO week of its Monday.
function monthRows(year, month, weekStart) {
    const offset = (new Date(year, month, 1).getDay() - weekStart + 7) % 7;
    const count = Math.ceil((offset + new Date(year, month + 1, 0).getDate()) / 7);
    const monday = (1 - weekStart + 7) % 7;
    const rows = [];
    for (let r = 0; r < count; r++) {
        const cells = [];
        for (let c = 0; c < 7; c++) {
            const d = new Date(year, month, 1 - offset + r * 7 + c);
            cells.push({ year: d.getFullYear(), month: d.getMonth(), day: d.getDate(), inMonth: d.getMonth() === month, weekday: d.getDay() });
        }
        const m = cells[monday];
        rows.push({ week: isoWeek(new Date(m.year, m.month, m.day)), cells });
    }
    return rows;
}

function weekdays(weekStart) {
    const out = [];
    for (let i = 0; i < 7; i++)
        out.push((weekStart + i) % 7);
    return out;
}

function sameDay(cell, date) {
    return cell.year === date.getFullYear() && cell.month === date.getMonth() && cell.day === date.getDate();
}

function shiftMonth(year, month, delta) {
    const d = new Date(year, month + delta, 1);
    return { year: d.getFullYear(), month: d.getMonth() };
}

// Clock hand rotations in degrees clockwise from 12; hours and minutes move continuously.
function handAngles(h, m, s) {
    return {
        hour: Math.round(((h % 12) + m / 60) * 30 * 10) / 10,
        minute: Math.round((m + s / 60) * 6 * 10) / 10,
        second: s * 6
    };
}
