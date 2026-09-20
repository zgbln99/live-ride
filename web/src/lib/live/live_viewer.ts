/**
 * Logika publicznej strony LIVE, oddzielona od rysowania.
 *
 * Wszystko tutaj jest czystą funkcją: strona bierze migawkę z serwera i pyta
 * ten moduł, co z niej wynika. Dzięki temu „po 80 sekundach ciszy piszemy
 * OFFLINE, a nie JEDZIE" da się sprawdzić testem, a nie tylko wzrokiem.
 */

/**
 * Stan zawodnika policzony po stronie serwera.
 *
 * `waiting` to zawodnik, od którego jeszcze nic nie przyszło — dopiero
 * udostępnił link i szuka pierwszego fiksa. To NIE jest `offline`: tamto
 * znaczy „milczy od ponad minuty" i czyta się jak awaria.
 */
export type RiderState =
    | "riding"
    | "paused"
    | "stopped"
    | "waiting"
    | "offline"
    | "ended";

/**
 * Jeden zawodnik w migawce.
 *
 * Prawie wszystko jest opcjonalne, bo prywatność rozstrzyga serwer: pole,
 * którego zawodnik nie udostępnia, w ogóle nie przychodzi. `undefined` znaczy
 * „nie wolno pokazać", a nie „zero" — i tak też musi to wyglądać na stronie.
 */
export type Rider = {
    id: string;
    display_name: string;
    state?: RiderState;
    last_seen_at: string;
    age_seconds?: number;
    role?: string;
    /** Chwila dołączenia do jazdy — znana, zanim przyjdzie pierwsza pozycja. */
    joined_at?: string;
    /** Czy od zawodnika przyszła kiedykolwiek pozycja. */
    has_fix?: boolean;
    latitude?: number;
    longitude?: number;
    altitude_m?: number;
    heading_deg?: number;
    accuracy_m?: number;
    distance_m?: number;
    elevation_gain_m?: number;
    moving_seconds?: number;
    speed_kmh?: number;
    max_speed_kmh?: number;
    heart_rate_bpm?: number;
    power_watts?: number;
    cadence_rpm?: number;
    battery_percent?: number;
    /** Czas zatrzymany przez licznik, bo rower stał. */
    auto_paused_seconds?: number;
    /** Czas zatrzymany palcem zawodnika. */
    manual_paused_seconds?: number;
    /** Czas od startu licznika razem z pauzami, liczony przez telefon. */
    elapsed_seconds?: number;
    /** Średnia z jazdy policzona przez serwer z dystansu i czasu w ruchu. */
    average_speed_kmh?: number;
    /** Nachylenie teraz. Ujemne na zjeździe — zero jest realnym pomiarem. */
    gradient_percent?: number;
    nav?: RiderNav;
    climb?: RiderClimb;
};

/**
 * Nawigacja tak, jak widzi ją zawodnik na kierownicy.
 *
 * Liczona w telefonie, nie tutaj: publiczna strona nie ma manewrów Valhalli,
 * a nawet gdyby je miała, musiałaby zgadywać, którym wariantem trasy ktoś
 * właśnie jedzie. Zamiast dwóch niezależnych nawigacji jest jedna, a ta
 * strona pokazuje jej stan.
 */
export type RiderNav = {
    instruction: string;
    street?: string;
    maneuver_type?: number;
    /** Ile metrów do manewru. */
    distance_m?: number;
    /** Ile metrów do mety według planu trasy. */
    remaining_m?: number;
    /** Sekundy do mety według planu trasy. */
    eta_seconds?: number;
    off_route?: boolean;
    off_route_m?: number;
};

/** Podjazd policzony w telefonie tym samym ClimbPro, który widzi zawodnik. */
export type RiderClimb = {
    index?: number;
    total?: number;
    done_m: number;
    length_m: number;
    gain_m: number;
    remaining_gain_m?: number;
    avg_gradient: number;
    max_gradient?: number;
    category?: string;
};

export type Meetup = { latitude: number; longitude: number; label: string };

export type SummaryRider = {
    id: string;
    display_name: string;
    distance_m?: number;
    elevation_gain_m?: number;
    moving_seconds?: number;
    avg_speed_kmh?: number;
    max_speed_kmh?: number;
    avg_heart_rate_bpm?: number;
    max_heart_rate_bpm?: number;
    avg_power_watts?: number;
    max_power_watts?: number;
};

export type Summary = {
    started_at: string;
    ended_at: string;
    elapsed_seconds: number;
    riders: SummaryRider[];
};

export type Snapshot = {
    /** "active" | "ended" dla żywego linku, albo powód, dla którego nie żyje. */
    status: "active" | "ended" | "expired" | "disabled";
    visibility?: "public" | "unlisted" | "disabled";
    title: string;
    kind?: string;
    trail_id?: string;
    has_route?: boolean;
    started_at?: string;
    ended_at?: string;
    expires_at?: string;
    server_time: string;
    riders: Rider[];
    meetup?: Meetup;
    summary?: Summary;
};

export type Climb = {
    start_m: number;
    length_m: number;
    gain_m: number;
    avg_gradient: number;
    max_gradient?: number;
    name?: string;
    category?: string;
};

/** Udział jednej nawierzchni w trasie, tak jak podał ją routing. */
export type Surface = { surface?: string; name?: string; distance_m?: number; meters?: number };

export type RouteSnapshot = {
    name?: string;
    polyline: string;
    /** Precyzja kodowania. Trasy Live Ride mają 6, stare ścieżki 5. */
    precision?: number;
    distance_m?: number;
    ascent_m?: number;
    descent_m?: number;
    elevation_profile?: { d: number; e: number }[];
    climbs?: Climb[];
    surfaces?: Surface[];
};

export type TrackSlice = {
    participant: string;
    polyline: string;
    precision?: number;
    cursor?: string;
};

export type LngLat = [number, number];

/** Kolejność kolorów zawodników. Stała, żeby nie skakały między odświeżeniami. */
export const RIDER_COLOURS = [
    "#00BFD8",
    "#FF8A3D",
    "#8B7BFF",
    "#31D07C",
    "#FF5C8A",
    "#F2C037",
    "#4BA3FF",
    "#FF6B4A",
];

/** Po tylu sekundach ciszy strona przestaje twierdzić, że pozycja jest świeża. */
export const OFFLINE_AFTER_SECONDS = 75;

export type StatusTone = "live" | "idle" | "waiting" | "offline" | "ended";

/**
 * Polska etykieta stanu zawodnika.
 *
 * `ageSeconds` liczy się od czasu SERWERA, nie przeglądarki: telefon widza z
 * zegarem przestawionym o dziesięć minut inaczej pokazywałby wszystkich jako
 * offline.
 */
export function riderStatus(
    state: RiderState | undefined,
    ageSeconds: number,
): { label: string; short: string; tone: StatusTone } {
    if (state === "ended") return { label: "ZAKOŃCZONY", short: "ZAKOŃCZONY", tone: "ended" };
    // „Czekam na GPS" wygrywa z wiekiem próbki, bo żadnej próbki jeszcze nie
    // było. Zawodnik, który przed chwilą wysłał link, nie stracił sygnału —
    // on go dopiero szuka, a to zupełnie inna wiadomość dla obserwującego.
    if (state === "waiting") {
        return { label: "OCZEKIWANIE NA GPS", short: "SZUKA GPS", tone: "waiting" };
    }
    if (state === "offline" || !Number.isFinite(ageSeconds) || ageSeconds > OFFLINE_AFTER_SECONDS) {
        // Pełne zdanie do panelu, skrót do plakietki nad mapą: na iPhonie SE
        // „BRAK AKTUALNYCH DANYCH" wchodziło na tytuł przejazdu.
        return { label: "BRAK AKTUALNYCH DANYCH", short: "BRAK SYGNAŁU", tone: "offline" };
    }
    switch (state) {
        case "paused":
            return { label: "PAUZA", short: "PAUZA", tone: "idle" };
        case "stopped":
            return { label: "POSTÓJ", short: "POSTÓJ", tone: "idle" };
        default:
            return { label: "JEDZIE", short: "JEDZIE", tone: "live" };
    }
}

/**
 * Wartość chwilowa — prędkość, tętno, moc, kadencja.
 *
 * Gdy telefon zawodnika milczy, ostatnia znana prędkość nie jest jego
 * prędkością, tylko prędkością sprzed trzech minut. Pozycja zostaje na mapie
 * (o tym mówi opis „ostatnia znana"), ale liczba, która wygląda na pomiar z
 * tej sekundy, znika.
 */
export function liveOnly<T>(value: T, tone: StatusTone): T | undefined {
    return tone === "offline" || tone === "waiting" ? undefined : value;
}

/** „przed chwilą", „42 s temu", „3 min temu". */
export function ago(seconds: number): string {
    if (!Number.isFinite(seconds)) return "brak danych";
    const value = Math.max(0, Math.round(seconds));
    if (value < 10) return "przed chwilą";
    if (value < 60) return `${value} s temu`;
    if (value < 3600) return `${Math.floor(value / 60)} min temu`;
    if (value < 86400) return `${Math.floor(value / 3600)} godz. temu`;
    return `${Math.floor(value / 86400)} dni temu`;
}

/** Dystans po polsku: metry pod kilometrem, potem kilometry. */
export function distance(meters: number | undefined): string {
    if (meters === undefined || !Number.isFinite(meters)) return "—";
    if (meters < 1000) return `${Math.round(meters)} m`;
    const km = meters / 1000;
    return `${km.toFixed(km >= 100 ? 0 : km >= 10 ? 1 : 2).replace(".", ",")} km`;
}

/** Czas trwania jako 1:23:45 albo 23:45. */
export function duration(seconds: number | undefined): string {
    if (seconds === undefined || !Number.isFinite(seconds) || seconds < 0) return "—";
    const total = Math.floor(seconds);
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    const pad = (value: number) => String(value).padStart(2, "0");
    return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

/**
 * Czas zaokrąglony do minut: „3 godz. 17 min".
 *
 * Do oszacowań, nie do pomiarów. „3:17:17" przy szacunku sugeruje dokładność,
 * której nie ma.
 */
export function durationCoarse(seconds: number | undefined): string {
    if (seconds === undefined || !Number.isFinite(seconds) || seconds < 0) return "—";
    const minutes = Math.round(seconds / 60);
    const h = Math.floor(minutes / 60);
    const m = minutes % 60;
    if (h === 0) return `${m} min`;
    return m === 0 ? `${h} godz.` : `${h} godz. ${m} min`;
}

/** Godzina bez sekund, w strefie widza. */
export function clock(value: string | undefined | null): string {
    if (!value) return "—";
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) return "—";
    return parsed.toLocaleTimeString("pl-PL", { hour: "2-digit", minute: "2-digit" });
}

/** Liczba albo kreska — nigdy zero udające pomiar. */
export function num(value: number | undefined, digits = 0): string {
    if (value === undefined || !Number.isFinite(value)) return "—";
    return value.toFixed(digits).replace(".", ",");
}

/** Inicjały na awatarze. */
export function initials(name: string): string {
    const parts = (name ?? "").trim().split(/[\s_.-]+/).filter(Boolean);
    if (!parts.length) return "?";
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
}

/** Kierunek świata dla kursu w stopniach. */
export function compass(degrees: number | undefined): string {
    if (degrees === undefined || !Number.isFinite(degrees)) return "";
    const labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
    return labels[Math.round((((degrees % 360) + 360) % 360) / 45) % 8];
}

export function hasPosition(rider: Rider): boolean {
    return (
        Number.isFinite(rider.latitude) &&
        Number.isFinite(rider.longitude) &&
        !(rider.latitude === 0 && rider.longitude === 0)
    );
}

/**
 * Czasy jednego zawodnika.
 *
 * Trzy różne liczby, które łatwo pomylić: zegarowy czas od startu, czas
 * w ruchu i czas stania. Ostatni jest znany tylko wtedy, gdy licznik go
 * przysłał — różnica „całkowity minus w ruchu" to nie postoje, bo zawiera
 * także sekundy poniżej progu auto-pauzy.
 */
export type RideTimes = {
    elapsedSeconds: number | undefined;
    movingSeconds: number | undefined;
    pausedSeconds: number | undefined;
    autoPausedSeconds: number | undefined;
    manualPausedSeconds: number | undefined;
};

export function rideTimes(
    rider: Rider | null,
    startedAt: string | undefined,
    endedAt: string | undefined,
    serverNow: number,
): RideTimes {
    // Zegar licznika zawodnika wygrywa z różnicą „teraz minus start sesji":
    // link bywa udostępniony na kwadrans przed startem, a wtedy ta różnica
    // nie jest czasem jazdy tylko czasem od udostępnienia.
    let elapsedSeconds: number | undefined = rider?.elapsed_seconds;
    if (elapsedSeconds === undefined && startedAt) {
        const started = new Date(startedAt).getTime();
        if (!Number.isNaN(started)) {
            const finished = endedAt ? new Date(endedAt).getTime() : NaN;
            const reference = Number.isNaN(finished) ? serverNow : finished;
            elapsedSeconds = Math.max(0, (reference - started) / 1000);
        }
    }

    const auto = rider?.auto_paused_seconds;
    const manual = rider?.manual_paused_seconds;
    const paused =
        auto === undefined && manual === undefined ? undefined : (auto ?? 0) + (manual ?? 0);

    return {
        elapsedSeconds,
        movingSeconds: rider?.moving_seconds,
        pausedSeconds: paused,
        autoPausedSeconds: auto,
        manualPausedSeconds: manual,
    };
}

const EARTH_RADIUS_METERS = 6371008.8;

export function haversine(a: LngLat, b: LngLat): number {
    const toRad = Math.PI / 180;
    const dLat = (b[1] - a[1]) * toRad;
    const dLon = (b[0] - a[0]) * toRad;
    const lat1 = a[1] * toRad;
    const lat2 = b[1] * toRad;
    const h =
        Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
    return 2 * EARTH_RADIUS_METERS * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

/** Narastający dystans wzdłuż linii; ostatnia pozycja to jej długość. */
export function cumulativeDistances(coordinates: LngLat[]): number[] {
    const cumulative: number[] = [];
    let total = 0;
    for (let i = 0; i < coordinates.length; i++) {
        if (i > 0) total += haversine(coordinates[i - 1], coordinates[i]);
        cumulative.push(total);
    }
    return cumulative;
}

export type Projection = { alongMeters: number; offRouteMeters: number };

/**
 * Rzutuje zawodnika na trasę i mówi, ile z niej przejechał.
 *
 * Rzut jest na odcinek, nie na wierzchołek, więc postęp płynie między dwoma
 * odległymi punktami trasy zamiast skakać z jednego na drugi.
 */
export function projectOnRoute(
    coordinates: LngLat[],
    cumulative: number[],
    lon: number,
    lat: number,
): Projection | null {
    if (coordinates.length < 2 || !Number.isFinite(lon) || !Number.isFinite(lat)) return null;
    const latScale = Math.max(0.05, Math.abs(Math.cos((lat * Math.PI) / 180)));
    let best: Projection | null = null;

    for (let i = 0; i < coordinates.length - 1; i++) {
        const a = coordinates[i];
        const b = coordinates[i + 1];
        const bx = (b[0] - a[0]) * latScale * 111320;
        const by = (b[1] - a[1]) * 110540;
        const px = (lon - a[0]) * latScale * 111320;
        const py = (lat - a[1]) * 110540;
        const lengthSquared = bx * bx + by * by;
        let t = 0;
        if (lengthSquared > 0) t = Math.min(1, Math.max(0, (px * bx + py * by) / lengthSquared));
        const dx = px - bx * t;
        const dy = py - by * t;
        const offRouteMeters = Math.sqrt(dx * dx + dy * dy);
        if (!best || offRouteMeters < best.offRouteMeters) {
            const segment = cumulative[i + 1] - cumulative[i];
            best = { alongMeters: cumulative[i] + segment * t, offRouteMeters };
        }
    }
    return best;
}

/** Ponad tyle metrów od trasy przestajemy liczyć postęp i ETA. */
export const OFF_ROUTE_LIMIT_METERS = 400;

/**
 * Tempo, na którym opieramy ETA, w km/h.
 *
 * Średnia z całej jazdy, a nie prędkość chwilowa: ETA skaczące od 40 minut do
 * 4 godzin przy każdym podjeździe jest gorsze niż jego brak. Prędkość chwilowa
 * służy tylko za awaryjne źródło, gdy średniej jeszcze nie ma.
 */
export function paceKmh(rider: Rider): number | null {
    const moving = rider.moving_seconds;
    const ridden = rider.distance_m;
    if (moving !== undefined && ridden !== undefined && moving > 120 && ridden > 500) {
        const average = (ridden / moving) * 3.6;
        if (average > 3 && average < 90) return average;
    }
    const current = rider.speed_kmh;
    if (current !== undefined && current > 6) return current;
    return null;
}

export type RouteProgress = {
    alongMeters: number;
    remainingMeters: number;
    fraction: number;
    offRouteMeters: number;
    /** Sekundy do mety albo null, gdy nie ma z czego ich policzyć. */
    etaSeconds: number | null;
    /** Godzina przyjazdu albo null. */
    etaAt: Date | null;
};

/** Postęp na trasie i przewidywany czas przyjazdu. */
export function routeProgress(
    rider: Rider,
    projection: Projection | null,
    routeLengthMeters: number,
    now: number,
): RouteProgress | null {
    if (!projection || routeLengthMeters <= 0) return null;
    if (projection.offRouteMeters > OFF_ROUTE_LIMIT_METERS) return null;

    const alongMeters = Math.min(projection.alongMeters, routeLengthMeters);
    const remainingMeters = Math.max(0, routeLengthMeters - alongMeters);
    const pace = paceKmh(rider);
    // Zjechany z trasy albo stojący zawodnik nie dostaje ETA zamiast
    // dostać ETA zmyślonego.
    const etaSeconds = pace === null ? null : (remainingMeters / 1000 / pace) * 3600;

    return {
        alongMeters,
        remainingMeters,
        fraction: Math.min(1, alongMeters / routeLengthMeters),
        offRouteMeters: projection.offRouteMeters,
        etaSeconds,
        etaAt: etaSeconds === null ? null : new Date(now + etaSeconds * 1000),
    };
}

/** Najbliższy podjazd przed zawodnikiem, albo null, gdy już za wszystkimi. */
export function nextClimb(climbs: Climb[] | undefined, alongMeters: number): (Climb & { distanceAheadMeters: number }) | null {
    if (!climbs?.length) return null;
    const ordered = [...climbs].sort((a, b) => a.start_m - b.start_m);
    for (const climb of ordered) {
        const end = climb.start_m + climb.length_m;
        if (end <= alongMeters) continue;
        return { ...climb, distanceAheadMeters: Math.max(0, climb.start_m - alongMeters) };
    }
    return null;
}

/**
 * Względna pozycja zawodników w grupie.
 *
 * Liczona wzdłuż trasy, nigdy w linii prostej: zawodnik po drugiej stronie
 * wzgórza jest bliżej mety na mapie i dalej od niej na drodze. Bez trasy nie
 * pokazujemy nic — „320 m za Markiem" wyssane z palca jest gorsze niż cisza.
 */
export function relativeGap(
    riderAlong: number | null,
    leaderAlong: number | null,
): string | null {
    if (riderAlong === null || leaderAlong === null) return null;
    const gap = leaderAlong - riderAlong;
    if (!Number.isFinite(gap)) return null;
    if (Math.abs(gap) < 40) return "razem z prowadzącym";
    return gap > 0 ? `${distance(gap)} za prowadzącym` : `${distance(-gap)} przed prowadzącym`;
}

/**
 * Punkt na profilu wysokości odpowiadający pozycji na trasie.
 *
 * Zwraca indeks i wysokość, żeby strona mogła postawić znacznik bez
 * przeszukiwania profilu przy każdej klatce.
 */
export function elevationAt(
    profile: { d: number; e: number }[] | undefined,
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

/**
 * Strzałka manewru dla typu z Valhalli.
 *
 * Te same numery, które w aplikacji wybierają ikonę Material — tutaj muszą
 * wystarczyć znaki, bo publiczna strona nie ładuje zestawu ikon dla jednego
 * trójkąta. Nieznany typ dostaje strzałkę w górę, nie pustkę: widz ma
 * widzieć, że manewr jest, nawet gdy nie wiemy który.
 */
export function maneuverArrow(type: number | undefined): string {
    switch (type) {
        case 4:
        case 5:
        case 6:
            return "\u25C9"; // meta
        case 9:
            return "\u2197"; // lekko w prawo
        case 10:
        case 11:
            return "\u21B1"; // w prawo
        case 12:
        case 13:
            return "\u21B6"; // zawracanie
        case 14:
        case 15:
            return "\u21B0"; // w lewo
        case 16:
            return "\u2196"; // lekko w lewo
        case 26:
        case 27:
            return "\u21BB"; // rondo
        default:
            return "\u2191";
    }
}

/**
 * Dystans do manewru, zaokrąglony tak, jak czyta go człowiek na rowerze.
 *
 * „za 312 m" sugeruje precyzję, której GPS nie ma, i zmienia się co sekundę.
 * Poniżej stu metrów liczy się co dziesięć, wyżej co pięćdziesiąt.
 */
export function maneuverDistance(meters: number | undefined): string {
    if (meters === undefined || !Number.isFinite(meters)) return "";
    if (meters < 20) return "teraz";
    if (meters < 100) return `za ${Math.round(meters / 10) * 10} m`;
    if (meters < 1000) return `za ${Math.round(meters / 50) * 50} m`;
    return `za ${distance(meters)}`;
}
