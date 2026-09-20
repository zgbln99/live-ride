import { describe, expect, it } from "vitest";
import { render } from "svelte/server";

import RiderCard from "./RiderCard.svelte";
import PrimaryMetrics from "./PrimaryMetrics.svelte";
import RouteProgressSection from "./RouteProgress.svelte";
import ClimbCard from "./ClimbCard.svelte";
import UpcomingClimbs from "./UpcomingClimbs.svelte";
import SensorMetrics from "./SensorMetrics.svelte";
import RouteWeather from "./RouteWeather.svelte";
import GroupRiders from "./GroupRiders.svelte";
import RideSummary from "./RideSummary.svelte";
import LiveHeader from "./LiveHeader.svelte";

import { rideTimes } from "$lib/live/live_viewer";
import { currentClimb, upcomingClimbs } from "$lib/live/route_insight";

/**
 * Renderowanie sekcji publicznego LIVE.
 *
 * Testy sprawdzają dwie rzeczy, których nie widać w logice: że dane, których
 * zawodnik nie udostępnił, NIE pojawiają się w wysłanym HTML-u, i że sekcja
 * bez danych znika zamiast pokazywać rząd kresek. Pierwsze to prywatność
 * (ukrycie CSS-em nie jest ukryciem), drugie to obietnica interfejsu, który
 * składa się z tego, co naprawdę wiemy.
 */

const NO_TIMES = rideTimes(null, undefined, undefined, Date.now());

describe("karta zawodnika", () => {
    it("przed pierwszym fiksem mówi, że czekamy na GPS", () => {
        const { body } = render(RiderCard, {
            props: {
                name: "Marek",
                statusLabel: "OCZEKIWANIE NA GPS",
                statusTone: "waiting" as const,
                ageSeconds: Number.POSITIVE_INFINITY,
                colour: "#00BFD8",
                hasFix: false,
            },
        });
        expect(body).toContain("Marek");
        expect(body).toContain("OCZEKIWANIE NA GPS");
        expect(body).toContain("Pozycja pojawi się za chwilę.");
        // Ani słowa o utracie sygnału: zawodnik go dopiero szuka.
        expect(body).not.toContain("BRAK");
    });

    it("po pierwszym fiksie pokazuje wiek próbki", () => {
        const { body } = render(RiderCard, {
            props: {
                name: "Marek",
                statusLabel: "POSTÓJ",
                statusTone: "idle" as const,
                ageSeconds: 4,
                colour: "#00BFD8",
                hasFix: true,
            },
        });
        expect(body).toContain("POSTÓJ");
        expect(body).toContain("przed chwilą");
    });
});

describe("nagłówek", () => {
    it("niesie markę, tytuł i stan już w pierwszym HTML-u", () => {
        const { body } = render(LiveHeader, {
            props: {
                title: "Sudety · sobotnia pętla",
                statusLabel: "JEDZIE",
                statusTone: "live" as const,
                subtitle: "Berlin → Potsdam",
            },
        });
        expect(body).toContain("LIVE");
        expect(body).toContain("RIDE");
        expect(body).toContain("Sudety · sobotnia pętla");
        expect(body).toContain("Berlin → Potsdam");
        expect(body).toContain("JEDZIE");
    });
});

describe("najważniejsze dane", () => {
    const base = {
        distanceMeters: 42800,
        times: rideTimes(
            { id: "1", display_name: "Marek", last_seen_at: "", moving_seconds: 5502 },
            "2026-05-01T12:00:00Z",
            undefined,
            Date.parse("2026-05-01T14:00:00Z"),
        ),
        speedKmh: 31.4,
        remainingMeters: 35200,
        averageSpeedKmh: 28.2,
        elevationGainMeters: 612,
        altitudeMeters: 148,
        etaAt: new Date("2026-05-01T16:42:00Z"),
    };

    it("pokazuje dystans, czas w ruchu, prędkość i dystans do mety", () => {
        const { body } = render(PrimaryMetrics, { props: base });
        expect(body).toContain("42,8 km");
        expect(body).toContain("1:31:42");
        expect(body).toContain("31,4");
        expect(body).toContain("35,2 km");
        expect(body).toContain("Do mety");
    });

    it("bez trasy nie ma „do mety”, jest czas całkowity", () => {
        const { body } = render(PrimaryMetrics, {
            props: { ...base, remainingMeters: undefined, etaAt: null },
        });
        expect(body).not.toContain("Do mety");
        expect(body).toContain("Czas całkowity");
        expect(body).toContain("2:00:00");
    });

    it("stojący zawodnik ma zera i kreski, nie zmyślone liczby", () => {
        const { body } = render(PrimaryMetrics, {
            props: {
                distanceMeters: 0,
                times: NO_TIMES,
                speedKmh: 0,
                remainingMeters: undefined,
                averageSpeedKmh: undefined,
                elevationGainMeters: 0,
                altitudeMeters: undefined,
                etaAt: null,
            },
        });
        expect(body).toContain("0 m");
        // Brak średniej to kreska, nie zero — zera nikt nie zmierzył.
        expect(body).toContain("—");
    });
});

describe("postęp na trasie", () => {
    it("liczy procent, pozostały dystans i ETA", () => {
        const { body } = render(RouteProgressSection, {
            props: {
                routeName: "Berlin → Potsdam",
                totalMeters: 78400,
                progress: {
                    alongMeters: 43200,
                    remainingMeters: 35200,
                    fraction: 43200 / 78400,
                    offRouteMeters: 12,
                    etaSeconds: 4500,
                    etaAt: new Date("2026-05-01T16:42:00Z"),
                },
                offRouteMeters: null,
            },
        });
        expect(body).toContain("Berlin → Potsdam");
        expect(body).toContain("78,4 km");
        expect(body).toContain("43,2 km");
        expect(body).toContain("35,2 km");
        expect(body).toContain("55%");
    });

    it("zjazd z trasy mówi wprost, jak daleko", () => {
        const { body } = render(RouteProgressSection, {
            props: {
                routeName: "",
                totalMeters: 78400,
                progress: null,
                offRouteMeters: 180,
            },
        });
        expect(body).toContain("Poza trasą");
        expect(body).toContain("180 m");
    });
});

describe("podjazdy", () => {
    const climbs = [
        { start_m: 5000, length_m: 4200, gain_m: 240, avg_gradient: 5.4, max_gradient: 9.1, name: "Katzenberg" },
        { start_m: 21000, length_m: 2100, gain_m: 126, avg_gradient: 6.0, name: "Teufelsberg" },
    ];

    it("aktualny podjazd pokazuje, ile zostało do szczytu", () => {
        const climb = currentClimb(climbs, 7800)!;
        const { body } = render(ClimbCard, { props: { climb } });
        expect(body).toContain("Katzenberg");
        expect(body).toContain("2,80 km");
        expect(body).toContain("1,40 km");
        expect(body).toContain("5,4");
        expect(body).toContain("9,1");
    });

    it("kolejne podjazdy podają odległość i profil", () => {
        const next = upcomingClimbs(climbs, 1000, 3);
        const { body } = render(UpcomingClimbs, {
            props: { climbs: next, total: climbs.length },
        });
        expect(body).toContain("Katzenberg");
        expect(body).toContain("Teufelsberg");
        expect(body).toContain("Za 4,00 km");
        expect(body).toContain("126 m ↑");
    });
});

describe("czujniki i prywatność", () => {
    it("pokazuje tylko to, co przyszło z serwera", () => {
        const { body } = render(SensorMetrics, {
            props: {
                heartRate: 154,
                power: undefined,
                cadence: undefined,
                batteryPercent: 72,
                maxSpeedKmh: undefined,
            },
        });
        expect(body).toContain("154");
        expect(body).toContain("72");
        // Moc, której zawodnik nie udostępnia, nie ma tu nawet pustego panelu:
        // „MOC —" czyta się jak usterka, choć po prostu nikt nie ma miernika.
        expect(body).not.toContain("Moc");
        expect(body).not.toContain("Kadencja");
    });

    it("bez żadnego czujnika cała sekcja znika", () => {
        const { body } = render(SensorMetrics, {
            props: {
                heartRate: undefined,
                power: undefined,
                cadence: undefined,
                batteryPercent: undefined,
                maxSpeedKmh: undefined,
            },
        });
        // Nic poza znacznikami sterującymi Svelte — żadnego nagłówka,
        // żadnego panelu, żadnej kreski.
        expect(body).not.toContain("Dane z jazdy");
        expect(body).not.toContain("lr-grid");
    });
});

describe("pogoda", () => {
    const forecasts = [
        {
            label: "now" as const,
            aheadMeters: 0,
            at: new Date("2026-05-01T12:00:00Z"),
            hour: {
                at: "2026-05-01T12:00:00Z",
                temp_c: 18,
                code: 3,
                wind_kmh: 14,
                wind_from_deg: 90,
            },
            wind: {
                speedKmh: 14,
                alongKmh: -9,
                crossKmh: 4,
                kind: "head" as const,
                label: "CZOŁOWY",
            },
        },
        {
            label: "ahead" as const,
            aheadMeters: 20000,
            at: new Date("2026-05-01T13:00:00Z"),
            hour: {
                at: "2026-05-01T13:00:00Z",
                temp_c: 17,
                code: 61,
                precip_probability: 40,
            },
            wind: null,
        },
    ];

    it("pokazuje wiatr jako to, co rowerzysta poczuje", () => {
        const { body } = render(RouteWeather, {
            props: { forecasts, alert: null, sunset: null },
        });
        expect(body).toContain("TERAZ");
        expect(body).toContain("CZOŁOWY");
        expect(body).toContain("18");
        expect(body).toContain("ZA 20 KM");
        expect(body).toContain("40% deszczu");
        expect(body).toContain("Deszcz");
    });

    it("ostrzeżenie to jedno zdanie, nie feed", () => {
        const { body } = render(RouteWeather, {
            props: {
                forecasts,
                alert: { title: "DESZCZ ZA OKOŁO 28 MIN", detail: "Prognoza daje 60% szans." },
                sunset: null,
            },
        });
        expect(body).toContain("DESZCZ ZA OKOŁO 28 MIN");
        expect(body).toContain("Prognoza daje 60% szans.");
    });

    it("przyjazd po zmroku jest powiedziany wprost", () => {
        const { body } = render(RouteWeather, {
            props: {
                forecasts,
                alert: null,
                sunset: {
                    at: new Date("2026-05-01T19:34:00Z"),
                    secondsAway: 4320,
                    arrivesAfterSunset: true,
                },
            },
        });
        expect(body).toContain("Zachód słońca");
        expect(body).toContain("Przewidywany przyjazd po zachodzie słońca.");
    });
});

describe("grupa", () => {
    it("wymienia uczestników z dystansem i stratą do prowadzącego", () => {
        const { body } = render(GroupRiders, {
            props: {
                riders: [
                    {
                        id: "a",
                        name: "Marek",
                        colour: "#00BFD8",
                        statusLabel: "JEDZIE",
                        statusTone: "live" as const,
                        distanceMeters: 43200,
                        gap: null,
                    },
                    {
                        id: "b",
                        name: "Paweł",
                        colour: "#FF8A3D",
                        statusLabel: "JEDZIE",
                        statusTone: "live" as const,
                        distanceMeters: 42700,
                        gap: "500 m za prowadzącym",
                    },
                ],
                selectedId: "a",
                onselect: () => {},
            },
        });
        expect(body).toContain("Marek");
        expect(body).toContain("Paweł");
        expect(body).toContain("500 m za prowadzącym");
        expect(body).toContain("43,2 km");
        // Wybrany jest oznaczony dla czytnika ekranu, nie tylko kolorem.
        expect(body).toContain('aria-pressed="true"');
    });
});

describe("po mecie", () => {
    it("pokazuje podsumowanie zamiast liczb na żywo", () => {
        const { body } = render(RideSummary, {
            props: {
                rider: {
                    id: "a",
                    display_name: "Marek",
                    distance_m: 78400,
                    moving_seconds: 10052,
                    elevation_gain_m: 920,
                    max_speed_kmh: 62.4,
                    avg_speed_kmh: 28.1,
                    avg_heart_rate_bpm: 148,
                    max_heart_rate_bpm: 176,
                },
                elapsedSeconds: 11294,
                climbs: {
                    count: 4,
                    totalGainMeters: 920,
                    longest: { start_m: 0, length_m: 4200, gain_m: 240, avg_gradient: 5.4 },
                    steepestPercent: 11,
                },
            },
        });
        expect(body).toContain("78,4 km");
        expect(body).toContain("2:47:32");
        expect(body).toContain("3:08:14");
        expect(body).toContain("28,1");
        expect(body).toContain("62,4");
        expect(body).toContain("920");
        expect(body).toContain("148");
        expect(body).toContain("Podjazdy");
    });

    it("bez mocy nie ma panelu mocy również w podsumowaniu", () => {
        const { body } = render(RideSummary, {
            props: {
                rider: { id: "a", display_name: "Marek", distance_m: 78400 },
                elapsedSeconds: 11294,
                climbs: null,
            },
        });
        expect(body).not.toContain("Moc śr.");
        expect(body).not.toContain("Podjazdy");
    });
});
