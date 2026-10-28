pragma Singleton

import QtQuick
import Quickshell
import qs.settings
import "../lib/weather.js" as WeatherLib

Singleton {
    id: root

    property var data: null
    property var airQuality: null
    property string place: ""
    property real updatedAt: 0
    property bool stale: false
    property string error: ""
    property int generation: 0
    property int failures: 0
    // The last place resolved ({ lat, lon }), by the forecast's lookup or locate(); null until one succeeds.
    property var location: null
    property int locateSeq: 0
    // The forecast is fetched only while a tab that shows weather is configured. The location lookup (geocoding
    // weather.location, else the IP lookup) also runs without one: ThemeMode calls locate() for sun mode's sunrise
    // and sunset at each start, when weather.location changes, and hourly while no location is known.
    readonly property bool needed: WeatherLib.needed(Settings.sections)
    readonly property string windUnit: Settings.weather.units === "imperial" ? "mph" : "km/h"
    readonly property string key: `${Settings.weather.location}|${Settings.weather.units}`

    // A request that hangs fails after this long instead of stalling the chain until the next refresh.
    readonly property int timeoutMs: 20000

    function get(url: string, onOk: var, onFail: var): void {
        const gen = generation;
        request(url, onOk, onFail, () => WeatherLib.isCurrent(gen, generation));
    }

    // current() says whether the answer is still wanted: get() drops one a newer refresh superseded.
    function request(url: string, onOk: var, onFail: var, current: var): void {
        const xhr = new XMLHttpRequest();
        // Settled once: by the response or by the watchdog, whichever comes first.
        let done = false;
        const watchdog = watchdogComponent.createObject(root);
        watchdog.triggered.connect(() => {
            watchdog.destroy();
            if (done)
                return;
            done = true;
            xhr.abort();
            if (current())
                onFail("timed out");
        });
        watchdog.start();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || done)
                return;
            done = true;
            watchdog.stop();
            watchdog.destroy();
            // A newer refresh (e.g. settings loaded or changed) supersedes this request.
            if (!current())
                return;
            if (xhr.status !== 200) {
                onFail(`HTTP ${xhr.status}`);
                return;
            }
            let json;
            try {
                json = JSON.parse(xhr.responseText);
            } catch (e) {
                onFail("bad response");
                return;
            }
            onOk(json);
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function fail(reason: string): void {
        console.warn("gutter: weather:", reason);
        if (data)
            stale = true;
        else
            error = "Weather unavailable";
        failures++;
        retry.interval = WeatherLib.retryDelay(failures);
        retry.restart();
    }

    // Air quality is optional: a failure only blanks the Air tile, it never marks the forecast stale.
    function fetchAir(loc: var): void {
        get(WeatherLib.airUrl(loc.lat, loc.lon), json => {
            airQuality = WeatherLib.parseAir(json);
        }, reason => {
            console.warn("gutter: air quality:", reason);
            airQuality = null;
        });
    }

    function fetchForecast(loc: var): void {
        get(WeatherLib.forecastUrl(loc.lat, loc.lon, Settings.weather.units), json => {
            const parsed = WeatherLib.parseForecast(json, Date.now());
            if (!parsed) {
                fail("unexpected forecast");
                return;
            }
            data = parsed;
            place = loc.name;
            updatedAt = Date.now();
            stale = false;
            error = "";
            failures = 0;
            fetchAir(loc);
        }, fail);
    }

    function setLocation(loc: var): void {
        if (!location || location.lat !== loc.lat || location.lon !== loc.lon)
            location = { lat: loc.lat, lon: loc.lon };
    }

    // The geocode of weather.location, else the IP lookup; onOk gets { lat, lon, name }. Also sets location.
    function lookup(onOk: var, onFail: var, current: var): void {
        const city = Settings.weather.location;
        const found = loc => {
            setLocation(loc);
            onOk(loc);
        };
        if (city) {
            request(WeatherLib.geocodeUrl(city), json => {
                const loc = WeatherLib.parseGeocode(json);
                loc ? found(loc) : onFail(`unknown city ${city}`);
            }, onFail, current);
        } else {
            // Plain http: ip-api's free tier has no https.
            request(WeatherLib.IP_URL, json => {
                const loc = WeatherLib.parseIpApi(json);
                loc ? found(loc) : onFail("IP location failed");
            }, onFail, current);
        }
    }

    // Resolves location only, without the forecast, so it works with no weather tab configured (for ThemeMode's
    // sun times). Never bumps the generation, so it cannot cancel a refresh, and a refresh cannot cancel it. A newer
    // locate (weather.location changed) supersedes an older one still in flight.
    function locate(): void {
        const seq = ++locateSeq;
        lookup(() => {}, reason => console.warn("gutter: weather: cannot locate:", reason), () => seq === locateSeq);
    }

    function refresh(): void {
        generation++;
        retry.stop();
        if (!needed)
            return;
        const gen = generation;
        lookup(fetchForecast, fail, () => WeatherLib.isCurrent(gen, generation));
    }

    onKeyChanged: refresh()
    onNeededChanged: {
        if (!needed)
            refresh(); // drops in-flight requests and the retry
    }

    // Starts (and fires at once) whenever `needed` becomes true.
    Timer {
        running: root.needed
        repeat: true
        triggeredOnStart: true
        interval: 30 * 60 * 1000
        onTriggered: root.refresh()
    }

    Component {
        id: watchdogComponent

        Timer {
            interval: root.timeoutMs
        }
    }

    Timer {
        id: retry

        onTriggered: root.refresh()
    }
}
