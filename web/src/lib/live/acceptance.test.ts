import { describe, expect, it } from "vitest";
import {
    cumulativeDistances,
    hasPosition,
    liveOnly,
    paceKmh,
    projectOnRoute,
    rideTimes,
    riderStatus,
    routeProgress,
    type LngLat,
    type Rider,
    type Snapshot,
} from "./live_viewer";
import { climbSummary, currentClimb, upcomingClimbs } from "./route_insight";
import { forecastAlongRoute, type WeatherSnapshot } from "./weather";

/**
 * Dwa scenariusze, które muszą działać, żeby ta strona miała sens.
 *
 * Pierwszy: udostępniam link stojąc przed domem i NIE RUSZAM SIĘ. Znajomy ma
 * natychmiast zobaczyć mnie, moją pozycję, trasę i to, co mnie czeka.
 * Drugi: wolna jazda bez trasy. Znajomy ma zobaczyć mnie i nic zmyślonego —
 * żadnego ETA, żadnego postępu, żadnych podjazdów.
 *
 * Testy chodzą po tej samej ścieżce co strona: migawka z serwera przechodzi
 * przez dokładnie te funkcje, z których strona składa swój widok.
 */

/** Linia na wschód o zadanej długości — Berlin → Potsdam ze scenariusza. */
function route(kilometres = 78.4): {
    coordinates: LngLat[];
    cumulative: number[];
    length: number;
} {
    // Stopień długości na 52° szerokości to około 68,5 km; dzielimy trasę na
    // dwieście odcinków, żeby rzut na nią był gładki.
    const metresPerDegree = 111320 * Math.cos((52 * Math.PI) / 180);
    const step = (kilometres * 1000) / 200 / metresPerDegree;
    const coordinates: LngLat[] = [];
    for (let i = 0; i <= 200; i++) coordinates.push([21.0 + i * step, 52.0]);
    const cumulative = cumulativeDistances(coordinates);
    return { coordinates, cumulative, length: cumulative[cumulative.length - 1] };
}

const CLIMBS = [
    { start_m: 12000, length_m: 4200, gain_m: 240, avg_gradient: 5.4, name: "Katzenberg" },
    { start_m: 31000, length_m: 2100, gain_m: 126, avg_gradient: 6.0, name: "Teufelsberg" },
    { start_m: 52000, length_m: 3000, gain_m: 330, avg_gradient: 11.0 },
    { start_m: 68000, length_m: 1500, gain_m: 224, avg_gradient: 6.0 },
];

describe("scenariusz 1 — udostępniam link i stoję przed domem", () => {
    const now = Date.parse("2026-05-01T12:00:10Z");

    /** Dokładnie to, co odda serwer sekundę po naciśnięciu udostępnienia. */
    const snapshot: Snapshot = {
        status: "active",
        visibility: "unlisted",
        title: "Berlin → Potsdam",
        started_at: "2026-05-01T12:00:00Z",
        server_time: "2026-05-01T12:00:10Z",
        has_route: true,
        riders: [
            {
                id: "p1",
                display_name: "Marek",
                state: "stopped",
                has_fix: true,
                joined_at: "2026-05-01T12:00:00Z",
                last_seen_at: "2026-05-01T12:00:08Z",
                latitude: 52.0,
                longitude: 21.0,
                distance_m: 0,
                elevation_gain_m: 0,
                moving_seconds: 0,
                speed_kmh: 0,
            },
        ],
    };

    const rider = snapshot.riders[0];
    const { coordinates, cumulative, length } = route();

    it("znajomy widzi zawodnika i jego pozycję, choć ten nie ruszył", () => {
        expect(hasPosition(rider)).toBe(true);
        const status = riderStatus(rider.state, 2);
        expect(status.label).toBe("POSTÓJ");
        expect(status.tone).toBe("idle");
    });

    it("trasa, podjazdy i przewyższenie są znane od razu", () => {
        const totals = climbSummary(CLIMBS)!;
        expect(totals.count).toBe(4);
        expect(totals.totalGainMeters).toBe(920);
        expect(length / 1000).toBeCloseTo(78.4, 0);

        // Wszystkie cztery podjazdy są jeszcze przed nim.
        expect(upcomingClimbs(CLIMBS, 0, 10)).toHaveLength(4);
        expect(currentClimb(CLIMBS, 0)).toBeNull();
    });

    it("postęp to zero procent, a nie brak trasy", () => {
        const projection = projectOnRoute(cumulative.length ? coordinates : [], cumulative, 21.0, 52.0);
        const progress = routeProgress(rider, projection, length, now)!;
        expect(progress.alongMeters).toBeCloseTo(0, 0);
        expect(progress.fraction).toBeCloseTo(0, 5);
        expect(Math.round(progress.remainingMeters)).toBe(Math.round(length));
    });

    it("ETA jeszcze nie istnieje i nie jest zmyślane", () => {
        // Zero przejechanych metrów i zero prędkości to brak tempa, a ETA bez
        // tempa byłoby liczbą wziętą z powietrza.
        expect(paceKmh(rider)).toBeNull();
        const projection = projectOnRoute(coordinates, cumulative, 21.0, 52.0);
        expect(routeProgress(rider, projection, length, now)!.etaSeconds).toBeNull();
    });

    it("czasy zaczynają się od zera, nie od kresek", () => {
        const times = rideTimes(rider, snapshot.started_at, undefined, now);
        expect(times.elapsedSeconds).toBe(10);
        expect(times.movingSeconds).toBe(0);
        // Postojów jeszcze nie ma i pole ma nie istnieć, zamiast pokazywać zero.
        expect(times.pausedSeconds).toBeUndefined();
    });

    it("pogoda „teraz” działa bez tempa, „za 20 km” jeszcze nie", () => {
        const weather: WeatherSnapshot = {
            points: [
                {
                    label: "now",
                    along_m: 0,
                    ahead_m: 0,
                    bearing_deg: 90,
                    hours: [{ at: "2026-05-01T12:00:00Z", temp_c: 18, wind_kmh: 14, wind_from_deg: 90 }],
                },
                {
                    label: "ahead",
                    along_m: 20000,
                    ahead_m: 20000,
                    bearing_deg: 90,
                    hours: [{ at: "2026-05-01T13:00:00Z", temp_c: 17 }],
                },
            ],
        };
        const forecasts = forecastAlongRoute(weather, now, paceKmh(rider));
        expect(forecasts).toHaveLength(1);
        expect(forecasts[0].label).toBe("now");
        expect(forecasts[0].wind?.kind).toBe("head");
    });

    it("po ruszeniu wszystko rośnie bez żadnego przełącznika", () => {
        const moved: Rider = {
            ...rider,
            state: "riding",
            latitude: 52.0,
            longitude: 21.0 + 100 * 0.00583,
            distance_m: 39200,
            moving_seconds: 5040,
            speed_kmh: 31.4,
        };
        const projection = projectOnRoute(coordinates, cumulative, moved.longitude!, moved.latitude!);
        const progress = routeProgress(moved, projection, length, now)!;

        expect(progress.fraction).toBeGreaterThan(0.45);
        expect(progress.fraction).toBeLessThan(0.55);
        expect(progress.etaSeconds).not.toBeNull();
        expect(currentClimb(CLIMBS, progress.alongMeters)).toBeNull();
        expect(upcomingClimbs(CLIMBS, progress.alongMeters).map((c) => c.name)).toEqual([
            undefined,
            undefined,
        ]);
        expect(riderStatus(moved.state, 2).label).toBe("JEDZIE");
    });
});

describe("scenariusz 2 — wolna jazda bez trasy", () => {
    const now = Date.parse("2026-05-01T12:00:20Z");
    const rider: Rider = {
        id: "p1",
        display_name: "Marek",
        state: "stopped",
        has_fix: true,
        last_seen_at: "2026-05-01T12:00:18Z",
        latitude: 52.23,
        longitude: 21.01,
        distance_m: 0,
        moving_seconds: 0,
        speed_kmh: 0,
        heart_rate_bpm: 62,
    };

    it("zawodnik i jego pozycja są widoczne", () => {
        expect(hasPosition(rider)).toBe(true);
        expect(riderStatus(rider.state, 2).label).toBe("POSTÓJ");
    });

    it("nie ma postępu, ETA ani podjazdów, bo nie ma trasy", () => {
        // Bez geometrii rzut nie istnieje, a bez rzutu nie ma postępu. To nie
        // jest brak danych do dopowiedzenia — to brak celu, do którego można
        // by liczyć.
        expect(projectOnRoute([], [], rider.longitude!, rider.latitude!)).toBeNull();
        expect(routeProgress(rider, null, 0, now)).toBeNull();
        expect(currentClimb(undefined, null)).toBeNull();
        expect(upcomingClimbs(undefined, null)).toEqual([]);
        expect(climbSummary(undefined)).toBeNull();
    });

    it("pogoda ogranicza się do miejsca, w którym zawodnik jest", () => {
        const weather: WeatherSnapshot = {
            points: [
                {
                    label: "now",
                    along_m: 0,
                    ahead_m: 0,
                    hours: [{ at: "2026-05-01T12:00:00Z", temp_c: 18, wind_kmh: 14, wind_from_deg: 90 }],
                },
            ],
        };
        const forecasts = forecastAlongRoute(weather, now, null);
        expect(forecasts).toHaveLength(1);
        // Bez trasy nie znamy kursu, więc wiatr nie udaje czołowego.
        expect(forecasts[0].wind).toBeNull();
    });

    it("znane czujniki widać, nieznanych nie ma", () => {
        expect(rider.heart_rate_bpm).toBe(62);
        expect(rider.power_watts).toBeUndefined();
        expect(rider.cadence_rpm).toBeUndefined();
    });

    it("czas LIVE liczy się od startu sesji", () => {
        const times = rideTimes(rider, "2026-05-01T12:00:00Z", undefined, now);
        expect(times.elapsedSeconds).toBe(20);
    });
});

describe("zawodnik bez ani jednego fiksa", () => {
    const rider: Rider = {
        id: "p1",
        display_name: "Marek",
        state: "waiting",
        has_fix: false,
        joined_at: "2026-05-01T12:00:00Z",
        last_seen_at: "",
    };

    it("czeka na GPS, a nie zniknął", () => {
        const status = riderStatus(rider.state, Number.POSITIVE_INFINITY);
        expect(status.label).toBe("OCZEKIWANIE NA GPS");
        expect(status.tone).toBe("waiting");
    });

    it("nie ma pozycji, więc mapa go nie rysuje", () => {
        expect(hasPosition(rider)).toBe(false);
    });

    it("wartości chwilowe zostają ukryte, dopóki nic nie przyszło", () => {
        // Stan „czekam" jest jak brak sygnału dla liczb mierzonych teraz:
        // nie mamy żadnej próbki, więc nie ma czego pokazać.
        expect(liveOnly(31.4, "waiting")).toBeUndefined();
        expect(liveOnly(31.4, "live")).toBe(31.4);
    });

    it("reszta strony — trasa, podjazdy — jest znana mimo braku pozycji", () => {
        const totals = climbSummary(CLIMBS)!;
        expect(totals.count).toBe(4);
        // Wszystkie podjazdy bez umiejscowienia: nie wiemy, gdzie on jest,
        // ale wiemy, co jest na trasie.
        expect(upcomingClimbs(CLIMBS, null)).toEqual([]);
        expect(currentClimb(CLIMBS, null)).toBeNull();
    });
});
