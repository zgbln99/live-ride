import { describe, expect, it } from "vitest";
import {
    OFFLINE_AFTER_SECONDS,
    ago,
    clock,
    compass,
    cumulativeDistances,
    distance,
    duration,
    durationCoarse,
    elevationAt,
    hasPosition,
    initials,
    liveOnly,
    nextClimb,
    num,
    paceKmh,
    projectOnRoute,
    relativeGap,
    riderStatus,
    routeProgress,
    type Climb,
    type LngLat,
    type Rider,
} from "./live_viewer";

const rider = (overrides: Partial<Rider> = {}): Rider => ({
    id: "p1",
    display_name: "Marek Piątak",
    last_seen_at: new Date().toISOString(),
    ...overrides,
});

describe("riderStatus", () => {
    it("nazywa stany po polsku", () => {
        expect(riderStatus("riding", 3).label).toBe("JEDZIE");
        expect(riderStatus("stopped", 3).label).toBe("POSTÓJ");
        expect(riderStatus("paused", 3).label).toBe("PAUZA");
        expect(riderStatus("ended", 3).label).toBe("ZAKOŃCZONY");
    });

    it("po ciszy przechodzi w brak danych, cokolwiek mówi ostatnia próbka", () => {
        const status = riderStatus("riding", OFFLINE_AFTER_SECONDS + 1);
        expect(status.tone).toBe("offline");
        expect(status.label).toBe("BRAK AKTUALNYCH DANYCH");
    });

    it("tuż przed progiem nadal uznaje dane za świeże", () => {
        expect(riderStatus("riding", OFFLINE_AFTER_SECONDS - 1).tone).toBe("live");
    });

    it("bez znanego wieku próbki jest offline, a nie 'jedzie'", () => {
        expect(riderStatus("riding", Number.POSITIVE_INFINITY).tone).toBe("offline");
        expect(riderStatus(undefined, Number.NaN).tone).toBe("offline");
    });

    it("zakończony przejazd wygrywa z wiekiem próbki", () => {
        expect(riderStatus("ended", 10_000).tone).toBe("ended");
    });

    it("ma krótką etykietę na wąskie ekrany", () => {
        expect(riderStatus("offline", 900).short).toBe("BRAK SYGNAŁU");
        expect(riderStatus("offline", 900).short.length).toBeLessThan(
            riderStatus("offline", 900).label.length,
        );
    });
});

describe("liveOnly", () => {
    it("chowa wartości chwilowe, gdy zawodnik milczy", () => {
        expect(liveOnly(31.4, "offline")).toBeUndefined();
    });

    it("zostawia je, gdy dane są świeże", () => {
        expect(liveOnly(31.4, "live")).toBe(31.4);
        expect(liveOnly(0, "idle")).toBe(0);
    });
});

describe("ago", () => {
    it.each([
        [0, "przed chwilą"],
        [9, "przed chwilą"],
        [42, "42 s temu"],
        [180, "3 min temu"],
        [7200, "2 godz. temu"],
        [172800, "2 dni temu"],
    ])("%i s → %s", (seconds, expected) => {
        expect(ago(seconds)).toBe(expected);
    });

    it("bez danych nie zgaduje", () => {
        expect(ago(Number.POSITIVE_INFINITY)).toBe("brak danych");
    });
});

describe("formatowanie", () => {
    it("dystans: metry pod kilometrem, potem kilometry", () => {
        expect(distance(430)).toBe("430 m");
        expect(distance(1500)).toBe("1,50 km");
        expect(distance(21400)).toBe("21,4 km");
        expect(distance(120000)).toBe("120 km");
    });

    it("brak danych to kreska, nie zero", () => {
        expect(distance(undefined)).toBe("—");
        expect(duration(undefined)).toBe("—");
        expect(num(undefined)).toBe("—");
        expect(clock(undefined)).toBe("—");
        expect(clock("nonsens")).toBe("—");
    });

    it("czas trwania", () => {
        expect(duration(59)).toBe("0:59");
        expect(duration(605)).toBe("10:05");
        expect(duration(5025)).toBe("1:23:45");
    });

    it("oszacowania są zaokrąglone do minut", () => {
        expect(durationCoarse(11837)).toBe("3 godz. 17 min");
        expect(durationCoarse(300)).toBe("5 min");
        expect(durationCoarse(7200)).toBe("2 godz.");
    });

    it("inicjały i kierunek", () => {
        expect(initials("Marek Piątak")).toBe("MP");
        expect(initials("kuba")).toBe("KU");
        expect(initials("")).toBe("?");
        expect(compass(0)).toBe("N");
        expect(compass(95)).toBe("E");
        expect(compass(undefined)).toBe("");
    });
});

describe("hasPosition", () => {
    it("odrzuca zero na zero jako brak pozycji", () => {
        expect(hasPosition(rider({ latitude: 0, longitude: 0 }))).toBe(false);
        expect(hasPosition(rider())).toBe(false);
        expect(hasPosition(rider({ latitude: 50.78, longitude: 16.92 }))).toBe(true);
    });
});

describe("rzut na trasę", () => {
    // Prosty odcinek wzdłuż południka, ~1,1 km na 0,01 stopnia.
    const line: LngLat[] = [
        [16.92, 50.78],
        [16.92, 50.79],
        [16.92, 50.8],
    ];
    const cumulative = cumulativeDistances(line);

    it("liczy narastający dystans", () => {
        expect(cumulative[0]).toBe(0);
        expect(cumulative[2]).toBeGreaterThan(2000);
        expect(cumulative[2]).toBeLessThan(2300);
    });

    it("rzutuje na odcinek, nie na wierzchołek", () => {
        // Punkt dokładnie w połowie pierwszego odcinka.
        const projection = projectOnRoute(line, cumulative, 16.92, 50.785);
        expect(projection).not.toBeNull();
        expect(projection!.alongMeters).toBeGreaterThan(500);
        expect(projection!.alongMeters).toBeLessThan(580);
        expect(projection!.offRouteMeters).toBeLessThan(5);
    });

    it("podaje odległość od trasy dla zjechanego zawodnika", () => {
        const projection = projectOnRoute(line, cumulative, 16.94, 50.785);
        expect(projection!.offRouteMeters).toBeGreaterThan(1000);
    });

    it("bez geometrii nie zgaduje", () => {
        expect(projectOnRoute([], [], 16.92, 50.78)).toBeNull();
        expect(projectOnRoute(line, cumulative, Number.NaN, 50.78)).toBeNull();
    });
});

describe("tempo i ETA", () => {
    it("bierze średnią z jazdy, a nie prędkość chwilową", () => {
        // 20 km w 3600 s w ruchu = 20 km/h, mimo chwilowych 45 km/h.
        const pace = paceKmh(rider({ distance_m: 20000, moving_seconds: 3600, speed_kmh: 45 }));
        expect(pace).toBeCloseTo(20, 1);
    });

    it("na początku jazdy spada na prędkość chwilową", () => {
        expect(paceKmh(rider({ distance_m: 200, moving_seconds: 40, speed_kmh: 24 }))).toBe(24);
    });

    it("nie zgaduje tempa stojącego zawodnika", () => {
        expect(paceKmh(rider({ speed_kmh: 0.4 }))).toBeNull();
        expect(paceKmh(rider())).toBeNull();
    });

    it("liczy postęp i czas do mety", () => {
        const progress = routeProgress(
            rider({ distance_m: 20000, moving_seconds: 3600 }),
            { alongMeters: 20000, offRouteMeters: 12 },
            40000,
            Date.UTC(2026, 4, 1, 10, 0, 0),
        );
        expect(progress).not.toBeNull();
        expect(progress!.fraction).toBeCloseTo(0.5, 3);
        expect(progress!.remainingMeters).toBe(20000);
        // 20 km przy 20 km/h to godzina.
        expect(progress!.etaSeconds).toBeCloseTo(3600, 0);
        expect(progress!.etaAt!.getUTCHours()).toBe(11);
    });

    it("nie liczy postępu zawodnikowi daleko od trasy", () => {
        const progress = routeProgress(
            rider({ distance_m: 20000, moving_seconds: 3600 }),
            { alongMeters: 20000, offRouteMeters: 900 },
            40000,
            Date.now(),
        );
        expect(progress).toBeNull();
    });

    it("bez tempa zwraca postęp, ale nie ETA", () => {
        const progress = routeProgress(
            rider({ speed_kmh: 0 }),
            { alongMeters: 10000, offRouteMeters: 5 },
            40000,
            Date.now(),
        );
        expect(progress!.fraction).toBeCloseTo(0.25, 3);
        expect(progress!.etaSeconds).toBeNull();
        expect(progress!.etaAt).toBeNull();
    });

    it("bez trasy nie ma postępu", () => {
        expect(routeProgress(rider(), null, 40000, Date.now())).toBeNull();
        expect(
            routeProgress(rider(), { alongMeters: 0, offRouteMeters: 0 }, 0, Date.now()),
        ).toBeNull();
    });
});

describe("następny podjazd", () => {
    const climbs: Climb[] = [
        { start_m: 6200, length_m: 4200, gain_m: 240, avg_gradient: 5.4 },
        { start_m: 21400, length_m: 6100, gain_m: 430, avg_gradient: 7.1 },
        { start_m: 33800, length_m: 2600, gain_m: 118, avg_gradient: 4.5 },
    ];

    it("wskazuje pierwszy podjazd przed zawodnikiem", () => {
        const climb = nextClimb(climbs, 1000);
        expect(climb!.start_m).toBe(6200);
        expect(climb!.distanceAheadMeters).toBe(5200);
    });

    it("w trakcie podjazdu pokazuje ten, na którym zawodnik jest", () => {
        const climb = nextClimb(climbs, 7000);
        expect(climb!.start_m).toBe(6200);
        expect(climb!.distanceAheadMeters).toBe(0);
    });

    it("po ostatnim podjeździe nie wymyśla kolejnego", () => {
        expect(nextClimb(climbs, 39000)).toBeNull();
        expect(nextClimb([], 1000)).toBeNull();
        expect(nextClimb(undefined, 1000)).toBeNull();
    });

    it("nie ufa kolejności z serwera", () => {
        const shuffled = [climbs[2], climbs[0], climbs[1]];
        expect(nextClimb(shuffled, 0)!.start_m).toBe(6200);
    });
});

describe("dystans względny w grupie", () => {
    it("liczy po trasie, nie w linii prostej", () => {
        expect(relativeGap(20000, 20320)).toBe("320 m za prowadzącym");
        expect(relativeGap(21000, 20000)).toBe("1,00 km przed prowadzącym");
    });

    it("kilka metrów różnicy to nie 'za prowadzącym'", () => {
        expect(relativeGap(20000, 20010)).toBe("razem z prowadzącym");
    });

    it("bez rzutu na trasę woli milczeć", () => {
        expect(relativeGap(null, 20000)).toBeNull();
        expect(relativeGap(20000, null)).toBeNull();
    });
});

describe("profil wysokości", () => {
    const profile = [
        { d: 0, e: 300 },
        { d: 1000, e: 400 },
        { d: 2000, e: 350 },
    ];

    it("interpoluje między próbkami", () => {
        expect(elevationAt(profile, 500)).toBeCloseTo(350, 5);
        expect(elevationAt(profile, 1500)).toBeCloseTo(375, 5);
    });

    it("trzyma się końców profilu", () => {
        expect(elevationAt(profile, -100)).toBe(300);
        expect(elevationAt(profile, 99999)).toBe(350);
    });

    it("bez profilu nie zgaduje wysokości", () => {
        expect(elevationAt(undefined, 500)).toBeNull();
        expect(elevationAt([], 500)).toBeNull();
    });
});
