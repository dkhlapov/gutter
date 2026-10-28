.pragma library

var IP_URL = "http://ip-api.com/json?fields=status,lat,lon,city";

var CONDITIONS = {
    0: "Clear", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
    45: "Fog", 48: "Fog",
    51: "Drizzle", 53: "Drizzle", 55: "Drizzle", 56: "Freezing drizzle", 57: "Freezing drizzle",
    61: "Light rain", 63: "Rain", 65: "Heavy rain", 66: "Freezing rain", 67: "Freezing rain",
    71: "Light snow", 73: "Snow", 75: "Heavy snow", 77: "Snow grains",
    80: "Showers", 81: "Showers", 82: "Heavy showers", 85: "Snow showers", 86: "Heavy snow showers",
    95: "Thunderstorm", 96: "Thunderstorm with hail", 99: "Thunderstorm with hail"
};

// Material Symbol names for the WMO weather codes, with night variants.
var ICONS = {
    0: "clear_day", 1: "clear_day", 2: "partly_cloudy_day", 3: "cloud",
    45: "foggy", 48: "foggy",
    51: "rainy", 53: "rainy", 55: "rainy", 56: "rainy", 57: "rainy",
    61: "rainy", 63: "rainy", 65: "rainy", 66: "rainy", 67: "rainy",
    71: "cloudy_snowing", 73: "cloudy_snowing", 75: "snowing_heavy", 77: "cloudy_snowing",
    80: "rainy", 81: "rainy", 82: "rainy", 85: "cloudy_snowing", 86: "snowing_heavy",
    95: "thunderstorm", 96: "thunderstorm", 99: "thunderstorm"
};

var NIGHT = { clear_day: "clear_night", partly_cloudy_day: "partly_cloudy_night" };

function forecastUrl(lat, lon, units) {
    const params = [
        "latitude=" + lat,
        "longitude=" + lon,
        "current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,wind_gusts_10m,uv_index,pressure_msl",
        "hourly=weather_code,temperature_2m,precipitation_probability,is_day",
        "daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset",
        "timezone=auto",
        "forecast_days=8"
    ];
    if (units === "imperial")
        params.push("temperature_unit=fahrenheit", "wind_speed_unit=mph");
    return "https://api.open-meteo.com/v1/forecast?" + params.join("&");
}

function airUrl(lat, lon) {
    return `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${lat}&longitude=${lon}&current=european_aqi`;
}

function parseAir(json) {
    const v = json && json.current ? json.current.european_aqi : null;
    return typeof v === "number" ? v : null;
}

function aqiWord(v) {
    if (v <= 20)
        return "good";
    if (v <= 40)
        return "fair";
    if (v <= 60)
        return "moderate";
    if (v <= 80)
        return "poor";
    if (v <= 100)
        return "very poor";
    return "extremely poor";
}

function uvWord(v) {
    const r = Math.round(v);
    if (r < 3)
        return "low";
    if (r < 6)
        return "moderate";
    if (r < 8)
        return "high";
    if (r < 11)
        return "very high";
    return "extreme";
}

function isRainy(code) {
    const name = ICONS[code];
    return name === "rainy" || name === "thunderstorm";
}

// Tabs that show weather; without one of them nothing is fetched (not even the IP lookup).
function needed(sections) {
    return sections.some(s => s === "overview" || s === "weather" || s === "calendar");
}

// Where a day's low..high sits on the week's lo..hi scale.
function rangeFractions(min, max, lo, hi) {
    if (hi <= lo)
        return { from: 0, to: 1 };
    return { from: (min - lo) / (hi - lo), to: (max - lo) / (hi - lo) };
}

// The week's temperature scale for the range bars.
function weekBounds(week) {
    if (week.length === 0)
        return { lo: 0, hi: 0 };
    return { lo: Math.min(...week.map(d => d.min)), hi: Math.max(...week.map(d => d.max)) };
}

function sunTime(list, i, offsetSeconds) {
    const t = list ? list[i] : null;
    return t ? { ms: hourStart(t, offsetSeconds), text: t.slice(11, 16) } : null;
}

function day(d, i, offsetSeconds) {
    const pops = d.precipitation_probability_max;
    return {
        date: d.time[i],
        max: d.temperature_2m_max[i],
        min: d.temperature_2m_min[i],
        code: d.weather_code[i],
        pop: (pops && pops[i]) || 0,
        sunrise: sunTime(d.sunrise, i, offsetSeconds),
        sunset: sunTime(d.sunset, i, offsetSeconds)
    };
}

function parseForecast(json, nowMs) {
    if (!json || !json.current || !json.hourly || !json.hourly.time || !json.daily || !json.daily.time || json.daily.time.length === 0)
        return null;
    const c = json.current;
    const off = json.utc_offset_seconds;
    const current = {
        temp: c.temperature_2m,
        feels: c.apparent_temperature,
        humidity: c.relative_humidity_2m,
        wind: c.wind_speed_10m,
        gusts: c.wind_gusts_10m,
        uv: c.uv_index,
        pressure: c.pressure_msl,
        code: c.weather_code,
        isDay: c.is_day === 1
    };
    const h = json.hourly;
    const hourly = [];
    for (let i = 0; i < h.time.length && hourly.length < 8; i++) {
        // Times are local to the location (timezone=auto); keep the current hour onwards.
        if (hourStart(h.time[i], off) + 3600000 <= nowMs)
            continue;
        hourly.push({
            time: h.time[i],
            hour: h.time[i].slice(11, 13),
            temp: h.temperature_2m[i],
            code: h.weather_code[i],
            pop: h.precipitation_probability[i] || 0,
            isDay: h.is_day ? h.is_day[i] === 1 : true
        });
    }
    // The current hour's column is "Now": show current conditions there so it matches the hero.
    if (hourly.length > 0 && hourStart(hourly[0].time, off) <= nowMs)
        Object.assign(hourly[0], { temp: current.temp, code: current.code, isDay: current.isDay });
    const week = [];
    for (let i = 1; i < json.daily.time.length && week.length < 7; i++)
        week.push(day(json.daily, i, off));
    return { current, hourly, today: day(json.daily, 0, off), week };
}

function geocodeUrl(city) {
    return "https://geocoding-api.open-meteo.com/v1/search?count=1&format=json&name=" + encodeURIComponent(city);
}

function parseGeocode(json) {
    const r = json && json.results && json.results[0];
    return r ? { lat: r.latitude, lon: r.longitude, name: r.name } : null;
}

function parseIpApi(json) {
    return json && json.status === "success" ? { lat: json.lat, lon: json.lon, name: json.city } : null;
}

// Epoch ms of a location-local "YYYY-MM-DDTHH:MM" time; without an offset, assume this machine's zone.
function hourStart(time, offsetSeconds) {
    return offsetSeconds === undefined ? Date.parse(time) : Date.parse(time + ":00Z") - offsetSeconds * 1000;
}

function condition(code) {
    return CONDITIONS[code] || "Unknown";
}

function icon(code, isDay) {
    const name = ICONS[code] || "air";
    return isDay ? name : (NIGHT[name] || name);
}

function isCurrent(gen, current) {
    return gen === current;
}

// Delay before retry number `failures` (1-based): 30 s, 1 min, 2 min, then every 5 min.
function retryDelay(failures) {
    return [30000, 60000, 120000][failures - 1] || 300000;
}
