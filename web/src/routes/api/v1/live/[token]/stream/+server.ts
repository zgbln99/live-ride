import { env } from "$env/dynamic/public";
import type { RequestEvent } from "@sveltejs/kit";

/**
 * Strumień zmian publicznego LIVE.
 *
 * Nie da się go przepuścić przez klienta PocketBase, tak jak reszty tras:
 * `pb.send` czeka na CAŁĄ odpowiedź, a ta z założenia nigdy się nie kończy.
 * Dlatego tutaj jest zwykły `fetch` i przekazanie strumienia dalej bez
 * buforowania — razem z nagłówkami, które każą pośrednikom go nie zbierać.
 *
 * Przerwane połączenie widza przerywa też to w górę: bez `signal` serwer
 * trzymałby otwarte gniazdo do PocketBase długo po zamknięciu zakładki.
 */
export async function GET(event: RequestEvent) {
    const origin = env.PUBLIC_POCKETBASE_URL;
    const target = `${origin}/live/${encodeURIComponent(event.params.token!)}/stream`;

    let upstream: Response;
    try {
        upstream = await fetch(target, {
            headers: { accept: "text/event-stream" },
            signal: event.request.signal,
        });
    } catch {
        // Brak strumienia nie jest awarią strony: viewer wraca do odpytywania.
        return new Response(null, { status: 503 });
    }

    if (!upstream.ok || !upstream.body) {
        return new Response(null, { status: upstream.status === 200 ? 503 : upstream.status });
    }

    return new Response(upstream.body, {
        headers: {
            "content-type": "text/event-stream",
            "cache-control": "no-store, max-age=0",
            connection: "keep-alive",
            "x-accel-buffering": "no",
        },
    });
}
