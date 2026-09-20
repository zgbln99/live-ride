/**
 * Co wynika z trasy: podjazdy, profil wysokości, nawierzchnia.
 *
 * Wszystko tutaj jest czystą funkcją nad danymi, które przysłał serwer.
 * Niczego nie zgadujemy z geometrii: gdy routing nie podał nachylenia
 * maksymalnego albo nawierzchni, odpowiedź brzmi „nie wiem", a nie
 * „prawdopodobnie asfalt". Obserwujący, który zobaczy wymyśloną liczbę, nie
 * ma jak odróżnić jej od zmierzonej.
 */

import type { Climb, RiderClimb, Surface } from "./live_viewer";

/** Podjazd umiejscowiony względem zawodnika. */
export type PlacedClimb = Climb & {
    endMeters: number;
    /** Ile zostało do jego początku. Zero, gdy zawodnik już na nim jest. */
    distanceAheadMeters: number;
    /** Ile podjazdu zawodnik ma za sobą, w metrach. */
    doneMeters: number;
    /** Ile zostało do szczytu. */
    remainingMeters: number;
    /** Udział ukończonej części, 0–1. */
    fraction: number;
};

/** Ile metrów przed podjazdem uznajemy, że zawodnik już na nim jest. */
const CLIMB_ENTRY_TOLERANCE_METERS = 30;

function ordered(climbs: Climb[] | undefined): Climb[] {
    if (!climbs?.length) return [];
    return [...climbs]
        .filter((climb) => Number.isFinite(climb.start_m) && climb.length_m > 0)
        .sort((a, b) => a.start_m - b.start_m);
}

function place(climb: Climb, alongMeters: number): PlacedClimb {
    const endMeters = climb.start_m + climb.length_m;
    const doneMeters = Math.min(climb.length_m, Math.max(0, alongMeters - climb.start_m));
    return {
        ...climb,
        endMeters,
        distanceAheadMeters: Math.max(0, climb.start_m - alongMeters),
        doneMeters,
        remainingMeters: Math.max(0, endMeters - Math.max(alongMeters, climb.start_m)),
        fraction: climb.length_m > 0 ? doneMeters / climb.length_m : 0,
    };
}

/**
 * Podjazd, na którym zawodnik właśnie jest.
 *
 * Tolerancja na wejściu bierze się z rzutu pozycji na trasę: przy dokładności
 * GPS rzędu kilku metrów zawodnik potrafi „stać" trzydzieści metrów przed
 * podnóżem, choć już się wspina.
 */
export function currentClimb(
    climbs: Climb[] | undefined,
    alongMeters: number | null | undefined,
): PlacedClimb | null {
    if (alongMeters === null || alongMeters === undefined) return null;
    for (const climb of ordered(climbs)) {
        const start = climb.start_m - CLIMB_ENTRY_TOLERANCE_METERS;
        const end = climb.start_m + climb.length_m;
        if (alongMeters >= start && alongMeters < end) return place(climb, alongMeters);
    }
    return null;
}

/**
 * Podjazdy jeszcze przed zawodnikiem, od najbliższego.
 *
 * Ten, na którym właśnie jest, tu nie wchodzi — ma własną, większą kartę.
 */
export function upcomingClimbs(
    climbs: Climb[] | undefined,
    alongMeters: number | null | undefined,
    limit = 3,
): PlacedClimb[] {
    if (alongMeters === null || alongMeters === undefined) return [];
    const current = currentClimb(climbs, alongMeters);
    return ordered(climbs)
        .filter((climb) => climb.start_m > alongMeters)
        .filter((climb) => !current || climb.start_m !== current.start_m)
        .slice(0, Math.max(0, limit))
        .map((climb) => place(climb, alongMeters));
}

/** Podsumowanie wszystkich podjazdów trasy. */
export type ClimbSummary = {
    count: number;
    totalGainMeters: number;
    longest: Climb | null;
    /** Największe znane nachylenie średnie albo maksymalne — w procentach. */
    steepestPercent: number | null;
};

export function climbSummary(climbs: Climb[] | undefined): ClimbSummary | null {
    const list = ordered(climbs);
    if (!list.length) return null;

    let totalGainMeters = 0;
    let longest: Climb | null = null;
    let steepestPercent: number | null = null;

    for (const climb of list) {
        if (Number.isFinite(climb.gain_m)) totalGainMeters += climb.gain_m;
        if (!longest || climb.length_m > longest.length_m) longest = climb;
        // Nachylenie maksymalne bierzemy tylko wtedy, gdy routing je podał.
        // Bez niego zostaje średnie — mniejsze, ale prawdziwe.
        const candidate = climb.max_gradient ?? climb.avg_gradient;
        if (Number.isFinite(candidate)) {
            const percent = normalizeGradient(candidate);
            if (steepestPercent === null || percent > steepestPercent) steepestPercent = percent;
        }
    }

    return { count: list.length, totalGainMeters, longest, steepestPercent };
}

/**
 * Nachylenie w procentach.
 *
 * Źródła podają je raz jako ułamek (0,054), raz jako procent (5,4). Wartość
 * poniżej jedności przy podjeździe znaczy ułamek — nikt nie nazywa podjazdem
 * drogi o nachyleniu pół procenta.
 */
export function normalizeGradient(value: number | undefined): number {
    if (value === undefined || !Number.isFinite(value)) return 0;
    const magnitude = Math.abs(value);
    return magnitude <= 1 ? value * 100 : value;
}

/** Punkty profilu wysokości. */
export type ElevationPoint = { d: number; e: number };

export type ElevationInsight = {
    minMeters: number;
    maxMeters: number;
    /** Wysokość w miejscu, w którym zawodnik jest. */
    currentMeters: number | null;
    /** Najwyższy punkt POZOSTAŁEJ części trasy. */
    highestAheadMeters: number | null;
    /** Suma podejść, które jeszcze przed zawodnikiem. */
    remainingGainMeters: number | null;
};

/**
 * Co profil wysokości mówi o tym, co zostało.
 *
 * „Pozostałe przewyższenie" liczymy tylko z podejść — zjazdy się nie odejmują,
 * bo rowerzysta pyta, ile jeszcze ma wjechać pod górę, a nie ile wyniesie
 * różnica wysokości między tym miejscem a metą.
 */
export function elevationInsight(
    profile: ElevationPoint[] | undefined,
    alongMeters: number | null | undefined,
): ElevationInsight | null {
    if (!profile?.length) return null;

    let minMeters = Infinity;
    let maxMeters = -Infinity;
    for (const point of profile) {
        if (point.e < minMeters) minMeters = point.e;
        if (point.e > maxMeters) maxMeters = point.e;
    }

    if (alongMeters === null || alongMeters === undefined) {
        return {
            minMeters,
            maxMeters,
            currentMeters: null,
            highestAheadMeters: null,
            remainingGainMeters: null,
        };
    }

    const currentMeters = elevationAtDistance(profile, alongMeters);
    let highestAheadMeters = currentMeters;
    let remainingGainMeters = 0;
    let previous = currentMeters;

    for (const point of profile) {
        if (point.d <= alongMeters) continue;
        if (previous !== null && point.e > previous) remainingGainMeters += point.e - previous;
        previous = point.e;
        if (highestAheadMeters === null || point.e > highestAheadMeters) {
            highestAheadMeters = point.e;
        }
    }

    return {
        minMeters,
        maxMeters,
        currentMeters,
        highestAheadMeters,
        remainingGainMeters: Math.round(remainingGainMeters),
    };
}

/** Wysokość w zadanej odległości wzdłuż trasy, interpolowana liniowo. */
export function elevationAtDistance(
    profile: ElevationPoint[] | undefined,
    alongMeters: number,
): number | null {
    if (!profile?.length) return null;
    if (alongMeters <= profile[0].d) return profile[0].e;
    for (let i = 1; i < profile.length; i++) {
        if (profile[i].d < alongMeters) continue;
        const previous = profile[i - 1];
        const span = profile[i].d - previous.d;
        if (span <= 0) return profile[i].e;
        const t = (alongMeters - previous.d) / span;
        return previous.e + (profile[i].e - previous.e) * t;
    }
    return profile[profile.length - 1].e;
}

/** Jedna nawierzchnia z udziałem w trasie. */
export type SurfaceShare = { label: string; meters: number; fraction: number };

const SURFACE_LABELS: Record<string, string> = {
    paved: "Asfalt",
    asphalt: "Asfalt",
    concrete: "Beton",
    paving_stones: "Kostka",
    cobblestone: "Bruk",
    sett: "Bruk",
    compacted: "Utwardzona",
    gravel: "Szuter",
    fine_gravel: "Drobny szuter",
    unpaved: "Nieutwardzona",
    ground: "Grunt",
    dirt: "Grunt",
    earth: "Grunt",
    sand: "Piasek",
    grass: "Trawa",
};

/**
 * Udział nawierzchni w trasie, od największego.
 *
 * Nazwy nieznane zostają takie, jakie przyszły: lepiej pokazać surową nazwę
 * z routingu niż wcisnąć ją do „inne" i stracić informację.
 */
export function surfaceShares(surfaces: Surface[] | undefined): SurfaceShare[] {
    if (!surfaces?.length) return [];
    const totals = new Map<string, number>();
    let total = 0;

    for (const entry of surfaces) {
        const meters = entry.distance_m ?? entry.meters;
        if (meters === undefined || !Number.isFinite(meters) || meters <= 0) continue;
        const key = (entry.surface ?? entry.name ?? "").trim().toLowerCase();
        if (!key) continue;
        totals.set(key, (totals.get(key) ?? 0) + meters);
        total += meters;
    }
    if (total <= 0) return [];

    return [...totals.entries()]
        .map(([key, meters]) => ({
            label: SURFACE_LABELS[key] ?? key.replace(/_/g, " "),
            meters,
            fraction: meters / total,
        }))
        .sort((a, b) => b.meters - a.meters);
}

/**
 * Podjazd zgłoszony przez licznik zawodnika, ubrany w [PlacedClimb].
 *
 * Telefon liczy ClimbPro na profilu trasy, którego publiczna strona może nie
 * mieć wcale — trasa bywa lokalna, świeżo z kreatora albo z GPX-a. Gdy
 * telemetria niesie podjazd, wygrywa on z rachunkiem z trasy: to ta sama
 * liczba, którą zawodnik widzi na kierownicy, a nie jej druga, rozjeżdżająca
 * się wersja.
 */
export function reportedClimb(climb: RiderClimb | undefined): PlacedClimb | null {
    if (!climb || !(climb.length_m > 0)) return null;
    const done = Math.min(climb.length_m, Math.max(0, climb.done_m));
    return {
        start_m: 0,
        length_m: climb.length_m,
        gain_m: climb.gain_m,
        avg_gradient: climb.avg_gradient,
        max_gradient: climb.max_gradient,
        category: climb.category || undefined,
        name:
            climb.index && climb.total
                ? `Podjazd ${climb.index} z ${climb.total}`
                : climb.index
                  ? `Podjazd ${climb.index}`
                  : undefined,
        endMeters: climb.length_m,
        distanceAheadMeters: 0,
        doneMeters: done,
        remainingMeters: Math.max(0, climb.length_m - done),
        fraction: done / climb.length_m,
    };
}
