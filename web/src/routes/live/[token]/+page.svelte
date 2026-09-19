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

    let snapshot: Snapshot | null = $state(null);
    let error = $state("");
    type RouteSnapshot = {
        name?: string;
        polyline: string;
        distance_m?: number;
        elevation_gain?: number;
        min_lat?: number;
        max_lat?: number;
        min_lon?: number;
        max_lon?: number;
    };

    let map: M.Map | null = null;
    const markers = new Map<string, M.Marker>();
    let routeCoordinates: [number, number][] = [];
    let firstFit = true;

    const km = (meters: number) => `${(meters / 1000).toFixed(1)} km`;
    const fresh = (date: string) => {
        if (!date) return false;
        return Date.now() - new Date(date).getTime() < 20_000;
    };

    function decodePolyline(encoded: string, precision = 6): [number, number][] {
        const coordinates: [number, number][] = [];
        const factor = Math.pow(10, precision);
        let index = 0;
        let lat = 0;
        let lon = 0;

        const decodeValue = () => {
            let result = 0;
            let shift = 0;
            let byte = 0;
            do {
                byte = encoded.charCodeAt(index++) - 63;
                result |= (byte & 0x1f) << shift;
                shift += 5;
            } while (byte >= 0x20 && index <= encoded.length);
            return result & 1 ? ~(result >> 1) : result >> 1;
        };

        while (index < encoded.length) {
            lat += decodeValue();
            lon += decodeValue();
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
        const source = map.getSource("live-route") as M.GeoJSONSource | undefined;
        if (source) {
            source.setData(data);
            return;
        }
        map.addSource("live-route", { type: "geojson", data });
        map.addLayer({
            id: "live-route-casing",
            type: "line",
            source: "live-route",
            paint: { "line-color": "#ffffff", "line-width": 8, "line-opacity": 0.9 },
        });
        map.addLayer({
            id: "live-route-line",
            type: "line",
            source: "live-route",
            paint: { "line-color": "#06b6d4", "line-width": 5, "line-opacity": 0.98 },
        });
    }

    function fitInitialBounds() {
        if (!map || !firstFit) return;
        const bounds = new M.LngLatBounds();
        for (const [lon, lat] of routeCoordinates) bounds.extend([lon, lat]);
        if (snapshot) {
            for (const rider of snapshot.riders) {
                if (Number.isFinite(rider.latitude) && Number.isFinite(rider.longitude) &&
                    !(rider.latitude === 0 && rider.longitude === 0)) {
                    bounds.extend([rider.longitude, rider.latitude]);
                }
            }
        }
        if (!bounds.isEmpty()) {
            map.fitBounds(bounds, { padding: 80, maxZoom: 14, duration: 0 });
            firstFit = false;
        }
    }

    async function loadRoute() {
        try {
            const response = await fetch(`/api/v1/live/${encodeURIComponent(page.params.token!)}/route`, {
                cache: "no-store",
            });
            if (!response.ok) return;
            const route = (await response.json()) as RouteSnapshot;
            routeCoordinates = route.polyline ? decodePolyline(route.polyline) : [];
            syncRoute();
            fitInitialBounds();
        } catch {
            // A Live Ride remains watchable even when no route is attached.
        }
    }

    function markerElement(rider: Rider) {
        const element = document.createElement("div");
        element.className = "live-rider-marker";
        element.title = rider.display_name;
        element.innerHTML = `<span>${rider.display_name.slice(0, 1).toUpperCase()}</span>`;
        return element;
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
                marker = new M.Marker({ element: markerElement(rider) })
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

    async function refresh() {
        try {
            const response = await fetch(`/api/v1/live/${encodeURIComponent(page.params.token!)}`, {
                cache: "no-store",
            });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            snapshot = (await response.json()) as Snapshot;
            error = "";
            syncMarkers();
        } catch (e) {
            error = e instanceof Error ? e.message : "Failed to load live ride";
        }
    }

    onMount(() => {
        map = new M.Map({
            container: "live-map",
            style: "https://tiles.openfreemap.org/styles/liberty",
            center: [14.5, 52.0],
            zoom: 6,
        });
        map.addControl(new M.NavigationControl({ showCompass: true }), "top-right");
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
    <meta name="theme-color" content="#f5f6f8" />
    <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='16' fill='%23111827'/%3E%3Cpath d='M20 44L32 16l12 28-12-7-12 7z' fill='white'/%3E%3C/svg%3E" />
</svelte:head>

<div class="live-shell">
    <header>
        <div>
            <div class="brand">LIVE RIDE</div>
            <h1>{snapshot?.title ?? "Ładowanie przejazdu…"}</h1>
        </div>
        {#if snapshot}
            <div class:ended={snapshot.status === "ended"} class="status">
                {snapshot.status === "active" ? "● NA ŻYWO" : "ZAKOŃCZONY"}
            </div>
        {/if}
    </header>

    {#if error}
        <div class="error">Nie udało się odświeżyć danych: {error}</div>
    {/if}

    <main>
        <section id="live-map" aria-label="Mapa uczestników"></section>
        <aside>
            <h2>Uczestnicy</h2>
            {#if snapshot?.riders.length}
                <div class="riders">
                    {#each snapshot.riders as rider (rider.id)}
                        <article class:stale={!fresh(rider.last_seen_at)}>
                            <div class="rider-head">
                                <strong>{rider.display_name}</strong>
                                <span>{fresh(rider.last_seen_at) ? "● LIVE" : "BRAK SYGNAŁU"}</span>
                            </div>
                            <div class="speed">{rider.speed_kmh.toFixed(1)} <small>km/h</small></div>
                            <div class="metrics">
                                <div><span>❤️ Tętno</span><b>{rider.heart_rate_bpm || "—"} {rider.heart_rate_bpm ? "bpm" : ""}</b></div>
                                <div><span>📍 Dystans</span><b>{km(rider.distance_m)}</b></div>
                                <div><span>⛰ Przewyższenie</span><b>+{Math.round(rider.elevation_gain_m)} m</b></div>
                                <div><span>Wysokość</span><b>{Math.round(rider.altitude_m)} m</b></div>
                            </div>
                            <footer>
                                GPS ±{Math.round(rider.accuracy_m)} m · aktualizacja
                                {rider.last_seen_at ? new Date(rider.last_seen_at).toLocaleTimeString() : "—"}
                            </footer>
                        </article>
                    {/each}
                </div>
            {:else}
                <p class="empty">Czekam na pierwszą pozycję uczestników.</p>
            {/if}
        </aside>
    </main>
</div>

<style>
    :global(.live-rider-marker) {
        width: 38px;
        height: 38px;
        display: grid;
        place-items: center;
        border-radius: 999px;
        background: #111827;
        color: white;
        border: 3px solid white;
        box-shadow: 0 5px 18px rgb(0 0 0 / 30%);
        font-weight: 800;
        transition: opacity 160ms ease;
    }
    :global(.live-rider-marker.stale) { opacity: 0.45; }
    .live-shell { min-height: 100vh; background: #f5f6f8; color: #111827; padding: 24px; }
    header { display: flex; align-items: center; justify-content: space-between; gap: 24px; max-width: 1500px; margin: 0 auto 18px; }
    h1 { margin: 4px 0 0; font-size: clamp(1.6rem, 3vw, 2.5rem); letter-spacing: -.03em; }
    .brand { font-size: .75rem; font-weight: 900; letter-spacing: .18em; color: #0f172a; }
    .status { padding: 9px 13px; border-radius: 999px; background: #dcfce7; color: #166534; font-size: .78rem; font-weight: 800; }
    .status.ended { background: #e5e7eb; color: #374151; }
    .error { max-width: 1500px; margin: 0 auto 14px; padding: 10px 14px; border-radius: 12px; background: #fee2e2; color: #991b1b; }
    main { max-width: 1500px; margin: auto; display: grid; grid-template-columns: minmax(0, 1fr) 360px; gap: 18px; }
    #live-map { min-height: 72vh; border-radius: 22px; overflow: hidden; background: #dbeafe; box-shadow: 0 8px 30px rgb(15 23 42 / 8%); }
    aside { min-width: 0; }
    aside h2 { margin: 0 0 12px; font-size: 1rem; }
    .riders { display: grid; gap: 12px; }
    article { background: white; border-radius: 18px; padding: 17px; box-shadow: 0 8px 30px rgb(15 23 42 / 6%); border: 1px solid #e5e7eb; }
    article.stale { opacity: .68; }
    .rider-head { display: flex; justify-content: space-between; gap: 10px; align-items: center; }
    .rider-head span { font-size: .68rem; font-weight: 800; color: #16a34a; }
    article.stale .rider-head span { color: #9ca3af; }
    .speed { font-size: 2.1rem; font-weight: 800; margin: 13px 0; letter-spacing: -.04em; }
    .speed small { font-size: .8rem; color: #64748b; letter-spacing: normal; }
    .metrics { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .metrics div { padding: 10px; border-radius: 12px; background: #f8fafc; display: grid; gap: 4px; }
    .metrics span { font-size: .68rem; color: #64748b; }
    .metrics b { font-size: .9rem; }
    article footer { margin-top: 12px; font-size: .68rem; color: #94a3b8; }
    .empty { color: #64748b; }
    @media (max-width: 900px) {
        .live-shell { padding: 12px; }
        header { align-items: flex-start; }
        main { grid-template-columns: 1fr; }
        #live-map { min-height: 55vh; border-radius: 18px; }
        aside { padding-bottom: 30px; }
    }
</style>
