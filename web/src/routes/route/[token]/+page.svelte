<script lang="ts">
    import { onMount } from "svelte";
    import * as M from "maplibre-gl";
    import "maplibre-gl/dist/maplibre-gl.css";
    import { ensureMapLibreWorker } from "$lib/util/maplibre_worker";
    import { decodePolyline } from "$lib/util/polyline_util";
    import {
        climbCategory,
        routeShape,
        surfaceLabel,
        type PublicRoute,
    } from "$lib/live/public_route";
    import {
        cumulativeDistances,
        distance as fmtDistance,
        durationCoarse,
        num,
        type LngLat,
    } from "$lib/live/live_viewer";
    import type { PageData } from "./$types";

    let { data }: { data: PageData } = $props();

    const route = $derived<PublicRoute>(data.route);

    let mapError = $state("");
    let copied = $state("");
    let hoverIndex = $state<number | null>(null);
    let map: M.Map | null = null;

    const coordinates = $derived.by<LngLat[]>(() =>
        route.polyline ? (decodePolyline(route.polyline, route.precision ?? 6) as LngLat[]) : [],
    );
    const cumulative = $derived(cumulativeDistances(coordinates));
    const lengthMeters = $derived(
        route.distance_m || cumulative[cumulative.length - 1] || 0,
    );
    const shape = $derived(routeShape(coordinates));
    const climbs = $derived(route.climbs ?? []);
    const surfaces = $derived((route.surfaces ?? []).filter((entry) => entry.share > 0.02));

    /**
     * Szacowany czas przejazdu.
     *
     * Jawnie oparty na 22 km/h plus doliczone podjazdy — i tak napisany na
     * stronie, bo „3:14" bez powiedzenia, skąd się wzięło, wygląda na pomiar.
     */
    const ASSUMED_KMH = 22;
    const estimatedSeconds = $derived.by(() => {
        if (!lengthMeters) return null;
        const flat = (lengthMeters / 1000 / ASSUMED_KMH) * 3600;
        // Każde 100 m w górę to mniej więcej dodatkowe 6 minut.
        const climbing = ((route.ascent_m ?? 0) / 100) * 360;
        return flat + climbing;
    });

    const profile = $derived.by(() => {
        const points = route.elevation_profile ?? [];
        if (points.length < 2) return null;
        const width = 1000;
        const height = 220;
        const total = points[points.length - 1].d || 1;
        let min = Infinity;
        let max = -Infinity;
        for (const point of points) {
            if (point.e < min) min = point.e;
            if (point.e > max) max = point.e;
        }
        const span = Math.max(20, max - min);
        const x = (d: number) => (d / total) * width;
        const y = (e: number) => height - ((e - min) / span) * (height - 16) - 8;
        const line = points
            .map((point, i) => `${i ? "L" : "M"}${x(point.d).toFixed(1)} ${y(point.e).toFixed(1)}`)
            .join(" ");
        return {
            points,
            width,
            height,
            min,
            max,
            total,
            line,
            area: `${line} L${width} ${height} L0 ${height} Z`,
            x,
            y,
            // Podjazdy jako pasy pod wykresem — od razu widać, gdzie boli.
            bands: climbs.map((climb) => ({
                x: x(climb.start_m),
                width: Math.max(2, x(climb.start_m + climb.length_m) - x(climb.start_m)),
                gradient: climb.avg_gradient,
            })),
        };
    });

    const hovered = $derived.by(() => {
        if (hoverIndex === null || !profile) return null;
        const point = profile.points[hoverIndex];
        return point ? { ...point } : null;
    });

    function onProfileMove(event: PointerEvent) {
        if (!profile) return;
        const target = event.currentTarget as SVGSVGElement;
        const box = target.getBoundingClientRect();
        const ratio = Math.min(1, Math.max(0, (event.clientX - box.left) / box.width));
        const along = ratio * profile.total;
        let best = 0;
        for (let i = 1; i < profile.points.length; i++) {
            if (Math.abs(profile.points[i].d - along) < Math.abs(profile.points[best].d - along)) {
                best = i;
            }
        }
        hoverIndex = best;
    }

    let copying = $state(false);

    /**
     * Kopiuje trasę do biblioteki zalogowanego widza.
     *
     * Jedyna akcja na tej stronie, która wymaga konta — i jedyna, która coś
     * zapisuje. Serwer nadaje kopii własny identyfikator, więc oryginał
     * zostaje nietknięty.
     */
    async function copyRoute() {
        copying = true;
        try {
            const response = await fetch(`/api/v1/live-routes/${data.token}/copy`, {
                method: "POST",
            });
            copied = response.ok
                ? "Trasa jest już w Twojej bibliotece"
                : "Nie udało się skopiować trasy";
        } catch {
            copied = "Nie udało się skopiować trasy";
        } finally {
            copying = false;
            setTimeout(() => (copied = ""), 3200);
        }
    }

    async function copyLink() {
        try {
            await navigator.clipboard.writeText(data.meta.url);
            copied = "Link skopiowany";
        } catch {
            copied = "Skopiuj link z paska adresu";
        }
        setTimeout(() => (copied = ""), 2600);
    }

    async function share() {
        const payload = {
            title: route.name || "Trasa rowerowa",
            text: `${route.name || "Trasa"} w Live Ride`,
            url: data.meta.url,
        };
        if (navigator.share) {
            try {
                await navigator.share(payload);
                return;
            } catch {
                // Anulowane okno udostępniania nie jest błędem.
            }
        }
        await copyLink();
    }

    onMount(() => {
        document.documentElement.lang = "pl";
        let cancelled = false;

        (async () => {
            try {
                const response = await fetch("/api/v1/map/style?theme=liberty", {
                    cache: "force-cache",
                });
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                if (cancelled) return;
                ensureMapLibreWorker();
                map = new M.Map({
                    container: "route-map",
                    style: (await response.json()) as M.StyleSpecification,
                    center: coordinates[0] ?? [19.4, 52.1],
                    zoom: 10,
                    attributionControl: false,
                });
                map.addControl(new M.NavigationControl({ showCompass: false }), "bottom-left");
                map.addControl(new M.AttributionControl({ compact: true }), "bottom-right");
                map.on("load", () => drawRoute());
                map.on("error", (event) => console.warn("Live Ride map", event.error));
            } catch (e) {
                mapError = e instanceof Error ? e.message : "nie udało się uruchomić mapy";
            }
        })();

        return () => {
            cancelled = true;
            map?.remove();
            map = null;
        };
    });

    function drawRoute() {
        if (!map || coordinates.length < 2) return;
        map.addSource("route", {
            type: "geojson",
            data: {
                type: "Feature",
                properties: {},
                geometry: { type: "LineString", coordinates },
            },
        });
        map.addLayer({
            id: "route-case",
            type: "line",
            source: "route",
            layout: { "line-cap": "round", "line-join": "round" },
            paint: { "line-color": "#04121c", "line-width": 10, "line-opacity": 0.5 },
        });
        map.addLayer({
            id: "route-line",
            type: "line",
            source: "route",
            layout: { "line-cap": "round", "line-join": "round" },
            paint: { "line-color": "#00bfd8", "line-width": 5 },
        });

        for (const [index, point] of [coordinates[0], coordinates[coordinates.length - 1]].entries()) {
            const element = document.createElement("div");
            element.className = index === 0 ? "rt-pin rt-start" : "rt-pin rt-finish";
            element.textContent = index === 0 ? "START" : "META";
            new M.Marker({ element, anchor: "bottom" }).setLngLat(point).addTo(map);
        }

        const bounds = new M.LngLatBounds();
        for (const point of coordinates) bounds.extend(point);
        // Na telefonie dolna krawędź mapy chowa się pod kartą z danymi, więc
        // dopasowanie musi zostawić tam więcej miejsca niż po bokach.
        const narrow = window.innerWidth <= 900;
        map.fitBounds(bounds, {
            padding: narrow
                ? { top: 74, right: 38, bottom: 62, left: 38 }
                : { top: 64, right: 56, bottom: 56, left: 56 },
            maxZoom: 14,
            duration: 0,
        });
    }

    // Znacznik na mapie podąża za kursorem na profilu wysokości.
    let hoverMarker: M.Marker | null = null;
    $effect(() => {
        if (!map || !profile) return;
        if (hoverIndex === null) {
            hoverMarker?.remove();
            hoverMarker = null;
            return;
        }
        const along = profile.points[hoverIndex]?.d ?? 0;
        let index = 0;
        while (index < cumulative.length - 1 && cumulative[index] < along) index++;
        const point = coordinates[index];
        if (!point) return;
        if (!hoverMarker) {
            const element = document.createElement("div");
            element.className = "rt-hover";
            hoverMarker = new M.Marker({ element, anchor: "center" }).setLngLat(point).addTo(map);
        } else {
            hoverMarker.setLngLat(point);
        }
    });
</script>

<svelte:head>
    <title>{data.meta.title}</title>
    <meta name="description" content={data.meta.description} />
    <meta name="theme-color" content="#07101A" />
    {#if !data.indexable}
        <meta name="robots" content="noindex, nofollow" />
    {/if}
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="Live Ride" />
    <meta property="og:title" content={data.meta.title} />
    <meta property="og:description" content={data.meta.description} />
    <meta property="og:image" content={data.meta.image} />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta property="og:url" content={data.meta.url} />
    <meta property="og:locale" content="pl_PL" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content={data.meta.title} />
    <meta name="twitter:description" content={data.meta.description} />
    <meta name="twitter:image" content={data.meta.image} />
    <link
        rel="icon"
        href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 64 64%22><rect width=%2264%22 height=%2264%22 rx=%2212%22 fill=%22%2307101a%22/><path d=%22M10 52 33 9l9 18H23z%22 fill=%22white%22/><path d=%22M30 56 58 12 49 56z%22 fill=%22%2300bfd8%22/></svg>"
    />
</svelte:head>

<main class="page">
    <div class="stage">
        <div id="route-map" class="map"></div>
        <header class="topbar">
            <div class="brand">
                <svg class="mark" viewBox="0 0 64 64" aria-hidden="true">
                    <path d="M10 52 33 9l9 18H23z" fill="#ffffff" />
                    <path d="M30 56 58 12 49 56z" fill="#00bfd8" />
                </svg>
                <span>LIVE RIDE</span>
            </div>
            {#if shape}<div class="chip">{shape}</div>{/if}
        </header>
        {#if mapError}
            <p class="warning">Mapa: {mapError}</p>
        {/if}
    </div>

    <section class="body">
        <div class="head">
            <h1>{route.name || "Trasa rowerowa"}</h1>
            <p class="byline">
                {#if route.author}zaplanował {route.author}{:else}trasa z Live Ride{/if}
                {#if route.copy_count}· skopiowana {route.copy_count}×{/if}
            </p>
            {#if route.description?.trim()}
                <p class="description">{route.description}</p>
            {/if}
            {#if route.tags?.length}
                <div class="tags">
                    {#each route.tags as tag (tag)}<span>{tag}</span>{/each}
                </div>
            {/if}
        </div>

        <div class="grid big">
            <div><span>DYSTANS</span><b>{fmtDistance(lengthMeters)}</b></div>
            <div><span>W GÓRĘ</span><b>{route.ascent_m ? `${Math.round(route.ascent_m)} m` : "—"}</b></div>
            <div><span>W DÓŁ</span><b>{route.descent_m ? `${Math.round(route.descent_m)} m` : "—"}</b></div>
            <div><span>SZACOWANY CZAS</span><b>{durationCoarse(estimatedSeconds ?? undefined)}</b></div>
        </div>
        <p class="assumption">
            Czas policzony dla {ASSUMED_KMH} km/h na płaskim, z doliczonymi podjazdami. To
            oszacowanie, nie pomiar.
        </p>

        <div class="actions">
            <a class="primary" href={`/api/v1/live-routes/${data.token}/gpx`} download>
                <svg viewBox="0 0 24 24" aria-hidden="true"
                    ><path fill="currentColor" d="M12 3v10.6l3.3-3.3 1.4 1.4-5.7 5.7-5.7-5.7 1.4-1.4 3.3 3.3V3zM5 19h14v2H5z" /></svg
                >
                Pobierz GPX
            </a>
            <a class="secondary" href={data.deepLink}>
                <svg viewBox="0 0 24 24" aria-hidden="true"
                    ><path fill="currentColor" d="M14 3h7v7h-2V6.4l-8.3 8.3-1.4-1.4L17.6 5H14zM5 5h5v2H5v12h12v-5h2v7H3V5z" /></svg
                >
                Otwórz w Live Ride
            </a>
            <button class="secondary" onclick={share}>
                <svg viewBox="0 0 24 24" aria-hidden="true"
                    ><path
                        fill="currentColor"
                        d="M18 16a3 3 0 0 0-2.2 1l-6-3.2a3 3 0 0 0 0-1.6l6-3.2a3 3 0 1 0-1-2 3 3 0 0 0 .1.7L8.8 11A3 3 0 1 0 6 15a3 3 0 0 0 2.8-1.9l6 3.2a3 3 0 1 0 3.2-2.3z"
                    /></svg
                >
                Udostępnij
            </button>
            {#if data.signedIn}
                <button class="ghost" onclick={copyRoute} disabled={copying}>
                    {copying ? "Kopiuję…" : "Skopiuj do swojej biblioteki"}
                </button>
            {:else}
                <a class="ghost" href="/login?r={encodeURIComponent(`/route/${data.token}`)}">
                    Zaloguj się, aby skopiować do swojej biblioteki
                </a>
            {/if}
        </div>
        {#if copied}<p class="copied" role="status">{copied}</p>{/if}
        <p class="note">
            Podgląd trasy nie wymaga konta. Konta wymaga dopiero zapisanie jej u siebie —
            „Otwórz w Live Ride" zadziała, jeżeli masz aplikację na tym telefonie.
        </p>

        {#if profile}
            <section class="panel">
                <div class="panel-head">
                    <h2>PROFIL WYSOKOŚCI</h2>
                    <small>
                        {#if hovered}
                            {fmtDistance(hovered.d)} · {Math.round(hovered.e)} m n.p.m.
                        {:else}
                            {Math.round(profile.min)}–{Math.round(profile.max)} m n.p.m.
                        {/if}
                    </small>
                </div>
                <svg
                    class="profile"
                    viewBox={`0 0 ${profile.width} ${profile.height}`}
                    preserveAspectRatio="none"
                    role="img"
                    aria-label="Profil wysokości trasy"
                    onpointermove={onProfileMove}
                    onpointerleave={() => (hoverIndex = null)}
                >
                    {#each profile.bands as band}
                        <rect
                            class="band"
                            x={band.x}
                            y="0"
                            width={band.width}
                            height={profile.height}
                            opacity={Math.min(0.17, 0.05 + band.gradient / 90)}
                        />
                    {/each}
                    <path class="area" d={profile.area} />
                    <path class="line" d={profile.line} />
                    {#if hovered}
                        <line class="cursor" x1={profile.x(hovered.d)} y1="0" x2={profile.x(hovered.d)} y2={profile.height} />
                        <circle class="dot" cx={profile.x(hovered.d)} cy={profile.y(hovered.e)} r="6" />
                    {/if}
                </svg>
            </section>
        {/if}

        {#if climbs.length}
            <section class="panel">
                <div class="panel-head">
                    <h2>PODJAZDY</h2>
                    <small>{climbs.length}</small>
                </div>
                <ul class="climbs">
                    {#each climbs as climb (climb.start_m)}
                        <li>
                            <div class="cat">{climbCategory(climb)}</div>
                            <div class="where">
                                <strong>od {fmtDistance(climb.start_m)}</strong>
                                <span>{fmtDistance(climb.length_m)} · {Math.round(climb.gain_m)} m ↑</span>
                            </div>
                            <b class="gradient">{num(climb.avg_gradient, 1)} %</b>
                        </li>
                    {/each}
                </ul>
            </section>
        {/if}

        {#if surfaces.length}
            <section class="panel">
                <div class="panel-head"><h2>NAWIERZCHNIA</h2></div>
                <div class="surfaces">
                    {#each surfaces as surface (surface.kind)}
                        <div class="surface">
                            <div class="surface-bar"><i style={`width:${Math.round(surface.share * 100)}%`}></i></div>
                            <span>{surfaceLabel(surface.kind)}</span>
                            <b>{Math.round(surface.share * 100)}%</b>
                        </div>
                    {/each}
                </div>
            </section>
        {/if}

        <p class="foot">Live Ride · trasy, nawigacja i jazda na żywo</p>
    </section>
</main>

<style>
    :global(html),
    :global(body) {
        margin: 0;
        background: #07101a;
    }
    :global(body) {
        font-family:
            Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    :global(.rt-pin) {
        padding: 4px 8px;
        border-radius: 6px;
        font-size: 9px;
        font-weight: 900;
        letter-spacing: 0.1em;
        color: #05121a;
        background: #ffffff;
        box-shadow: 0 4px 12px rgb(0 0 0 / 0.42);
        transform: translateY(6px);
    }
    :global(.rt-finish) {
        background: #31d07c;
    }
    :global(.rt-hover) {
        width: 16px;
        height: 16px;
        border-radius: 50%;
        border: 3px solid #ffffff;
        background: #00bfd8;
        box-shadow: 0 2px 8px rgb(0 0 0 / 0.5);
    }

    .page {
        color: #f3f8fc;
        background: #07101a;
        min-height: 100dvh;
    }
    .stage {
        position: relative;
        height: 46dvh;
        min-height: 260px;
    }
    .map {
        position: absolute;
        inset: 0;
        background: #dde6ed;
    }
    .topbar {
        position: absolute;
        inset: 0 0 auto 0;
        z-index: 3;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding: max(14px, env(safe-area-inset-top)) 16px 18px;
        pointer-events: none;
        background: linear-gradient(180deg, rgb(7 16 26 / 0.82), transparent);
    }
    .brand {
        display: flex;
        align-items: center;
        gap: 10px;
    }
    .brand span {
        font-size: 11px;
        font-weight: 900;
        letter-spacing: 0.24em;
        color: #6ceeff;
    }
    .mark {
        width: 28px;
        height: 28px;
    }
    .chip {
        padding: 7px 12px;
        border: 1px solid rgb(255 255 255 / 0.18);
        border-radius: 999px;
        background: rgb(7 16 26 / 0.76);
        font-size: 10px;
        font-weight: 900;
        letter-spacing: 0.1em;
        backdrop-filter: blur(10px);
    }
    .warning {
        position: absolute;
        left: 16px;
        right: 16px;
        bottom: 16px;
        margin: 0;
        padding: 9px 12px;
        border-radius: 9px;
        background: rgb(148 40 34 / 0.94);
        font-size: 11.5px;
    }

    .body {
        position: relative;
        z-index: 2;
        display: grid;
        gap: 14px;
        margin-top: -18px;
        padding: 20px 16px calc(32px + env(safe-area-inset-bottom));
        border-radius: 20px 20px 0 0;
        border-top: 1px solid rgb(255 255 255 / 0.08);
        background: #07101a;
        box-shadow: 0 -18px 40px rgb(0 0 0 / 0.45);
    }
    .head {
        display: grid;
        gap: 8px;
    }
    h1 {
        margin: 0;
        font-size: clamp(22px, 5.6vw, 32px);
        letter-spacing: -0.03em;
        line-height: 1.15;
    }
    .byline {
        margin: 0;
        font-size: 12px;
        color: #7c8e9c;
    }
    .description {
        margin: 4px 0 0;
        font-size: 14px;
        line-height: 1.6;
        color: #b9c7d2;
    }
    .tags {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
    }
    .tags span {
        padding: 5px 10px;
        border-radius: 999px;
        border: 1px solid rgb(255 255 255 / 0.1);
        background: #0c1824;
        font-size: 11px;
        color: #93a6b4;
    }

    .grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 8px;
    }
    .grid > div {
        min-width: 0;
        display: grid;
        gap: 4px;
        padding: 12px;
        border: 1px solid rgb(255 255 255 / 0.07);
        border-radius: 12px;
        background: #0c1824;
    }
    .grid span {
        font-size: 8.5px;
        font-weight: 900;
        letter-spacing: 0.13em;
        color: #7f919f;
    }
    .grid b {
        font-size: 22px;
        letter-spacing: -0.03em;
        font-variant-numeric: tabular-nums;
    }
    .assumption {
        margin: -6px 0 0;
        font-size: 11px;
        line-height: 1.5;
        color: #62727f;
    }

    .actions {
        display: grid;
        gap: 8px;
    }
    .actions a,
    .actions button {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 9px;
        padding: 14px 16px;
        border-radius: 12px;
        border: 1px solid transparent;
        font-size: 14px;
        font-weight: 700;
        text-decoration: none;
        cursor: pointer;
        font-family: inherit;
    }
    .actions svg {
        width: 18px;
        height: 18px;
    }
    .primary {
        background: #00bfd8;
        color: #05121a;
    }
    .secondary {
        border-color: rgb(255 255 255 / 0.14);
        background: #0c1824;
        color: #eaf3f8;
    }
    .ghost {
        background: none;
        color: #7c8e9c;
        font-weight: 600;
        font-size: 13px;
    }
    .copied {
        margin: -4px 0 0;
        font-size: 12px;
        color: #59e9a5;
        text-align: center;
    }
    .note {
        margin: 0;
        font-size: 11.5px;
        line-height: 1.6;
        color: #62727f;
    }

    .panel {
        display: grid;
        gap: 10px;
        padding: 14px;
        border: 1px solid rgb(255 255 255 / 0.07);
        border-radius: 14px;
        background: #0c1824;
    }
    .panel-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 10px;
    }
    .panel h2 {
        margin: 0;
        font-size: 9px;
        font-weight: 900;
        letter-spacing: 0.15em;
        color: #7f919f;
    }
    .panel-head small {
        font-size: 11px;
        color: #93a6b4;
        font-variant-numeric: tabular-nums;
    }

    .profile {
        width: 100%;
        height: 160px;
        display: block;
        touch-action: none;
    }
    .profile .band {
        fill: #ff8a3d;
    }
    .profile .area {
        fill: rgb(0 191 216 / 0.16);
    }
    .profile .line {
        fill: none;
        stroke: #00bfd8;
        stroke-width: 2;
        vector-effect: non-scaling-stroke;
    }
    .profile .cursor {
        stroke: rgb(255 255 255 / 0.5);
        stroke-width: 1;
        vector-effect: non-scaling-stroke;
    }
    .profile .dot {
        fill: #ffffff;
    }

    .climbs {
        margin: 0;
        padding: 0;
        list-style: none;
        display: grid;
        gap: 7px;
    }
    .climbs li {
        display: flex;
        align-items: center;
        gap: 11px;
        padding: 10px 11px;
        border-radius: 10px;
        background: #08131c;
    }
    .cat {
        flex: none;
        padding: 5px 8px;
        border-radius: 6px;
        background: rgb(255 138 61 / 0.16);
        color: #ff8a3d;
        font-size: 10px;
        font-weight: 900;
        letter-spacing: 0.06em;
    }
    .where {
        flex: 1;
        min-width: 0;
        display: grid;
        gap: 2px;
    }
    .where strong {
        font-size: 13.5px;
    }
    .where span {
        font-size: 11px;
        color: #8496a3;
    }
    .gradient {
        flex: none;
        font-size: 16px;
        font-variant-numeric: tabular-nums;
    }

    .surfaces {
        display: grid;
        gap: 8px;
    }
    .surface {
        display: grid;
        grid-template-columns: 1fr auto;
        grid-template-areas: "bar bar" "name value";
        gap: 4px 10px;
        align-items: center;
    }
    .surface-bar {
        grid-area: bar;
        height: 6px;
        border-radius: 3px;
        background: #08131c;
        overflow: hidden;
    }
    .surface-bar i {
        display: block;
        height: 100%;
        background: #00bfd8;
    }
    .surface span {
        grid-area: name;
        font-size: 12px;
        color: #93a6b4;
    }
    .surface b {
        grid-area: value;
        font-size: 12px;
        font-variant-numeric: tabular-nums;
    }

    .foot {
        margin: 4px 0 0;
        font-size: 9.5px;
        letter-spacing: 0.06em;
        color: #4d5e6b;
        text-align: center;
    }

    @media (min-width: 901px) {
        .page {
            display: grid;
            grid-template-columns: minmax(0, 1fr) 460px;
            height: 100dvh;
            overflow: hidden;
        }
        .stage {
            height: 100dvh;
        }
        .body {
            height: 100dvh;
            overflow-y: auto;
            margin-top: 0;
            padding: 24px;
            border-radius: 0;
            border-top: 0;
            border-left: 1px solid rgb(255 255 255 / 0.08);
            box-shadow: none;
        }
        .actions {
            grid-template-columns: repeat(2, minmax(0, 1fr));
        }
        .actions .ghost {
            grid-column: 1 / -1;
        }
    }
</style>
