import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";

// Przejechany ślad. Bez `since` pełny (rozrzedzony), z `since` tylko to, co
// przybyło — inaczej każda aktualizacja ciągnęłaby całą historię przejazdu.
export async function GET(event: RequestEvent) {
    try {
        const since = event.url.searchParams.get("since");
        const query = since ? `?since=${encodeURIComponent(since)}` : "";
        const response = await event.locals.pb.send(
            `/live/${encodeURIComponent(event.params.token!)}/track${query}`,
            { method: "GET", fetch: event.fetch },
        );
        return json(response, { headers: { "cache-control": "no-store" } });
    } catch (e: any) {
        return handleError(e);
    }
}
