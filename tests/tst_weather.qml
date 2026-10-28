import QtQuick
import QtTest
import "../lib/weather.js" as W

TestCase {
    name: "Weather"

    function pad(n) {
        return n < 10 ? "0" + n : String(n);
    }

    function forecast() {
        const days = ["2026-10-14", "2026-10-15", "2026-10-16", "2026-10-17", "2026-10-18", "2026-10-19", "2026-10-20", "2026-10-21"];
        const hours = [];
        for (let h = 12; h < 24; h++)
            hours.push(`2026-10-14T${h}:00`);
        return {
            current: { temperature_2m: 14.2, apparent_temperature: 12.9, relative_humidity_2m: 71, wind_speed_10m: 9.4, wind_gusts_10m: 21.6, uv_index: 2.4, pressure_msl: 1012.3, weather_code: 3, is_day: 1 },
            hourly: {
                time: hours,
                temperature_2m: [13, 14, 15, 14, 13, 12, 11, 10, 10, 9, 9, 8],
                weather_code: [2, 3, 61, 3, 2, 0, 0, 1, 2, 3, 3, 3],
                precipitation_probability: [0, 10, 60, 20, null, 0, 0, 0, 5, 5, 5, 5],
                is_day: [1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0]
            },
            daily: {
                time: days,
                temperature_2m_max: [16, 17, 15, 14, 13, 12, 18, 19],
                temperature_2m_min: [8, 9, 7, 6, 5, 4, 10, 11],
                weather_code: [3, 61, 0, 1, 2, 95, 3, 0],
                precipitation_probability_max: [20, 80, 0, 10, 15, 90, 30, null],
                sunrise: days.map((d, i) => `${d}T07:${pad(41 + 2 * i)}`),
                sunset: days.map((d, i) => `${d}T18:${pad(22 - 2 * i)}`)
            }
        };
    }

    function test_forecastUrlFields() {
        const m = W.forecastUrl(52.5, 13.4, "metric");
        verify(m.indexOf("latitude=52.5") !== -1 && m.indexOf("longitude=13.4") !== -1);
        for (const f of ["wind_gusts_10m", "uv_index", "pressure_msl", "is_day", "sunrise", "sunset", "precipitation_probability_max", "forecast_days=8"])
            verify(m.indexOf(f) !== -1, f);
        verify(m.indexOf("fahrenheit") === -1);
        const i = W.forecastUrl(52.5, 13.4, "imperial");
        verify(i.indexOf("temperature_unit=fahrenheit") !== -1 && i.indexOf("wind_speed_unit=mph") !== -1);
    }

    function test_geocodeUrlEncodes() {
        verify(W.geocodeUrl("São Paulo").indexOf("name=S%C3%A3o%20Paulo") !== -1);
    }

    function test_parseGeocode() {
        compare(W.parseGeocode({ results: [{ latitude: 1, longitude: 2, name: "X" }] }), { lat: 1, lon: 2, name: "X" });
        compare(W.parseGeocode({}), null);
    }

    function test_parseIpApi() {
        compare(W.parseIpApi({ status: "success", lat: 1, lon: 2, city: "Y" }), { lat: 1, lon: 2, name: "Y" });
        compare(W.parseIpApi({ status: "fail" }), null);
    }

    function test_parseCurrent() {
        const c = W.parseForecast(forecast(), Date.parse("2026-10-14T13:30")).current;
        compare(c, { temp: 14.2, feels: 12.9, humidity: 71, wind: 9.4, gusts: 21.6, uv: 2.4, pressure: 1012.3, code: 3, isDay: true });
    }

    function test_hourlyFromCurrentHourEightEntries() {
        const h = W.parseForecast(forecast(), Date.parse("2026-10-14T13:30")).hourly;
        compare(h.length, 8);
        compare(h.map(x => x.hour), ["13", "14", "15", "16", "17", "18", "19", "20"]);
        compare(h[1], { time: "2026-10-14T14:00", hour: "14", temp: 15, code: 61, pop: 60, isDay: true });
        compare(h[6].isDay, false);
    }

    // "Now" shows current conditions so it matches the hero; its rain chance stays hourly.
    function test_nowColumnUsesCurrent() {
        const f = forecast();
        f.current.temperature_2m = 16.6;
        f.current.weather_code = 0;
        f.current.is_day = 0;
        const h = W.parseForecast(f, Date.parse("2026-10-14T13:30")).hourly;
        compare(h[0], { time: "2026-10-14T13:00", hour: "13", temp: 16.6, code: 0, pop: 10, isDay: false });
        compare(h[1].temp, 15);
        // Before the first forecast hour there is no current-hour column to replace.
        compare(W.parseForecast(f, Date.parse("2026-10-14T11:30")).hourly[0].temp, 13);
    }

    // Review focus 2: Open-Meteo sends null for some probabilities.
    function test_nullProbabilityBecomesZero() {
        const r = W.parseForecast(forecast(), Date.parse("2026-10-14T13:30"));
        compare(r.hourly[3].pop, 0);
        compare(r.week[6].pop, 0);
    }

    function test_todayAndWeekSplit() {
        const r = W.parseForecast(forecast(), Date.parse("2026-10-14T13:30"));
        compare(r.today.date, "2026-10-14");
        compare([r.today.max, r.today.min, r.today.code, r.today.pop], [16, 8, 3, 20]);
        compare(r.today.sunrise, { ms: Date.parse("2026-10-14T07:41"), text: "07:41" });
        compare(r.today.sunset.text, "18:22");
        compare(r.week.length, 7);
        compare(r.week[0].date, "2026-10-15");
        compare(r.week[0].sunrise.text, "07:43");
        compare(r.week[6].date, "2026-10-21");
    }

    // Review focus 2: older or partial responses without sun times.
    function test_missingSunTimesAreNull() {
        const f = forecast();
        delete f.daily.sunrise;
        delete f.daily.sunset;
        delete f.daily.precipitation_probability_max;
        const r = W.parseForecast(f, Date.parse("2026-10-14T13:30"));
        compare(r.today.sunrise, null);
        compare(r.today.sunset, null);
        compare(r.today.pop, 0);
    }

    // Times are local to the forecast location, which can differ from this machine's timezone.
    function test_parseForecastUsesLocationOffset() {
        const f = forecast();
        f.utc_offset_seconds = 3600;
        f.hourly.time = f.hourly.time.map((t, i) => `2026-10-14T${pad(15 + i)}:00`).slice(0, 9).concat(["2026-10-15T00:00", "2026-10-15T01:00", "2026-10-15T02:00"]);
        // 15:10 UTC is 16:10 at the location.
        const r = W.parseForecast(f, Date.parse("2026-10-14T15:10:00Z"));
        compare(r.hourly[0].time, "2026-10-14T16:00");
        compare(r.today.sunrise.ms, Date.parse("2026-10-14T07:41:00Z") - 3600000);
    }

    function test_parseForecastRejectsIncomplete() {
        compare(W.parseForecast({ current: {} }, 0), null);
        compare(W.parseForecast(null, 0), null);
        const f = forecast();
        f.daily.time = [];
        compare(W.parseForecast(f, 0), null);
    }

    function test_icons() {
        compare(W.icon(0, true), "clear_day");
        compare(W.icon(0, false), "clear_night");
        compare(W.icon(2, false), "partly_cloudy_night");
        compare(W.icon(61, true), "rainy");
        compare(W.icon(75, true), "snowing_heavy");
        compare(W.icon(95, true), "thunderstorm");
        compare(W.icon(12345, true), "air");
    }

    function test_isRainy() {
        verify(W.isRainy(61));
        verify(W.isRainy(53));
        verify(W.isRainy(95));
        verify(!W.isRainy(3));
        verify(!W.isRainy(71));
    }

    function test_condition() {
        compare(W.condition(3), "Overcast");
        compare(W.condition(12345), "Unknown");
    }

    function test_airQuality() {
        const u = W.airUrl(52.5, 13.4);
        verify(u.indexOf("https://air-quality-api.open-meteo.com/v1/air-quality?") === 0);
        verify(u.indexOf("latitude=52.5") !== -1 && u.indexOf("current=european_aqi") !== -1);
        compare(W.parseAir({ current: { european_aqi: 24 } }), 24);
        compare(W.parseAir({ current: { european_aqi: null } }), null);
        compare(W.parseAir({}), null);
        compare(W.parseAir(null), null);
    }

    function test_aqiWordBoundaries() {
        compare([0, 20, 21, 40, 41, 60, 61, 80, 81, 100, 101].map(v => W.aqiWord(v)),
            ["good", "good", "fair", "fair", "moderate", "moderate", "poor", "poor", "very poor", "very poor", "extremely poor"]);
    }

    function test_uvWord() {
        compare([0, 2.4, 2.6, 5, 6, 7, 8, 10, 11].map(v => W.uvWord(v)),
            ["low", "low", "moderate", "moderate", "high", "high", "very high", "very high", "extreme"]);
    }

    function test_needed() {
        verify(!W.needed(["music", "system"]));
        verify(W.needed(["calendar"]));
        verify(W.needed(["overview", "music"]));
        verify(W.needed(["weather"]));
    }

    function test_rangeFractions() {
        const r = W.rangeFractions(8, 13, 4, 19);
        compare(Math.round(r.from * 100), 27);
        compare(Math.round(r.to * 100), 60);
        compare(W.rangeFractions(5, 5, 5, 5), { from: 0, to: 1 });
    }

    function test_onlyCurrentGenerationApplies() {
        verify(W.isCurrent(3, 3));
        verify(!W.isCurrent(2, 3));
    }

    function test_retryBackoff() {
        compare([1, 2, 3, 4, 9].map(n => W.retryDelay(n)), [30000, 60000, 120000, 300000, 300000]);
    }

    function test_weekBounds() {
        compare(W.weekBounds([{ min: 8, max: 13 }, { min: 7, max: 20 }, { min: 10, max: 14 }]), { lo: 7, hi: 20 });
        compare(W.weekBounds([]), { lo: 0, hi: 0 });
    }
}
