import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";

// Oś czasu przejazdu. Osobno od migawki, bo zdarzeń przybywa kilkanaście na
// godzinę, a migawka chodzi co kilka sekund.
export async function GET(event: RequestEvent) {
    try {
        const response = await event.locals.pb.send(
            `/live/${encodeURIComponent(event.params.token!)}/events`,
            { method: "GET", fetch: event.fetch },
        );
        return json(response, { headers: { "cache-control": "no-store" } });
    } catch (e: any) {
        return handleError(e);
    }
}
