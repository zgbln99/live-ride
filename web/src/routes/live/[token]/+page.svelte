<script lang="ts">
    import { page } from "$app/state";
    import { onMount } from "svelte";
    import * as M from "maplibre-gl";
    import "maplibre-gl/dist/maplibre-gl.css";

    type Rider = {
        id: string;
        display_name: string;
        latitude: number;
        longitude: number;
        speed_kmh: number;
        altitude_m: number;
        heading_deg: number;
        accuracy_m: number;
        heart_rate_bpm: number;
        distance_m: number;
        elevation_gain_m: number;
        last_seen_at: string;
    };

    type Snapshot = {
        title: string;
        trail_id: string;
        status: "active" | "ended";
        started_at: string;
        ended_at: string;
        riders: Rider[];
    };

    type RouteSnapshot = {
        name?: string;
        polyline: string;
        distance_m?: number;
        elevation_gain?: number;
    };

    let snapshot: Snapshot | null = $state(null);
    let route: RouteSnapshot | null = $state(null);
    let error = $state("");
    let map: M.Map | null = null;
    let routeCoordinates: [number, number][] = [];
    let firstFit = true;
    const markers = new Map<string, M.Marker>();

    const km = (m: number) => `${(m / 1000).toFixed(m >= 10000 ? 1 : 2)} km`;
    const fresh = (date: string) => !!date && Date.now() - new Date(date).getTime() < 20_000;
    const clock = (date: string) => date ? new Date(date).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) : "—";

    function decodePolyline(encoded: string, precision = 6): [number, number][] {
        const coordinates: [number, number][] = [];
        const factor = Math.pow(10, precision);
        let index = 0;
        let lat = 0;
        let lon = 0;
        while (index < encoded.length) {
            let result = 0;
            let shift = 0;
            let byte: number;
            do {
                byte = encoded.charCodeAt(index++) - 63;
                result |= (byte & 0x1f) << shift;
                shift += 5;
            } while (byte >= 0x20);
            lat += result & 1 ? ~(result >> 1) : result >> 1;

            result = 0;
            shift = 0;
            do {
                byte = encoded.charCodeAt(index++) - 63;
                result |= (byte & 0x1f) << shift;
                shift += 5;
            } while (byte >= 0x20);
            lon += result & 1 ? ~(result >> 1) : result >> 1;
            coordinates.push([lon / factor, lat / factor]);
        }
        return coordinates;
    }

    function syncRoute() {
        if (!map || !map.isStyleLoaded() || routeCoordinates.length < 2) return;
        const data: GeoJSON.Feature<GeoJSON.LineString> = {
            type: "Feature",
            properties: {},
            geometry: { type: "LineString", coordinates: routeCoordinates },
        };
        const existing = map.getSource("route") as M.GeoJSONSource | undefined;
        if (existing) {
            existing.setData(data);
            return;
        }
        map.addSource("route", { type: "geojson", data });
        map.addLayer({
            id: "route-outline",
            type: "line",
            source: "route",
            paint: { "line-color": "#071018", "line-width": 10, "line-opacity": 0.55 },
        });
        map.addLayer({
            id: "route-line",
            type: "line",
            source: "route",
            paint: { "line-color": "#18d9ff", "line-width": 6, "line-opacity": 1 },
        });
    }

    function fitInitialBounds() {
        if (!map || !firstFit) return;
        const bounds = new M.LngLatBounds();
        for (const p of routeCoordinates) bounds.extend(p);
        for (const rider of snapshot?.riders ?? []) {
            if (Number.isFinite(rider.latitude) && Number.isFinite(rider.longitude) && !(rider.latitude === 0 && rider.longitude === 0)) {
                bounds.extend([rider.longitude, rider.latitude]);
            }
        }
        if (!bounds.isEmpty()) {
            map.fitBounds(bounds, { padding: 70, maxZoom: 14, duration: 0 });
            firstFit = false;
        }
    }

    function riderMarker(rider: Rider) {
        const el = document.createElement("div");
        el.className = "lr-marker";
        el.innerHTML = `<span>${rider.display_name.slice(0, 1).toUpperCase()}</span>`;
        el.title = rider.display_name;
        return el;
    }

    function syncMarkers() {
        if (!map || !snapshot) return;
        const alive = new Set<string>();
        for (const rider of snapshot.riders) {
            if (!Number.isFinite(rider.latitude) || !Number.isFinite(rider.longitude)) continue;
            if (rider.latitude === 0 && rider.longitude === 0) continue;
            alive.add(rider.id);
            let marker = markers.get(rider.id);
            if (!marker) {
                marker = new M.Marker({ element: riderMarker(rider) })
                    .setLngLat([rider.longitude, rider.latitude])
                    .addTo(map);
                markers.set(rider.id, marker);
            } else {
                marker.setLngLat([rider.longitude, rider.latitude]);
            }
            marker.getElement().classList.toggle("stale", !fresh(rider.last_seen_at));
        }
        for (const [id, marker] of markers) {
            if (!alive.has(id)) {
                marker.remove();
                markers.delete(id);
            }
        }
        fitInitialBounds();
    }

    async function loadRoute() {
        try {
            const response = await fetch(`/api/v1/live/${encodeURIComponent(page.params.token!)}/route`, { cache: "no-store" });
            if (!response.ok) return;
            route = await response.json() as RouteSnapshot;
            routeCoordinates = route.polyline ? decodePolyline(route.polyline) : [];
            syncRoute();
            fitInitialBounds();
        } catch {}
    }

    async function refresh() {
        try {
            const response = await fetch(`/api/v1/live/${encodeURIComponent(page.params.token!)}`, { cache: "no-store" });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            snapshot = await response.json() as Snapshot;
            error = "";
            syncMarkers();
        } catch (e) {
            error = e instanceof Error ? e.message : "Błąd połączenia";
        }
    }

    onMount(() => {
        map = new M.Map({
            container: "map",
            style: "https://tiles.openfreemap.org/styles/dark",
            center: [14.5, 52],
            zoom: 6,
            attributionControl: false,
        });
        map.addControl(new M.NavigationControl({ showCompass: true, showZoom: true }), "top-right");
        map.addControl(new M.AttributionControl({ compact: true }), "bottom-right");
        map.on("load", () => {
            syncRoute();
            fitInitialBounds();
        });
        void loadRoute();
        void refresh();
        const timer = window.setInterval(() => void refresh(), 3000);
        return () => {
            window.clearInterval(timer);
            for (const marker of markers.values()) marker.remove();
            markers.clear();
            map?.remove();
            map = null;
        };
    });
</script>

<svelte:head>
    <title>{snapshot?.title ?? "Live Ride"} · Live Ride</title>
    <meta name="theme-color" content="#070b10" />
    <meta name="description" content="Live Ride — podgląd przejazdu na żywo" />
    <link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 64 64%22><rect width=%2264%22 height=%2264%22 rx=%2218%22 fill=%22%23070b10%22/><path d=%22M19 43 32 14l13 29-13-7z%22 fill=%22%2318d9ff%22/></svg>" />
</svelte:head>

<div class="page-shell">
    <div id="map"></div>
    <div class="shade"></div>

    <header class="topbar">
        <div class="brand-wrap">
            <div class="logo">▲</div>
            <div>
                <div class="brand">LIVE RIDE</div>
                <div class="ride-title">{snapshot?.title ?? "Ładowanie przejazdu…"}</div>
            </div>
        </div>
        <div class:ended={snapshot?.status === "ended"} class="live-pill">
            {snapshot?.status === "ended" ? "ZAKOŃCZONY" : "● LIVE"}
        </div>
    </header>

    {#if error}
        <div class="error-pill">Brak świeżych danych · {error}</div>
    {/if}

    <section class="route-summary">
        <div>
            <span>TRASA</span>
            <strong>{route?.distance_m ? km(route.distance_m) : "—"}</strong>
        </div>
        <div>
            <span>PRZEWYŻSZENIE</span>
            <strong>{route?.elevation_gain ? `+${Math.round(route.elevation_gain)} m` : "—"}</strong>
        </div>
        <div>
            <span>START</span>
            <strong>{snapshot?.started_at ? clock(snapshot.started_at) : "—"}</strong>
        </div>
    </section>

    <section class="rider-panel">
        <div class="panel-head">
            <span>UCZESTNICY</span>
            <b>{snapshot?.riders.length ?? 0}</b>
        </div>
        <div class="rider-strip">
            {#if snapshot?.riders.length}
                {#each snapshot.riders as rider (rider.id)}
                    <article class:stale={!fresh(rider.last_seen_at)}>
                        <div class="rider-top">
                            <div class="avatar">{rider.display_name.slice(0, 1).toUpperCase()}</div>
                            <div class="name-wrap">
                                <strong>{rider.display_name}</strong>
                                <span>{fresh(rider.last_seen_at) ? "AKTYWNY" : "BRAK SYGNAŁU"}</span>
                            </div>
                            <div class="speed"><b>{rider.speed_kmh.toFixed(1)}</b><small>km/h</small></div>
                        </div>
                        <div class="stats">
                            <div><span>HR</span><b>{rider.heart_rate_bpm || "—"}<small>{rider.heart_rate_bpm ? " bpm" : ""}</small></b></div>
                            <div><span>DYSTANS</span><b>{km(rider.distance_m)}</b></div>
                            <div><span>W GÓRĘ</span><b>+{Math.round(rider.elevation_gain_m)} m</b></div>
                            <div><span>WYSOKOŚĆ</span><b>{Math.round(rider.altitude_m)} m</b></div>
                        </div>
                        <footer>GPS ±{Math.round(rider.accuracy_m)} m · {clock(rider.last_seen_at)}</footer>
                    </article>
                {/each}
            {:else}
                <div class="empty">Czekam na pierwszą pozycję uczestników…</div>
            {/if}
        </div>
    </section>
</div>

<style>
    :global(html), :global(body) { margin: 0; background: #070b10; color: #f8fbff; }
    :global(body) { overflow: hidden; }
    :global(.lr-marker) {
        width: 42px; height: 42px; border-radius: 50%; display: grid; place-items: center;
        background: #071018; border: 3px solid #18d9ff; color: #fff; font-weight: 900;
        box-shadow: 0 0 0 5px rgb(24 217 255 / 14%), 0 10px 30px rgb(0 0 0 / 55%);
        transition: opacity .2s ease, transform .2s ease;
    }
    :global(.lr-marker.stale) { opacity: .35; }
    .page-shell { position: relative; min-height: 100dvh; overflow: hidden; background: #070b10; font-family: Inter, ui-sans-serif, system-ui, sans-serif; }
    #map { position: absolute; inset: 0; }
    .shade { position: absolute; inset: 0; pointer-events: none; background: linear-gradient(180deg, rgb(4 8 12 / 78%) 0, transparent 26%, transparent 58%, rgb(4 8 12 / 92%) 100%); }
    .topbar { position: absolute; z-index: 5; top: 0; left: 0; right: 0; display: flex; align-items: center; justify-content: space-between; padding: 22px 24px; gap: 16px; }
    .brand-wrap { display: flex; align-items: center; gap: 12px; min-width: 0; }
    .logo { width: 42px; height: 42px; display: grid; place-items: center; border-radius: 13px; background: #18d9ff; color: #061017; font-size: 19px; font-weight: 900; transform: rotate(8deg); }
    .brand { font-size: 11px; letter-spacing: .22em; font-weight: 900; color: #80efff; }
    .ride-title { margin-top: 4px; font-size: clamp(18px, 2vw, 28px); font-weight: 850; letter-spacing: -.035em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 60vw; }
    .live-pill { flex: none; padding: 9px 13px; border: 1px solid rgb(24 217 255 / 34%); background: rgb(8 17 24 / 72%); backdrop-filter: blur(16px); border-radius: 999px; color: #67f7b5; font-size: 11px; font-weight: 900; letter-spacing: .08em; }
    .live-pill.ended { color: #b5c0ca; border-color: rgb(255 255 255 / 16%); }
    .error-pill { position: absolute; z-index: 7; top: 88px; left: 50%; transform: translateX(-50%); padding: 9px 13px; border-radius: 999px; background: rgb(118 26 26 / 88%); font-size: 12px; }
    .route-summary { position: absolute; z-index: 5; top: 92px; left: 24px; display: flex; gap: 8px; }
    .route-summary > div { min-width: 112px; padding: 10px 12px; border-radius: 14px; border: 1px solid rgb(255 255 255 / 10%); background: rgb(6 13 18 / 68%); backdrop-filter: blur(15px); display: grid; gap: 4px; }
    .route-summary span, .panel-head span { font-size: 9px; font-weight: 900; color: #84919e; letter-spacing: .14em; }
    .route-summary strong { font-size: 15px; letter-spacing: -.025em; }
    .rider-panel { position: absolute; z-index: 5; left: 20px; right: 20px; bottom: 18px; padding: 14px; border-radius: 22px; border: 1px solid rgb(255 255 255 / 9%); background: rgb(5 11 16 / 86%); backdrop-filter: blur(22px); box-shadow: 0 22px 55px rgb(0 0 0 / 45%); }
    .panel-head { display: flex; align-items: center; gap: 8px; margin: 0 4px 10px; }
    .panel-head b { display: grid; place-items: center; min-width: 22px; height: 22px; border-radius: 999px; background: #18d9ff; color: #061017; font-size: 11px; }
    .rider-strip { display: grid; grid-auto-flow: column; grid-auto-columns: minmax(280px, 360px); gap: 10px; overflow-x: auto; scrollbar-width: none; }
    .rider-strip::-webkit-scrollbar { display: none; }
    article { padding: 14px; border-radius: 17px; background: linear-gradient(145deg, rgb(255 255 255 / 8%), rgb(255 255 255 / 3%)); border: 1px solid rgb(255 255 255 / 8%); transition: opacity .2s ease; }
    article.stale { opacity: .48; }
    .rider-top { display: flex; align-items: center; gap: 10px; }
    .avatar { width: 38px; height: 38px; border-radius: 13px; display: grid; place-items: center; background: #18d9ff; color: #061017; font-weight: 900; }
    .name-wrap { min-width: 0; display: grid; gap: 3px; }
    .name-wrap strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .name-wrap span { font-size: 9px; color: #67f7b5; font-weight: 900; letter-spacing: .09em; }
    article.stale .name-wrap span { color: #8c99a6; }
    .speed { margin-left: auto; display: flex; align-items: baseline; gap: 4px; }
    .speed b { font-size: 29px; letter-spacing: -.055em; }
    .speed small { font-size: 10px; color: #83909d; }
    .stats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 7px; margin-top: 12px; }
    .stats div { padding: 9px; border-radius: 11px; background: rgb(0 0 0 / 18%); display: grid; gap: 4px; min-width: 0; }
    .stats span { font-size: 8px; color: #788591; font-weight: 900; letter-spacing: .1em; }
    .stats b { font-size: 13px; white-space: nowrap; }
    .stats small { font-size: 9px; color: #7d8994; }
    article footer { margin-top: 9px; font-size: 9px; color: #66727c; }
    .empty { padding: 22px; color: #8996a2; }

    @media (min-width: 1100px) {
        .rider-panel { left: auto; top: 96px; bottom: 20px; right: 20px; width: 360px; overflow: hidden; }
        .rider-strip { grid-auto-flow: row; grid-auto-columns: auto; grid-template-columns: 1fr; max-height: calc(100dvh - 175px); overflow-y: auto; overflow-x: hidden; }
        .route-summary { right: 400px; left: auto; }
    }
    @media (max-width: 700px) {
        .topbar { padding: 16px 14px; }
        .ride-title { max-width: 55vw; font-size: 18px; }
        .logo { width: 38px; height: 38px; border-radius: 12px; }
        .route-summary { top: 78px; left: 12px; right: 12px; gap: 6px; }
        .route-summary > div { flex: 1; min-width: 0; padding: 8px 9px; }
        .route-summary span { font-size: 7px; }
        .route-summary strong { font-size: 12px; }
        .rider-panel { left: 8px; right: 8px; bottom: 8px; padding: 10px; border-radius: 18px; }
        .rider-strip { grid-auto-columns: 86vw; }
        .stats { grid-template-columns: repeat(2, 1fr); }
        .live-pill { padding: 8px 10px; font-size: 9px; }
    }
</style>
