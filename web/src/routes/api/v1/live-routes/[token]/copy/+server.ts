import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";

// Kopiowanie do własnej biblioteki — jedyna akcja na publicznej stronie
// trasy, która wymaga konta.
export async function POST(event: RequestEvent) {
    try {
        const response = await event.locals.pb.send(
            `/live-routes/${encodeURIComponent(event.params.token!)}/copy`,
            { method: "POST", fetch: event.fetch },
        );
        return json(response);
    } catch (e: any) {
        return handleError(e);
    }
}
