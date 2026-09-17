import { json, type RequestEvent } from '@sveltejs/kit';

const cachedStyles = new Map<string, unknown>();

export async function GET(event: RequestEvent) {
    const theme = event.url.searchParams.get('theme') === 'dark' ? 'dark' : 'liberty';
    const cached = cachedStyles.get(theme);
    if (cached) {
        return json(cached, { headers: { 'cache-control': 'public, max-age=3600' } });
    }

    const upstream = await fetch(`https://tiles.openfreemap.org/styles/${theme}`, {
        headers: {
            accept: 'application/json',
            'user-agent': 'LiveRide/0.1 MapLibre',
        },
    });

    if (!upstream.ok) {
        return json(
            { message: 'map_style_unavailable', status: upstream.status },
            { status: 502 },
        );
    }

    const style = await upstream.json();
    cachedStyles.set(theme, style);
    return json(style, { headers: { 'cache-control': 'public, max-age=3600' } });
}
