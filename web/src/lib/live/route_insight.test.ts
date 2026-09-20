import { describe, expect, it } from "vitest";
import {
    climbSummary,
    currentClimb,
    elevationAtDistance,
    elevationInsight,
    normalizeGradient,
    surfaceShares,
    upcomingClimbs,
} from "./route_insight";
import type { Climb } from "./live_viewer";

/**
 * Sekcja podjazdów jest jedyną częścią strony, która odpowiada na pytanie
 * „jak ciężko mu jeszcze będzie". Pomyłka o jeden podjazd albo o kierunek
 * liczenia jest tu niewidoczna gołym okiem i kompletnie zmienia odpowiedź.
 */

const CLIMBS: Climb[] = [
    { start_m: 5000, length_m: 4200, gain_m: 240, avg_gradient: 5.4, max_gradient: 9.1 },
    { start_m: 21000, length_m: 2100, gain_m: 126, avg_gradient: 6.0 },
    { start_m: 44000, length_m: 3000, gain_m: 330, avg_gradient: 11.0 },
    { start_m: 60000, length_m: 1500, gain_m: 90, avg_gradient: 6.0 },
];

describe("aktualny podjazd", () => {
    it("rozpoznaje zawodnika w połowie wspinaczki", () => {
        const climb = currentClimb(CLIMBS, 7800);
        expect(climb).not.toBeNull();
        expect(climb!.start_m).toBe(5000);
        expect(climb!.doneMeters).toBe(2800);
        expect(climb!.remainingMeters).toBe(1400);
        expect(climb!.fraction).toBeCloseTo(2800 / 4200, 5);
    });

    it("tolerancja na wejściu łapie kogoś tuż przed podnóżem", () => {
        // Rzut pozycji na trasę bywa o kilkanaście metrów za wcześnie i bez
        // tolerancji karta podjazdu mrugałaby na samym początku wspinaczki.
        expect(currentClimb(CLIMBS, 4985)).not.toBeNull();
        expect(currentClimb(CLIMBS, 4500)).toBeNull();
    });

    it("po szczycie nie ma już aktualnego podjazdu", () => {
        expect(currentClimb(CLIMBS, 9200)).toBeNull();
        expect(currentClimb(CLIMBS, 9199)).not.toBeNull();
    });

    it("bez pozycji na trasie nie ma czego liczyć", () => {
        expect(currentClimb(CLIMBS, null)).toBeNull();
        expect(currentClimb(undefined, 7800)).toBeNull();
    });
});

describe("kolejne podjazdy", () => {
    it("pokazuje najbliższe trzy, od najbliższego", () => {
        const next = upcomingClimbs(CLIMBS, 1000);
        expect(next.map((climb) => climb.start_m)).toEqual([5000, 21000, 44000]);
        expect(next[0].distanceAheadMeters).toBe(4000);
        expect(next[1].distanceAheadMeters).toBe(20000);
    });

    it("nie powtarza podjazdu, na którym zawodnik właśnie jest", () => {
        const next = upcomingClimbs(CLIMBS, 7800);
        expect(next.map((climb) => climb.start_m)).toEqual([21000, 44000, 60000]);
    });

    it("za ostatnim podjazdem lista jest pusta", () => {
        expect(upcomingClimbs(CLIMBS, 70000)).toEqual([]);
    });

    it("limit da się podnieść dla rozwiniętej listy", () => {
        expect(upcomingClimbs(CLIMBS, 0, 10)).toHaveLength(4);
    });
});

describe("podsumowanie podjazdów", () => {
    it("liczy sumę podejść i znajduje najdłuższy", () => {
        const summary = climbSummary(CLIMBS)!;
        expect(summary.count).toBe(4);
        expect(summary.totalGainMeters).toBe(786);
        expect(summary.longest!.length_m).toBe(4200);
    });

    it("najstromszy bierze nachylenie maksymalne, gdy jest znane", () => {
        const summary = climbSummary(CLIMBS)!;
        // 11% średnio na trzecim podjeździe przebija 9,1% maksymalnie
        // na pierwszym — i ma przebijać, bo to prawdziwa liczba.
        expect(summary.steepestPercent).toBeCloseTo(11, 5);
    });

    it("trasa bez podjazdów nie dostaje sekcji", () => {
        expect(climbSummary([])).toBeNull();
        expect(climbSummary(undefined)).toBeNull();
    });
});

describe("nachylenie", () => {
    it("ułamek zamienia na procenty, procentów nie rusza", () => {
        expect(normalizeGradient(0.054)).toBeCloseTo(5.4, 5);
        expect(normalizeGradient(5.4)).toBeCloseTo(5.4, 5);
        expect(normalizeGradient(undefined)).toBe(0);
    });
});

describe("profil wysokości", () => {
    const profile = [
        { d: 0, e: 100 },
        { d: 1000, e: 150 },
        { d: 2000, e: 120 },
        { d: 3000, e: 300 },
        { d: 4000, e: 280 },
    ];

    it("interpoluje wysokość między punktami", () => {
        expect(elevationAtDistance(profile, 500)).toBeCloseTo(125, 5);
        expect(elevationAtDistance(profile, 0)).toBe(100);
        expect(elevationAtDistance(profile, 99999)).toBe(280);
    });

    it("pozostałe przewyższenie liczy tylko podejścia", () => {
        // Z 1000 m (150 m n.p.m.): zjazd do 120, wjazd do 300, zjazd do 280.
        // Do wjechania zostaje 180 m, a nie różnica 130 m między tu a metą.
        const insight = elevationInsight(profile, 1000)!;
        expect(insight.currentMeters).toBe(150);
        expect(insight.remainingGainMeters).toBe(180);
        expect(insight.highestAheadMeters).toBe(300);
    });

    it("za najwyższym punktem nie ma już czego wjeżdżać", () => {
        const insight = elevationInsight(profile, 3000)!;
        expect(insight.remainingGainMeters).toBe(0);
        expect(insight.highestAheadMeters).toBe(300);
    });

    it("bez pozycji podaje tylko zakres trasy", () => {
        const insight = elevationInsight(profile, null)!;
        expect(insight.minMeters).toBe(100);
        expect(insight.maxMeters).toBe(300);
        expect(insight.currentMeters).toBeNull();
        expect(insight.remainingGainMeters).toBeNull();
    });

    it("bez profilu nie ma sekcji", () => {
        expect(elevationInsight(undefined, 100)).toBeNull();
        expect(elevationInsight([], 100)).toBeNull();
    });
});

describe("nawierzchnia", () => {
    it("sumuje odcinki i liczy udziały", () => {
        const shares = surfaceShares([
            { surface: "asphalt", distance_m: 8200 },
            { surface: "gravel", distance_m: 1800 },
            { surface: "asphalt", distance_m: 1000 },
        ]);
        expect(shares[0].label).toBe("Asfalt");
        expect(shares[0].meters).toBe(9200);
        expect(shares[0].fraction).toBeCloseTo(9200 / 11000, 5);
        expect(shares[1].label).toBe("Szuter");
    });

    it("nieznana nazwa zostaje taka, jaka przyszła z routingu", () => {
        const shares = surfaceShares([{ surface: "wood_planks", distance_m: 100 }]);
        expect(shares[0].label).toBe("wood planks");
    });

    it("brak danych to brak sekcji, a nie sto procent asfaltu", () => {
        expect(surfaceShares(undefined)).toEqual([]);
        expect(surfaceShares([])).toEqual([]);
        expect(surfaceShares([{ surface: "asphalt" }])).toEqual([]);
    });
});
