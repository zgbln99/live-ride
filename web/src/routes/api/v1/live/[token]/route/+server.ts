import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";

export async function GET(event: RequestEvent) {
    try {
        const response = await event.locals.pb.send(
            `/live/${encodeURIComponent(event.params.token!)}/route`,
            { method: "GET", fetch: event.fetch },
        );
        return json(response, {
            headers: { "cache-control": "private, max-age=30" },
        });
    } catch (e: any) {
        return handleError(e);
    }
}
