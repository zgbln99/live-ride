import { error } from "@sveltejs/kit";
import { env } from "$env/dynamic/private";
import type { Snapshot } from "$lib/live/live_viewer";
import type { PageServerLoad } from "./$types";

/**
 * Wczytanie publicznej strony LIVE po stronie serwera.
 *
 * Dwa powody, dla których to nie może być tylko `fetch` w przeglądarce:
 *
 *  1. Podgląd linku. WhatsApp, Messenger i iMessage czytają gotowy HTML i nie
 *     uruchamiają JavaScriptu — bez metadanych z serwera wklejony link jest
 *     gołym adresem.
 *  2. Pierwsza klatka. Znajomy otwiera link w ruchu, często na słabym LTE;
 *     tytuł i stan mają być w pierwszej odpowiedzi, a nie sekundę później.
 *
 * Strona jest dostępna BEZ konta i bez logowania — ten `load` celowo nie
 * dotyka `locals.user` ani niczego, co wymaga sesji.
 */
export const load: PageServerLoad = async ({ params, fetch, setHeaders, url }) => {
    const token = params.token;

    let snapshot: Snapshot | null = null;
    try {
        const response = await fetch(`/api/v1/live/${encodeURIComponent(token)}`);
        if (response.status === 404) error(404, "Nie znaleziono tego przejazdu");
        if (response.ok) snapshot = (await response.json()) as Snapshot;
    } catch (e: any) {
        // Serwer migawek może być chwilowo niedostępny. Strona i tak potrafi
        // dociągnąć dane po stronie przeglądarki, więc nie zamieniamy tego na
        // błąd 500 — byłby gorszy od mapy, która za chwilę sama się odświeży.
        if (e?.status === 404) throw e;
        snapshot = null;
    }

    const indexable = snapshot?.visibility === "public" && snapshot?.status === "active";
    setHeaders({
        // Migawka jest nieświeża sekundę później.
        "cache-control": "no-store",
        // Link „z linku" nie ma prawa trafić do wyszukiwarki.
        "x-robots-tag": indexable ? "all" : "noindex, nofollow",
    });

    const origin = env.ORIGIN || url.origin;
    const riderName = snapshot?.riders?.[0]?.display_name?.trim() || "";
    const riders = snapshot?.riders?.length ?? 0;

    return {
        token,
        snapshot,
        indexable,
        meta: buildMeta({ snapshot, riderName, riders, origin, token }),
    };
};

/**
 * „Marek" → „Marka".
 *
 * Dopełniacz dla polskich imion na spółgłoskę i na -a. Reszty nie ruszamy:
 * źle odmienione imię w podglądzie linku jest gorsze niż nieodmienione.
 */
function possessive(name: string): string {
    if (!name || name.includes(" ")) return name;
    if (/[aA]$/.test(name)) return `${name.slice(0, -1)}y`;
    if (/[bcdfghjklmnprstwzBCDFGHJKLMNPRSTWZ]$/.test(name)) return `${name}a`;
    return name;
}

/**
 * Dystans i przewyższenie z podsumowania — albo nic.
 *
 * Bez zapisanych liczb opis nie zmyśla: przejazd bez podsumowania dostaje
 * zdanie ogólne zamiast wymyślonych kilometrów.
 */
function summaryShape(snapshot: Snapshot): string {
    const rider = snapshot.summary?.riders?.[0];
    const parts: string[] = [];
    if (rider?.distance_m !== undefined && rider.distance_m > 0) {
        parts.push(`${(rider.distance_m / 1000).toFixed(1).replace(".", ",")} km`);
    }
    if (rider?.elevation_gain_m !== undefined && rider.elevation_gain_m > 0) {
        parts.push(`${Math.round(rider.elevation_gain_m)} m ↑`);
    }
    return parts.join(" · ");
}

function buildMeta(input: {
    snapshot: Snapshot | null;
    riderName: string;
    riders: number;
    origin: string;
    token: string;
}) {
    const { snapshot, riderName, riders, origin, token } = input;

    // Nazwa zawodnika, a nie „Marek" wpisany na sztywno. Gdy jej nie znamy
    // (np. link wygasł), zdanie ma nadal brzmieć sensownie.
    const who = riderName || "Ktoś";
    const group = riders > 1 ? ` (${riders} zawodników)` : "";

    let title = "Live Ride";
    let description = "Śledź przejazd na żywo w Live Ride.";

    switch (snapshot?.status) {
        case "active":
            title = `Live Ride · ${who}`;
            description = `${who} jedzie teraz na rowerze${group} — śledź przejazd na żywo. Bez aplikacji i bez zakładania konta.`;
            break;
        case "ended": {
            title = `Live Ride · przejazd ${possessive(who)}`;
            // Liczby w opisie, bo to one zostają po jeździe. Nigdy miejsce:
            // miniatura podglądu trafia dalej niż sam link.
            const shape = summaryShape(snapshot);
            description = shape || "Zobacz podsumowanie przejazdu: dystans, czas i przewyższenie.";
            break;
        }
        case "expired":
            title = "Link wygasł · Live Ride";
            description = "Ten link do śledzenia przejazdu na żywo już nie działa.";
            break;
        case "disabled":
            title = "Udostępnianie wyłączone · Live Ride";
            description = "Zawodnik wyłączył udostępnianie tego przejazdu.";
            break;
    }

    return {
        title,
        description,
        // Obrazek jest STAŁY i nie pokazuje pozycji: miniatura podglądu trafia
        // dalej niż sam link, a lokalizacja zawodnika nie ma prawa wyciec
        // przez metadane, których nikt nie kontroluje.
        image: `${origin}/imgs/live-ride/og-live.png`,
        url: `${origin}/live/${token}`,
    };
}
