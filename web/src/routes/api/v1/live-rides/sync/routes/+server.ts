import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";

export async function POST(event: RequestEvent) {
    try {
        const body = await event.request.json();
        const response = await event.locals.pb.send("/live-rides/sync/routes", {
            method: "POST",
            body,
            fetch: event.fetch,
        });
        return json(response);
    } catch (e: any) {
        return handleError(e);
    }
}

// Świeżo zainstalowany telefon dociąga trasy zmienione od ostatniego razu.
export async function GET(event: RequestEvent) {
    try {
        const since = event.url.searchParams.get("since");
        const query = since ? `?since=${encodeURIComponent(since)}` : "";
        const response = await event.locals.pb.send(
            `/live-rides/sync/routes${query}`,
            { method: "GET", fetch: event.fetch },
        );
        return json(response, { headers: { "cache-control": "no-store" } });
    } catch (e: any) {
        return handleError(e);
    }
}
