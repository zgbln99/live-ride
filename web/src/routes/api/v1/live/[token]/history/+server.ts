import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";

// Przebieg jazdy w czasie: cofnięcie się w trwającej transmisji i odtworzenie
// zakończonej korzystają z tego samego adresu, bo to ten sam problem.
export async function GET(event: RequestEvent) {
    try {
        const query = event.url.search;
        const response = await event.locals.pb.send(
            `/live/${encodeURIComponent(event.params.token!)}/history${query}`,
            { method: "GET", fetch: event.fetch },
        );
        return json(response, { headers: { "cache-control": "no-store" } });
    } catch (e: any) {
        return handleError(e);
    }
}
