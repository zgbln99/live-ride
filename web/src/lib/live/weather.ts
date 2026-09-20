/**
 * Pogoda tam, gdzie zawodnik dopiero będzie.
 *
 * Serwer przysyła surową serię godzinową dla kilku punktów wzdłuż trasy i kurs
 * jazdy w każdym z nich. Wszystko, co robi ten moduł, to odpowiedź na trzy
 * pytania, których nie da się zadać serwerowi, bo zależą od tempa liczonego
 * w przeglądarce:
 *
 *   1. którą godzinę z serii czytać dla danego punktu,
 *   2. czy wiatr będzie czołowy, tylny czy boczny,
 *   3. czy w tym, co przed zawodnikiem, jest coś, o czym warto uprzedzić.
 *
 * Nic tu nie zgaduje. Brak pola w odpowiedzi dostawcy oznacza brak wartości,
 * a nie zero — zero procent szansy na deszcz to obietnica, nie brak danych.
 */

export type WeatherHour = {
    at: string;
    temp_c?: number;
    precip_probability?: number;
    code?: number;
    wind_kmh?: number;
    wind_from_deg?: number;
};

export type WeatherPoint = {
    label: "now" | "ahead" | "finish" | string;
    along_m: number;
    ahead_m: number;
    bearing_deg?: number;
    hours: WeatherHour[];
};

export type WeatherSnapshot = {
    server_time?: string;
    sunrise?: string;
    sunset?: string;
    points: WeatherPoint[];
};

/**
 * Godzina z serii najbliższa zadanej chwili.
 *
 * Seria jest godzinowa, więc „najbliższa" znaczy co najwyżej pół godziny
 * w jedną albo drugą stronę. Dalej niż godzinę poza serię nie zgadujemy —
 * prognoza, której dostawca nie wydał, nie istnieje.
 */
export function hourAt(hours: WeatherHour[] | undefined, at: number): WeatherHour | null {
    if (!hours?.length) return null;
    let best: WeatherHour | null = null;
    let bestDistance = Infinity;
    for (const hour of hours) {
        const stamp = new Date(hour.at).getTime();
        if (Number.isNaN(stamp)) continue;
        const distance = Math.abs(stamp - at);
        if (distance < bestDistance) {
            bestDistance = distance;
            best = hour;
        }
    }
    return bestDistance <= 90 * 60 * 1000 ? best : null;
}

export type WindComponent = {
    /** Prędkość wiatru, km/h. */
    speedKmh: number;
    /** Składowa wzdłuż jazdy: dodatnia = w plecy, ujemna = w twarz. */
    alongKmh: number;
    /** Składowa boczna, zawsze dodatnia. */
    crossKmh: number;
    kind: "head" | "tail" | "cross";
    label: string;
};

/**
 * Wiatr przeliczony na to, co rowerzysta czuje.
 *
 * „Wiatr z zachodu, 18 km/h" nic nie znaczy, dopóki nie wiadomo, w którą
 * stronę się jedzie. Znaczy dopiero „czołowy 14 km/h" — i to jest jedyna
 * postać, w jakiej ta informacja trafia na stronę.
 *
 * [windFromDeg] to kierunek METEOROLOGICZNY: skąd wieje. [bearingDeg] to kurs
 * jazdy. Wiatr z tego samego kierunku, w którym jedziemy, jest czołowy.
 */
export function windComponent(
    speedKmh: number | undefined,
    windFromDeg: number | undefined,
    bearingDeg: number | undefined,
): WindComponent | null {
    if (speedKmh === undefined || !Number.isFinite(speedKmh)) return null;
    if (windFromDeg === undefined || !Number.isFinite(windFromDeg)) return null;
    if (bearingDeg === undefined || !Number.isFinite(bearingDeg)) return null;

    // Kąt między kursem a kierunkiem, Z KTÓREGO wieje. Zero = prosto w twarz.
    const relative = (((windFromDeg - bearingDeg) % 360) + 360) % 360;
    const radians = (relative * Math.PI) / 180;
    const alongKmh = -speedKmh * Math.cos(radians);
    const crossKmh = Math.abs(speedKmh * Math.sin(radians));

    // Próg jednego kilometra na godzinę: przy słabszej składowej podłużnej
    // nazwanie wiatru czołowym albo tylnym jest zaokrągleniem, nie faktem.
    let kind: WindComponent["kind"] = "cross";
    if (alongKmh < -1) kind = "head";
    else if (alongKmh > 1) kind = "tail";

    return {
        speedKmh,
        alongKmh,
        crossKmh,
        kind,
        label: kind === "head" ? "CZOŁOWY" : kind === "tail" ? "TYLNY" : "BOCZNY",
    };
}

/** Jedna pozycja w sekcji pogody: punkt na trasie z dobraną godziną. */
export type WeatherForecast = {
    label: WeatherPoint["label"];
    aheadMeters: number;
    /** Chwila, dla której czytamy prognozę. */
    at: Date;
    hour: WeatherHour;
    wind: WindComponent | null;
};

/**
 * Składa sekcję pogody: dla każdego punktu dobiera godzinę po ETA.
 *
 * Bez tempa nie wiemy, kiedy zawodnik tam dotrze, więc zostaje sam punkt
 * „teraz". Prognoza „za 20 km" bez czasu dojazdu byłaby prognozą na godzinę
 * wziętą z sufitu.
 */
export function forecastAlongRoute(
    snapshot: WeatherSnapshot | null,
    now: number,
    paceKmh: number | null,
): WeatherForecast[] {
    if (!snapshot?.points?.length) return [];
    const out: WeatherForecast[] = [];

    for (const point of snapshot.points) {
        const aheadMeters = point.ahead_m ?? 0;
        if (aheadMeters > 0 && (paceKmh === null || paceKmh <= 0)) continue;

        const secondsAway = aheadMeters > 0 ? (aheadMeters / 1000 / paceKmh!) * 3600 : 0;
        const at = new Date(now + secondsAway * 1000);
        const hour = hourAt(point.hours, at.getTime());
        if (!hour) continue;

        out.push({
            label: point.label,
            aheadMeters,
            at,
            hour,
            wind: windComponent(hour.wind_kmh, hour.wind_from_deg, point.bearing_deg),
        });
    }
    return out;
}

export type WeatherAlert = { title: string; detail: string };

/** Od tylu procent uznajemy opady za warte wspomnienia. */
export const RAIN_PROBABILITY_THRESHOLD = 50;

/** Od tylu km/h wiatr czołowy przestaje być tłem, a staje się tematem. */
export const HEADWIND_THRESHOLD_KMH = 18;

/**
 * Jedno zdanie o tym, co przed zawodnikiem — albo nic.
 *
 * Jedno, nie lista: alert, który pojawia się przy każdej zmianie prognozy,
 * przestaje być alertem. Deszcz wygrywa z wiatrem, bo przed deszczem można
 * się schować, a przed wiatrem nie.
 */
export function weatherAlert(forecasts: WeatherForecast[]): WeatherAlert | null {
    const rain = forecasts.find(
        (entry) => (entry.hour.precip_probability ?? 0) >= RAIN_PROBABILITY_THRESHOLD,
    );
    if (rain) {
        const minutes = Math.round((rain.at.getTime() - Date.now()) / 60000);
        const when =
            minutes <= 5
                ? "teraz"
                : minutes < 90
                  ? `za około ${minutes} min`
                  : `około ${formatClock(rain.at)}`;
        return {
            title: minutes <= 5 ? "MOŻLIWY DESZCZ" : `DESZCZ ${when.toUpperCase()}`,
            detail: `Prognoza daje ${Math.round(rain.hour.precip_probability!)}% szans na opady${
                rain.aheadMeters > 0 ? ` po ${Math.round(rain.aheadMeters / 1000)} km` : ""
            }.`,
        };
    }

    const headwind = forecasts.find(
        (entry) => entry.wind?.kind === "head" && -entry.wind.alongKmh >= HEADWIND_THRESHOLD_KMH,
    );
    if (headwind) {
        return {
            title: "SILNY WIATR CZOŁOWY",
            detail: `Około ${Math.round(-headwind.wind!.alongKmh)} km/h prosto w twarz${
                headwind.aheadMeters > 0
                    ? ` na odcinku za ${Math.round(headwind.aheadMeters / 1000)} km`
                    : ""
            }.`,
        };
    }
    return null;
}

/** Jak blisko zachodu jest przyjazd, i czy już po nim. */
export type SunsetInfo = {
    at: Date;
    secondsAway: number;
    /** Czy przewidywany przyjazd wypada po zachodzie. */
    arrivesAfterSunset: boolean;
};

export function sunsetInfo(
    snapshot: WeatherSnapshot | null,
    now: number,
    etaAt: Date | null,
): SunsetInfo | null {
    if (!snapshot?.sunset) return null;
    const at = new Date(snapshot.sunset);
    if (Number.isNaN(at.getTime())) return null;
    return {
        at,
        secondsAway: (at.getTime() - now) / 1000,
        arrivesAfterSunset: etaAt !== null && etaAt.getTime() > at.getTime(),
    };
}

/** Opis kodu pogody WMO po polsku. Nieznany kod nie dostaje opisu. */
export function weatherLabel(code: number | undefined): string {
    if (code === undefined || !Number.isFinite(code)) return "";
    if (code === 0) return "Bezchmurnie";
    if (code <= 2) return "Częściowe zachmurzenie";
    if (code === 3) return "Pochmurno";
    if (code === 45 || code === 48) return "Mgła";
    if (code >= 51 && code <= 57) return "Mżawka";
    if (code >= 61 && code <= 67) return "Deszcz";
    if (code >= 71 && code <= 77) return "Śnieg";
    if (code >= 80 && code <= 82) return "Przelotny deszcz";
    if (code === 85 || code === 86) return "Przelotny śnieg";
    // Skala WMO kończy się na 99. Wyżej to nie „burza", tylko wartość,
    // której nie rozumiemy — i lepiej nie nazywać jej wcale.
    if (code >= 95 && code <= 99) return "Burza";
    return "";
}

function formatClock(value: Date): string {
    return value.toLocaleTimeString("pl-PL", { hour: "2-digit", minute: "2-digit" });
}
