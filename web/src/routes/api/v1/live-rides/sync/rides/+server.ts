import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";

// Wysyłka zakończonych przejazdów z telefonu.
//
// Aplikacja rozmawia wyłącznie z tym originem, więc każda trasa Go musi mieć
// tu swoją bliźniaczkę. Brak tego pliku był powodem, dla którego ekran
// „Offline i synchronizacja" pokazywał 404 mimo działającego backendu.
export async function POST(event: RequestEvent) {
    try {
        const body = await event.request.json();
        const response = await event.locals.pb.send("/live-rides/sync/rides", {
            method: "POST",
            body,
            fetch: event.fetch,
        });
        return json(response);
    } catch (e: any) {
        return handleError(e);
    }
}
