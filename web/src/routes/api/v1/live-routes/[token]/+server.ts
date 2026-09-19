import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";

// Publiczna trasa spod linku — bez konta i bez logowania.
export async function GET(event: RequestEvent) {
    try {
        const response = await event.locals.pb.send(
            `/live-routes/${encodeURIComponent(event.params.token!)}`,
            { method: "GET", fetch: event.fetch },
        );
        return json(response, { headers: { "cache-control": "private, max-age=60" } });
    } catch (e: any) {
        return handleError(e);
    }
}
