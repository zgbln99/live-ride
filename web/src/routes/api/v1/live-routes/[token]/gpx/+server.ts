import { handleError } from "$lib/util/api_util";
import { type RequestEvent } from "@sveltejs/kit";
import { env as envPub } from "$env/dynamic/public";

/**
 * Pobranie trasy jako GPX.
 *
 * Nie idzie przez `locals.pb.send`, bo ten zwraca sparsowany JSON — tutaj
 * potrzebny jest strumień pliku razem z nagłówkiem `Content-Disposition`,
 * żeby przeglądarka zapisała plik zamiast go wyświetlić.
 */
export async function GET(event: RequestEvent) {
    try {
        const upstream = await event.fetch(
            `${envPub.PUBLIC_POCKETBASE_URL}/live-routes/${encodeURIComponent(event.params.token!)}/gpx`,
        );
        if (!upstream.ok) {
            return new Response(JSON.stringify({ message: "route_not_found" }), {
                status: upstream.status,
                headers: { "content-type": "application/json" },
            });
        }
        return new Response(upstream.body, {
            status: 200,
            headers: {
                "content-type": upstream.headers.get("content-type") ?? "application/gpx+xml",
                "content-disposition":
                    upstream.headers.get("content-disposition") ?? 'attachment; filename="trasa.gpx"',
                "cache-control": "private, max-age=300",
            },
        });
    } catch (e: any) {
        return handleError(e);
    }
}
