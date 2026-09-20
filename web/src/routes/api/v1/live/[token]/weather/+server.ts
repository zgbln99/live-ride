import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";

// Prognoza wzdłuż pozostałej części trasy. Pyta o nią serwer, nie przeglądarka
// widza: jedna jazda potrafi mieć kilkunastu obserwujących, a współrzędne
// zawodnika nie mają powodu wychodzić z każdego z ich telefonów osobno.
export async function GET(event: RequestEvent) {
    try {
        const response = await event.locals.pb.send(
            `/live/${encodeURIComponent(event.params.token!)}/weather`,
            { method: "GET", fetch: event.fetch },
        );
        return json(response, { headers: { "cache-control": "no-store" } });
    } catch (e: any) {
        return handleError(e);
    }
}
