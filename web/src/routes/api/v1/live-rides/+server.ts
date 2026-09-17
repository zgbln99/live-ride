import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";

export async function POST(event: RequestEvent) {
    try {
        const body = await event.request.json();
        const response = await event.locals.pb.send("/live-rides", {
            method: "POST",
            body,
            fetch: event.fetch,
        });
        return json(response, { status: 201 });
    } catch (e: any) {
        return handleError(e);
    }
}
