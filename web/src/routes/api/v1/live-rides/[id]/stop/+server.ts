import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";

export async function POST(event: RequestEvent) {
    try {
        const response = await event.locals.pb.send(
            `/live-rides/${encodeURIComponent(event.params.id!)}/stop`,
            { method: "POST", fetch: event.fetch },
        );
        return json(response);
    } catch (e: any) {
        return handleError(e);
    }
}
