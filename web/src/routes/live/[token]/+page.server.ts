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
            title = `${who} jedzie teraz 🚴 · Live Ride`;
            description = `Śledź przejazd na żywo${group}: mapa, dystans i tempo w czasie rzeczywistym. Bez aplikacji i bez zakładania konta.`;
            break;
        case "ended":
            title = `${who} — przejazd zakończony · Live Ride`;
            description = "Zobacz podsumowanie przejazdu: mapa, dystans, czas i przewyższenie.";
            break;
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
