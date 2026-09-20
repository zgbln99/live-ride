import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";

// Diagnostyka LIVE dla właściciela jazdy. Wymaga zalogowania — serwer
// dodatkowo sprawdza, czy pytający jest właścicielem sesji.
export async function GET(event: RequestEvent) {
    try {
        const response = await event.locals.pb.send(
            `/live-rides/${encodeURIComponent(event.params.id!)}/diagnostics`,
            { method: "GET", fetch: event.fetch },
        );
        return json(response, { headers: { "cache-control": "no-store" } });
    } catch (e: any) {
        return handleError(e);
    }
}
