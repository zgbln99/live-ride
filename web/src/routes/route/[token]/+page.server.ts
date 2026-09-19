import { error } from "@sveltejs/kit";
import { env } from "$env/dynamic/private";
import type { PublicRoute } from "$lib/live/public_route";
import type { PageServerLoad } from "./$types";

/**
 * Publiczna strona trasy.
 *
 * Druga z dwóch stron, które znajomy otwiera z linku — ta pokazuje plan
 * PRZED jazdą, nie przejazd w trakcie. Podgląd nie wymaga konta; konta
 * wymaga dopiero skopiowanie trasy do własnej biblioteki.
 */
export const load: PageServerLoad = async ({ params, fetch, setHeaders, url, locals }) => {
    const token = params.token;

    const response = await fetch(`/api/v1/live-routes/${encodeURIComponent(token)}`);
    if (!response.ok) error(404, "Nie znaleziono tej trasy");
    const route = (await response.json()) as PublicRoute;

    const indexable = route.privacy === "public";
    setHeaders({
        "cache-control": indexable ? "public, max-age=300" : "no-store",
        // Trasa „tylko z linku" nie ma prawa trafić do wyszukiwarki.
        "x-robots-tag": indexable ? "all" : "noindex, nofollow",
    });

    const origin = env.ORIGIN || url.origin;
    const kilometres = route.distance_m ? (route.distance_m / 1000).toFixed(1).replace(".", ",") : null;
    const ascent = route.ascent_m ? `${Math.round(route.ascent_m)} m` : null;
    const facts = [kilometres && `${kilometres} km`, ascent && `${ascent} w górę`]
        .filter(Boolean)
        .join(" · ");

    return {
        token,
        route,
        indexable,
        // Podgląd nie wymaga konta; konta wymaga dopiero zapisanie trasy u
        // siebie. Dlatego strona musi wiedzieć, czy pokazać przycisk, czy
        // odesłać do logowania — a nie obiecywać akcji, która skończy się 401.
        signedIn: Boolean(locals.user?.id),
        meta: {
            title: `${route.name || "Trasa rowerowa"} · Live Ride`,
            description: [facts, route.description?.trim(), "Pobierz GPX albo otwórz w Live Ride."]
                .filter(Boolean)
                .join(" — ")
                .slice(0, 300),
            image: `${origin}/imgs/live-ride/og-route.png`,
            url: `${origin}/route/${token}`,
        },
        // Deep link do aplikacji. Gdy jej nie ma, nic się nie dzieje i
        // znajomy zostaje na zwykłej stronie WWW — dlatego przycisk nigdy nie
        // jest jedyną drogą do trasy.
        deepLink: `liveride://route/${token}`,
    };
};
