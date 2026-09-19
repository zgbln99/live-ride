import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";

// Wiadomości grupy czyta ten sam token, co migawkę: obserwujący jazdę to
// dokładnie te osoby, które dostały link.
export async function GET(event: RequestEvent) {
    try {
        const response = await event.locals.pb.send(
            `/live/${encodeURIComponent(event.params.token!)}/messages`,
            { method: "GET", fetch: event.fetch },
        );
        return json(response, { headers: { "cache-control": "no-store" } });
    } catch (e: any) {
        return handleError(e);
    }
}
