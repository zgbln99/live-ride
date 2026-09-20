import { describe, expect, it } from "vitest";
import {
    forecastAlongRoute,
    hourAt,
    sunsetInfo,
    weatherAlert,
    weatherLabel,
    windComponent,
    type WeatherSnapshot,
} from "./weather";

/**
 * Pogoda na trasie jest jedyną sekcją, która mówi coś o przyszłości, więc
 * jako jedyna może skłamać bez możliwości sprawdzenia w tej samej minucie.
 * Stąd te testy: dobór godziny po ETA i przeliczenie wiatru na to, co
 * rowerzysta poczuje, to cała treść tej sekcji.
 */

const HOUR = 3600_000;
const NOW = Date.parse("2026-05-01T12:00:00Z");

function series(from: number, values: Partial<Record<string, number>>[] = []) {
    return values.map((value, index) => ({
        at: new Date(from + index * HOUR).toISOString(),
        ...value,
    }));
}

describe("dobór godziny", () => {
    it("bierze najbliższą próbkę z serii", () => {
        const hours = series(NOW, [{ temp_c: 18 }, { temp_c: 17 }, { temp_c: 16 }]);
        expect(hourAt(hours, NOW + 10 * 60_000)?.temp_c).toBe(18);
        expect(hourAt(hours, NOW + 50 * 60_000)?.temp_c).toBe(17);
        expect(hourAt(hours, NOW + 2 * HOUR)?.temp_c).toBe(16);
    });

    it("dalej niż półtorej godziny poza serię nie zgaduje", () => {
        const hours = series(NOW, [{ temp_c: 18 }]);
        expect(hourAt(hours, NOW + 4 * HOUR)).toBeNull();
    });

    it("pusta seria to brak prognozy", () => {
        expect(hourAt([], NOW)).toBeNull();
        expect(hourAt(undefined, NOW)).toBeNull();
    });
});

describe("wiatr względem jazdy", () => {
    it("wiatr z tej strony, w którą jedziemy, jest czołowy", () => {
        // Jedziemy na wschód (90°), wieje ZE wschodu (90°).
        const wind = windComponent(18, 90, 90)!;
        expect(wind.kind).toBe("head");
        expect(wind.label).toBe("CZOŁOWY");
        expect(wind.alongKmh).toBeCloseTo(-18, 5);
        expect(wind.crossKmh).toBeCloseTo(0, 5);
    });

    it("wiatr z tyłu popycha", () => {
        const wind = windComponent(18, 270, 90)!;
        expect(wind.kind).toBe("tail");
        expect(wind.alongKmh).toBeCloseTo(18, 5);
    });

    it("wiatr z boku nie jest ani czołowy, ani tylny", () => {
        const wind = windComponent(18, 180, 90)!;
        expect(wind.kind).toBe("cross");
        expect(wind.crossKmh).toBeCloseTo(18, 5);
        expect(Math.abs(wind.alongKmh)).toBeLessThan(0.001);
    });

    it("skos rozkłada się na obie składowe", () => {
        const wind = windComponent(20, 45, 90)!;
        expect(wind.kind).toBe("head");
        expect(wind.alongKmh).toBeCloseTo(-20 * Math.cos(Math.PI / 4), 4);
        expect(wind.crossKmh).toBeCloseTo(20 * Math.sin(Math.PI / 4), 4);
    });

    it("bez kursu jazdy nie da się nic powiedzieć", () => {
        // I właśnie dlatego jazda bez trasy nie pokazuje wiatru czołowego:
        // sam kierunek meteorologiczny nie jest informacją dla rowerzysty.
        expect(windComponent(18, 90, undefined)).toBeNull();
        expect(windComponent(18, undefined, 90)).toBeNull();
        expect(windComponent(undefined, 90, 90)).toBeNull();
    });
});

describe("prognoza wzdłuż trasy", () => {
    const snapshot: WeatherSnapshot = {
        sunset: "2026-05-01T19:34:00Z",
        points: [
            {
                label: "now",
                along_m: 20000,
                ahead_m: 0,
                bearing_deg: 90,
                hours: series(NOW, [
                    { temp_c: 18, wind_kmh: 14, wind_from_deg: 90, precip_probability: 10 },
                ]),
            },
            {
                label: "ahead",
                along_m: 40000,
                ahead_m: 20000,
                bearing_deg: 90,
                hours: series(NOW, [
                    { temp_c: 18, precip_probability: 10 },
                    { temp_c: 17, precip_probability: 60, wind_kmh: 18, wind_from_deg: 90 },
                ]),
            },
        ],
    };

    it("punkt przed zawodnikiem czyta godzinę po czasie dojazdu", () => {
        // 20 km przy 20 km/h to godzina drogi, więc liczy się druga próbka.
        const forecasts = forecastAlongRoute(snapshot, NOW, 20);
        expect(forecasts).toHaveLength(2);
        expect(forecasts[0].hour.temp_c).toBe(18);
        expect(forecasts[1].hour.temp_c).toBe(17);
        expect(forecasts[1].hour.precip_probability).toBe(60);
    });

    it("bez tempa zostaje tylko „teraz”", () => {
        // Stojący zawodnik nie ma ETA, więc „za 20 km" nie ma godziny —
        // a prognoza na godzinę wziętą z sufitu jest gorsza niż jej brak.
        const forecasts = forecastAlongRoute(snapshot, NOW, null);
        expect(forecasts).toHaveLength(1);
        expect(forecasts[0].label).toBe("now");
    });

    it("liczy wiatr względem kursu w każdym punkcie", () => {
        const forecasts = forecastAlongRoute(snapshot, NOW, 20);
        expect(forecasts[0].wind?.kind).toBe("head");
        expect(forecasts[0].wind?.alongKmh).toBeCloseTo(-14, 5);
    });

    it("brak danych to brak sekcji", () => {
        expect(forecastAlongRoute(null, NOW, 20)).toEqual([]);
        expect(forecastAlongRoute({ points: [] }, NOW, 20)).toEqual([]);
    });
});

describe("ostrzeżenie", () => {
    const point = (probability: number, aheadMeters: number) => ({
        label: "ahead",
        aheadMeters,
        at: new Date(NOW + HOUR),
        hour: { at: new Date(NOW + HOUR).toISOString(), precip_probability: probability },
        wind: null,
    });

    it("deszcz powyżej progu daje jedno zdanie", () => {
        const alert = weatherAlert([point(60, 20000)])!;
        expect(alert.title).toContain("DESZCZ");
        expect(alert.detail).toContain("60%");
        expect(alert.detail).toContain("20 km");
    });

    it("mała szansa na opady nie jest ostrzeżeniem", () => {
        expect(weatherAlert([point(30, 20000)])).toBeNull();
    });

    it("silny wiatr czołowy wystarcza, gdy nie pada", () => {
        const alert = weatherAlert([
            {
                label: "now",
                aheadMeters: 0,
                at: new Date(NOW),
                hour: { at: new Date(NOW).toISOString() },
                wind: {
                    speedKmh: 24,
                    alongKmh: -24,
                    crossKmh: 0,
                    kind: "head",
                    label: "CZOŁOWY",
                },
            },
        ])!;
        expect(alert.title).toBe("SILNY WIATR CZOŁOWY");
        expect(alert.detail).toContain("24 km/h");
    });

    it("deszcz wygrywa z wiatrem, bo przed deszczem można się schować", () => {
        const alert = weatherAlert([
            {
                ...point(70, 10000),
                wind: {
                    speedKmh: 30,
                    alongKmh: -30,
                    crossKmh: 0,
                    kind: "head",
                    label: "CZOŁOWY",
                },
            },
        ])!;
        expect(alert.title).toContain("DESZCZ");
    });

    it("spokojna prognoza nie generuje alertu", () => {
        expect(weatherAlert([])).toBeNull();
    });
});

describe("zachód słońca", () => {
    it("mówi, ile zostało i czy przyjazd wypada po zmroku", () => {
        const snapshot: WeatherSnapshot = { sunset: "2026-05-01T19:34:00Z", points: [] };
        const info = sunsetInfo(snapshot, NOW, new Date(Date.parse("2026-05-01T20:10:00Z")))!;
        expect(Math.round(info.secondsAway / 60)).toBe(454);
        expect(info.arrivesAfterSunset).toBe(true);
    });

    it("przyjazd przed zmrokiem nie jest ostrzeżeniem", () => {
        const snapshot: WeatherSnapshot = { sunset: "2026-05-01T19:34:00Z", points: [] };
        const info = sunsetInfo(snapshot, NOW, new Date(Date.parse("2026-05-01T18:00:00Z")))!;
        expect(info.arrivesAfterSunset).toBe(false);
    });

    it("bez godziny zachodu nie ma sekcji", () => {
        expect(sunsetInfo({ points: [] }, NOW, null)).toBeNull();
        expect(sunsetInfo(null, NOW, null)).toBeNull();
    });
});

describe("opis pogody", () => {
    it("nazywa kody WMO po polsku", () => {
        expect(weatherLabel(0)).toBe("Bezchmurnie");
        expect(weatherLabel(61)).toBe("Deszcz");
        expect(weatherLabel(95)).toBe("Burza");
    });

    it("nieznany kod nie dostaje wymyślonego opisu", () => {
        expect(weatherLabel(undefined)).toBe("");
        expect(weatherLabel(999)).toBe("");
    });
});
