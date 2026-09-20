import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";

// Doczepia aktywną trasę do trwającej sesji LIVE.
//
// Przyjmuje całą trasę, a nie tylko jej identyfikator: trasa świeżo z
// kreatora, z pliku GPX albo skopiowana z cudzego linku nie istnieje jeszcze
// na serwerze, a publiczna strona ma ją pokazać i tak.
export async function POST(event: RequestEvent) {
    try {
        const response = await event.locals.pb.send(
            `/live-rides/${encodeURIComponent(event.params.id!)}/route`,
            { method: "POST", body: await event.request.json(), fetch: event.fetch },
        );
        return json(response);
    } catch (e: any) {
        return handleError(e);
    }
}
