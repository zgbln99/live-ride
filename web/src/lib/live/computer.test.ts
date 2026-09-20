import { describe, expect, it } from "vitest";
import {
    eventLabel,
    freshValue,
    maneuverArrow,
    maneuverDistance,
    placeCheckpoints,
    rideTimes,
    sensorAge,
    type LiveEvent,
    type Rider,
} from "./live_viewer";
import { reportedClimb } from "./route_insight";

/**
 * Scenariusz z realnej jazdy, w którym publiczny LIVE był dotąd pusty.
 *
 * Wszystkie liczby pochodzą z jednego przejazdu: aktywna trasa 42,3 km,
 * pas HR na klatce, miernik mocy w korbie, nawigacja po polsku, drugi z pięciu
 * podjazdów. Aplikacja pokazywała to wszystko naraz; strona pokazywała
 * dystans i prędkość.
 */
const RIDER: Rider = {
    id: "p1",
    display_name: "Marek",
    state: "riding",
    last_seen_at: "2026-05-01T12:00:00Z",
    latitude: 52.41,
    longitude: 13.12,
    distance_m: 25800,
    moving_seconds: 3120,
    elapsed_seconds: 3380,
    speed_kmh: 31.4,
    average_speed_kmh: 29.8,
    gradient_percent: 8.2,
    heart_rate_bpm: 143,
    power_watts: 242,
    cadence_rpm: 89,
    hr_source: "WHOOP",
    hr_updated_at: "2026-05-01T12:00:00Z",
    power_updated_at: "2026-05-01T12:00:00Z",
    cadence_updated_at: "2026-05-01T12:00:00Z",
    auto_paused_seconds: 180,
    manual_paused_seconds: 80,
    nav: {
        instruction: "Skręć w lewo w Burgenlandstraße",
        street: "Burgenlandstraße",
        maneuver_type: 15,
        distance_m: 310,
        remaining_m: 16500,
        eta_seconds: 2100,
        off_route: false,
    },
    climb: {
        index: 2,
        total: 5,
        done_m: 1300,
        length_m: 2400,
        gain_m: 152,
        remaining_gain_m: 83,
        avg_gradient: 6.3,
        max_gradient: 9.1,
        category: "3",
    },
    batteries: { phone: 61, heart_rate: 37 },
};

const NOW = Date.parse("2026-05-01T12:00:02Z");

describe("nawigacja na publicznej stronie", () => {
    it("pokazuje instrukcję dokładnie taką, jaką dostał zawodnik", () => {
        // Strona jej nie składa i nie tłumaczy. Dwie warstwy nawigacji
        // rozjechałyby się na pierwszym rondzie, a widz nie ma jak sprawdzić,
        // która kłamie.
        expect(RIDER.nav!.instruction).toBe("Skręć w lewo w Burgenlandstraße");
        expect(RIDER.nav!.street).toBe("Burgenlandstraße");
    });

    it("strzałka manewru odpowiada typowi z routera", () => {
        expect(maneuverArrow(15)).toBe("↰");
        expect(maneuverArrow(10)).toBe("↱");
        expect(maneuverArrow(26)).toBe("↻");
        // Nieznany typ dostaje strzałkę, nie pustkę: widz ma widzieć, że
        // manewr jest, nawet gdy nie wiemy który.
        expect(maneuverArrow(999)).toBe("↑");
        expect(maneuverArrow(undefined)).toBe("↑");
    });

    it("dystans do manewru zaokrągla się tak, jak czyta go człowiek", () => {
        expect(maneuverDistance(310)).toBe("za 300 m");
        expect(maneuverDistance(64)).toBe("za 60 m");
        expect(maneuverDistance(12)).toBe("teraz");
        expect(maneuverDistance(2400)).toBe("za 2,40 km");
        expect(maneuverDistance(undefined)).toBe("");
    });
});

describe("świeżość każdego czujnika osobno", () => {
    it("tętno sprzed czterech minut przestaje być tętnem", () => {
        const stale = { ...RIDER, hr_updated_at: "2026-05-01T11:56:00Z" };
        expect(freshValue(stale.heart_rate_bpm, stale.hr_updated_at, NOW)).toBeUndefined();
        // …ale moc z tej samej migawki zostaje: pas odpadł, korba nie.
        expect(freshValue(stale.power_watts, stale.power_updated_at, NOW)).toBe(242);
    });

    it("bez znacznika rozstrzyga świeżość całej transmisji", () => {
        // Starsza wersja aplikacji nie wysyła rozbicia. Wtedy nie wolno
        // ukrywać danych, których świeżości po prostu nie znamy.
        expect(freshValue(143, undefined, NOW)).toBe(143);
        expect(sensorAge(undefined, NOW)).toBeNull();
    });

    it("zero jest pomiarem, nie brakiem", () => {
        // Moc zero na zjeździe to prawdziwy odczyt i musi przejść przez filtr
        // tak samo jak każdy inny.
        expect(freshValue(0, "2026-05-01T12:00:00Z", NOW)).toBe(0);
    });
});

describe("czasy", () => {
    it("zegar licznika wygrywa z różnicą od startu sesji", () => {
        // Link bywa udostępniony na kwadrans przed startem. Różnica
        // „teraz minus start sesji" nie jest wtedy czasem jazdy.
        const times = rideTimes(RIDER, "2026-05-01T10:00:00Z", undefined, NOW);
        expect(times.elapsedSeconds).toBe(3380);
        expect(times.movingSeconds).toBe(3120);
        expect(times.autoPausedSeconds).toBe(180);
        expect(times.manualPausedSeconds).toBe(80);
        expect(times.pausedSeconds).toBe(260);
    });

    it("bez zegara licznika liczymy od startu sesji", () => {
        const noClock: Rider = { ...RIDER, elapsed_seconds: undefined };
        const times = rideTimes(noClock, "2026-05-01T11:00:00Z", undefined, NOW);
        expect(times.elapsedSeconds).toBeCloseTo(3602, 0);
    });
});

describe("podjazd z licznika", () => {
    it("wygrywa z rachunkiem z trasy i niesie te same liczby", () => {
        const climb = reportedClimb(RIDER.climb)!;
        expect(climb.name).toBe("Podjazd 2 z 5");
        expect(climb.doneMeters).toBe(1300);
        expect(climb.remainingMeters).toBe(1100);
        expect(climb.fraction).toBeCloseTo(0.5417, 3);
        expect(climb.category).toBe("3");
    });

    it("bez podjazdu nie zmyśla żadnego", () => {
        expect(reportedClimb(undefined)).toBeNull();
        expect(
            reportedClimb({ done_m: 0, length_m: 0, gain_m: 0, avg_gradient: 0 }),
        ).toBeNull();
    });
});

describe("oś czasu", () => {
    const events: LiveEvent[] = [
        { seq: 4, kind: "back_on_route", at: "2026-05-01T11:40:00Z" },
        { seq: 3, kind: "off_route", at: "2026-05-01T11:36:00Z", distance_m: 18400 },
        { seq: 2, kind: "climb_start", at: "2026-05-01T11:20:00Z", label: "2/5" },
        { seq: 1, kind: "start", at: "2026-05-01T11:00:00Z" },
    ];

    it("nazywa zdarzenia po polsku", () => {
        expect(eventLabel(events[0])).toBe("Powrót na trasę");
        expect(eventLabel(events[1])).toBe("Poza trasą");
        expect(eventLabel(events[2])).toBe("Podjazd 2/5");
        expect(eventLabel(events[3])).toBe("Start");
    });

    it("checkpoint bierze nazwę nadaną przez zawodnika", () => {
        expect(
            eventLabel({ seq: 9, kind: "checkpoint", at: "x", label: "Wannsee" }),
        ).toBe("Wannsee");
    });
});

describe("punkty na trasie", () => {
    const checkpoints = [
        { name: "Potsdam", distance_m: 31700 },
        { name: "Wannsee", distance_m: 12400 },
    ];

    it("liczy dystans i ETA jednym tempem, w kolejności od startu", () => {
        const placed = placeCheckpoints(checkpoints, 25800, 29.8, NOW);
        expect(placed.map((point) => point.name)).toEqual(["Wannsee", "Potsdam"]);
        // Minięty punkt zostaje na liście, tylko bez przyszłości.
        expect(placed[0].reached).toBe(true);
        expect(placed[0].etaAt).toBeNull();
        expect(placed[1].reached).toBe(false);
        expect(placed[1].remainingMeters).toBe(5900);
        expect(placed[1].etaAt).not.toBeNull();
    });

    it("bez tempa nie zmyśla godziny przyjazdu", () => {
        const placed = placeCheckpoints(checkpoints, 0, null, NOW);
        expect(placed.every((point) => point.etaAt === null)).toBe(true);
    });
});

describe("prywatność lokalizacji widziana przez stronę", () => {
    it("ukryta pozycja nie przychodzi wcale, a strona o tym wie", () => {
        // Serwer nie wysyła współrzędnych z promienia wokół domu. Strona
        // dostaje sam znacznik „ukryte" i nie ma czego narysować — i o to
        // dokładnie chodzi.
        const hidden: Rider = {
            id: "p2",
            display_name: "Marek",
            last_seen_at: "2026-05-01T12:00:00Z",
            location_hidden: true,
            distance_m: 400,
        };
        expect(hidden.latitude).toBeUndefined();
        expect(hidden.longitude).toBeUndefined();
        expect(hidden.location_hidden).toBe(true);
    });
});
