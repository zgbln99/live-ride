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

    /** A rider plus everything the viewer derives about them. */
    type RiderView = Rider & {
        fresh: boolean;
        secondsSinceUpdate: number;
        /** Distance ridden along the route geometry, in metres. */
        alongMeters: number | null;
        /** Share of the route completed, 0..1. */
        progress: number | null;
        /** Perpendicular distance from the route, in metres. */
        offRouteMeters: number | null;
        colour: string;
    };

    /** Riders are told apart by colour, in a fixed order. */
    const RIDER_COLOURS = [
        "#00BFD8",
        "#FF8A3D",
        "#8B7BFF",
        "#31D07C",
        "#FF5C8A",
        "#F2C037",
        "#4BA3FF",
        "#FF6B4A",
    ];

    /** A rider is "live" while telemetry keeps arriving. */
    const FRESH_AFTER_SECONDS = 20;
    const REFRESH_MS = 3000;

    let snapshot: Snapshot | null = $state(null);
    let route: RouteSnapshot | null = $state(null);
    let error = $state("");
    let mapError = $state("");
    let now = $state(Date.now());
    let selectedRiderId = $state<string | null>(null);
    let followSelected = $state(false);
    let sheetOpen = $state(false);

    let map: M.Map | null = null;
    let routeCoordinates: [number, number][] = [];
    let routeCumulative: number[] = [];
    let routeLengthMeters = 0;
    let firstFit = true;
    const markers = new Map<string, M.Marker>();

    // `$derived.by` keeps the body a closure, so `snapshot` is read when the
    // value is recomputed rather than being narrowed to its initial null.
    const riders = $derived.by<RiderView[]>(() =>
        (snapshot?.riders ?? [])
            .map((rider, index) => {
                const seconds = secondsSince(rider.last_seen_at);
                const projection = projectOnRoute(rider.longitude, rider.latitude);
                return {
                    ...rider,
                    fresh: seconds !== null && seconds < FRESH_AFTER_SECONDS,
                    secondsSinceUpdate: seconds ?? Number.POSITIVE_INFINITY,
                    alongMeters: projection?.alongMeters ?? null,
                    progress:
                        projection && routeLengthMeters > 0
                            ? Math.min(1, projection.alongMeters / routeLengthMeters)
                            : null,
                    offRouteMeters: projection?.offRouteMeters ?? null,
                    colour: RIDER_COLOURS[index % RIDER_COLOURS.length],
                };
            })
            // Ranking uses progress along the route geometry — never the
            // straight-line distance to the finish, which puts a rider on the
            // far side of a hill ahead of one who has actually ridden further.
            .sort((a, b) => {
                if (a.progress !== null && b.progress !== null) return b.progress - a.progress;
                if (a.progress !== null) return -1;
                if (b.progress !== null) return 1;
                return b.distance_m - a.distance_m;
            }),
    );

    const liveCount = $derived(riders.filter((rider) => rider.fresh).length);
    const selected = $derived(riders.find((rider) => rider.id === selectedRiderId) ?? null);
    const ended = $derived.by(() => snapshot?.status === "ended");

    function km(meters: number, digits?: number) {
        const value = meters / 1000;
        return `${value.toFixed(digits ?? (value >= 10 ? 1 : 2))} km`;
    }

    function secondsSince(date: string): number | null {
        if (!date) return null;
        const parsed = new Date(date).getTime();
        if (Number.isNaN(parsed)) return null;
        return Math.max(0, Math.round((now - parsed) / 1000));
    }

    function ago(seconds: number) {
        if (!Number.isFinite(seconds)) return "brak danych";
        if (seconds < 10) return "przed chwilą";
        if (seconds < 60) return `${seconds} s temu`;
        if (seconds < 3600) return `${Math.floor(seconds / 60)} min temu`;
        return `${Math.floor(seconds / 3600)} godz. temu`;
    }

    function clock(date: string) {
        if (!date) return "—";
        const parsed = new Date(date);
        return Number.isNaN(parsed.getTime())
            ? "—"
            : parsed.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
    }

    function elapsed(date: string) {
        if (!date) return "—";
        const started = new Date(date).getTime();
        if (Number.isNaN(started)) return "—";
        const endedAt = snapshot?.ended_at ? new Date(snapshot.ended_at).getTime() : now;
        const seconds = Math.max(0, Math.floor(((endedAt || now) - started) / 1000));
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
    }

    function initials(name: string) {
        const parts = name.trim().split(/[\s_.-]+/).filter(Boolean);
        if (!parts.length) return "?";
        if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
        return (parts[0][0] + parts[1][0]).toUpperCase();
    }

    function compass(degrees: number) {
        // Kierunki po polsku: północ, północny wschód i tak dalej.
        const labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
        return labels[Math.round((((degrees % 360) + 360) % 360) / 45) % 8];
    }

    function decodePolyline(encoded: string, precision = 6): [number, number][] {
        const coordinates: [number, number][] = [];
        const factor = 10 ** precision;
        let index = 0;
        let lat = 0;
        let lon = 0;
        while (index < encoded.length) {
            let result = 0;
            let shift = 0;
            let byte = 0;
            do {
                byte = encoded.charCodeAt(index++) - 63;
                result |= (byte & 0x1f) << shift;
                shift += 5;
            } while (byte >= 0x20 && index <= encoded.length);
            lat += result & 1 ? ~(result >> 1) : result >> 1;

            result = 0;
            shift = 0;
            do {
                byte = encoded.charCodeAt(index++) - 63;
                result |= (byte & 0x1f) << shift;
                shift += 5;
            } while (byte >= 0x20 && index <= encoded.length);
            lon += result & 1 ? ~(result >> 1) : result >> 1;
            coordinates.push([lon / factor, lat / factor]);
        }
        return coordinates;
    }

    function haversine(a: [number, number], b: [number, number]) {
        const R = 6371008.8;
        const toRad = Math.PI / 180;
        const dLat = (b[1] - a[1]) * toRad;
        const dLon = (b[0] - a[0]) * toRad;
        const lat1 = a[1] * toRad;
        const lat2 = b[1] * toRad;
        const h =
            Math.sin(dLat / 2) ** 2 +
            Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
        return 2 * R * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
    }

    function buildCumulative() {
        routeCumulative = [];
        let total = 0;
        for (let i = 0; i < routeCoordinates.length; i++) {
            if (i > 0) total += haversine(routeCoordinates[i - 1], routeCoordinates[i]);
            routeCumulative.push(total);
        }
        routeLengthMeters = total;
    }

    /**
     * Projects a rider onto the route and returns how far along it they are.
     *
     * The projection is per segment rather than per vertex, so progress moves
     * smoothly between two widely spaced route points instead of jumping.
     */
    function projectOnRoute(lon: number, lat: number) {
        if (routeCoordinates.length < 2 || !Number.isFinite(lon) || !Number.isFinite(lat)) {
            return null;
        }
        const latScale = Math.max(0.05, Math.abs(Math.cos((lat * Math.PI) / 180)));
        let best: { alongMeters: number; offRouteMeters: number } | null = null;

        for (let i = 0; i < routeCoordinates.length - 1; i++) {
            const a = routeCoordinates[i];
            const b = routeCoordinates[i + 1];
            const bx = (b[0] - a[0]) * latScale * 111320;
            const by = (b[1] - a[1]) * 110540;
            const px = (lon - a[0]) * latScale * 111320;
            const py = (lat - a[1]) * 110540;
            const lengthSquared = bx * bx + by * by;
            let t = 0;
            if (lengthSquared > 0) {
                t = Math.min(1, Math.max(0, (px * bx + py * by) / lengthSquared));
            }
            const dx = px - bx * t;
            const dy = py - by * t;
            const distance = Math.sqrt(dx * dx + dy * dy);
            if (!best || distance < best.offRouteMeters) {
                const segment = routeCumulative[i + 1] - routeCumulative[i];
                best = {
                    alongMeters: routeCumulative[i] + segment * t,
                    offRouteMeters: distance,
                };
            }
        }
        return best;
    }

    function hasPosition(rider: Rider) {
        return (
            Number.isFinite(rider.latitude) &&
            Number.isFinite(rider.longitude) &&
            !(rider.latitude === 0 && rider.longitude === 0)
        );
    }

    function syncRoute() {
        if (!map || !map.isStyleLoaded() || routeCoordinates.length < 2) return;
        const data: GeoJSON.Feature<GeoJSON.LineString> = {
            type: "Feature",
            properties: {},
            geometry: { type: "LineString", coordinates: routeCoordinates },
        };
        const existing = map.getSource("live-route") as M.GeoJSONSource | undefined;
        if (existing) {
            existing.setData(data);
            return;
        }
        map.addSource("live-route", { type: "geojson", data });
        map.addLayer({
            id: "live-route-case",
            type: "line",
            source: "live-route",
            layout: { "line-cap": "round", "line-join": "round" },
            paint: { "line-color": "#ffffff", "line-width": 10, "line-opacity": 0.95 },
        });
        map.addLayer({
            id: "live-route-line",
            type: "line",
            source: "live-route",
            layout: { "line-cap": "round", "line-join": "round" },
            paint: { "line-color": "#00bfd8", "line-width": 6 },
        });
    }

    function fitAll(force = false) {
        if (!map || (!firstFit && !force)) return;
        const bounds = new M.LngLatBounds();
        for (const point of routeCoordinates) bounds.extend(point);
        for (const rider of snapshot?.riders ?? []) {
            if (hasPosition(rider)) bounds.extend([rider.longitude, rider.latitude]);
        }
        if (bounds.isEmpty()) return;
        map.fitBounds(bounds, {
            padding: { top: 110, right: 90, bottom: 210, left: 90 },
            maxZoom: 15,
            duration: force ? 550 : 0,
        });
        firstFit = false;
    }

    function focusRider(rider: RiderView, zoom = 15) {
        selectedRiderId = rider.id;
        followSelected = true;
        if (map && hasPosition(rider)) {
            map.easeTo({
                center: [rider.longitude, rider.latitude],
                zoom: Math.max(map.getZoom(), zoom),
                duration: 450,
            });
        }
    }

    function markerElement(rider: RiderView) {
        const root = document.createElement("button");
        root.type = "button";
        root.className = "lr-marker";
        root.setAttribute("aria-label", rider.display_name);
        root.innerHTML = `<span class="lr-marker-initials"></span><i></i>`;
        root.onclick = () => focusRider(rider);
        return root;
    }

    function syncMarkers() {
        if (!map || !snapshot) return;
        const alive = new Set<string>();
        for (const rider of riders) {
            if (!hasPosition(rider)) continue;
            alive.add(rider.id);
            let marker = markers.get(rider.id);
            if (!marker) {
                marker = new M.Marker({ element: markerElement(rider), anchor: "center" })
                    .setLngLat([rider.longitude, rider.latitude])
                    .addTo(map);
                markers.set(rider.id, marker);
            } else {
                marker.setLngLat([rider.longitude, rider.latitude]);
            }
            const element = marker.getElement();
            element.style.setProperty("--rider-colour", rider.colour);
            const label = element.querySelector(".lr-marker-initials");
            if (label) label.textContent = initials(rider.display_name);
            element.classList.toggle("stale", !rider.fresh);
            element.classList.toggle("selected", selectedRiderId === rider.id);
        }
        for (const [id, marker] of markers) {
            if (!alive.has(id)) {
                marker.remove();
                markers.delete(id);
            }
        }

        if (followSelected && selected && hasPosition(selected)) {
            map.easeTo({
                center: [selected.longitude, selected.latitude],
                duration: 800,
            });
        }
        fitAll();
    }

    async function loadRoute() {
        try {
            const response = await fetch(
                `/api/v1/live/${encodeURIComponent(page.params.token!)}/route`,
                { cache: "no-store" },
            );
            if (!response.ok) return;
            route = (await response.json()) as RouteSnapshot;
            routeCoordinates = route.polyline ? decodePolyline(route.polyline) : [];
            buildCumulative();
            syncRoute();
            fitAll();
        } catch {
            // A LIVE without a planned route is still valid: rider markers,
            // telemetry and the map all keep working without it.
        }
    }

    async function refresh() {
        try {
            const response = await fetch(
                `/api/v1/live/${encodeURIComponent(page.params.token!)}`,
                { cache: "no-store" },
            );
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            snapshot = (await response.json()) as Snapshot;
            now = Date.now();
            error = "";
            syncMarkers();
        } catch (e) {
            error = e instanceof Error ? e.message : "Utracono połączenie";
        }
    }

    async function initMap() {
        try {
            const styleResponse = await fetch("/api/v1/map/style?theme=liberty", {
                cache: "force-cache",
            });
            if (!styleResponse.ok) throw new Error(`style HTTP ${styleResponse.status}`);
            const style = (await styleResponse.json()) as M.StyleSpecification;
            map = new M.Map({
                container: "live-map",
                style,
                center: [14.5, 52],
                zoom: 6,
                attributionControl: false,
                fadeDuration: 0,
            });
            map.addControl(new M.NavigationControl({ showCompass: true, showZoom: true }), "top-right");
            map.addControl(new M.AttributionControl({ compact: true }), "bottom-right");
            map.on("load", () => {
                syncRoute();
                syncMarkers();
                fitAll();
            });
            // Any manual pan releases rider follow, exactly like the app.
            map.on("dragstart", () => (followSelected = false));
            map.on("error", (event) => console.warn("Live Ride map error", event.error));
        } catch (e) {
            mapError = e instanceof Error ? e.message : "Nie udało się uruchomić mapy";
        }
    }

    onMount(() => {
        // Podgląd jest po polsku, więc mówi to też przeglądarce — ale tylko
        // on, bez ruszania reszty serwisu.
        document.documentElement.lang = "pl";
        void initMap();
        void loadRoute();
        void refresh();
        const poll = window.setInterval(() => void refresh(), REFRESH_MS);
        // A separate clock keeps "12s ago" honest between polls.
        const tick = window.setInterval(() => (now = Date.now()), 1000);
        return () => {
            window.clearInterval(poll);
            window.clearInterval(tick);
            for (const marker of markers.values()) marker.remove();
            markers.clear();
            map?.remove();
            map = null;
        };
    });
</script>

<svelte:head>
    <title>{snapshot?.title ?? "Live Ride"} · Live Ride</title>
    <meta name="theme-color" content="#07101A" />
    <meta name="description" content="Śledź tę jazdę na żywo w Live Ride." />
    <link
        rel="icon"
        href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 64 64%22><rect width=%2264%22 height=%2264%22 rx=%2212%22 fill=%22%2307101a%22/><path d=%22M10 52 33 9l9 18H23z%22 fill=%22white%22/><path d=%22M30 56 58 12 49 56z%22 fill=%22%2300bfd8%22/></svg>"
    />
</svelte:head>

<main class="viewer">
    <div id="live-map" class="map"></div>

    <header class="topbar">
        <div class="brand">
            <svg class="mark" viewBox="0 0 64 64" aria-hidden="true">
                <path d="M10 52 33 9l9 18H23z" fill="#ffffff" />
                <path d="M30 56 58 12 49 56z" fill="#00bfd8" />
            </svg>
            <div class="brand-copy">
                <span>LIVE RIDE</span>
                <strong>{snapshot?.title ?? "Wczytuję przejazd…"}</strong>
            </div>
        </div>
        <div class="top-actions">
            <button class="ghost" onclick={() => fitAll(true)} title="Pokaż wszystkich">
                <svg viewBox="0 0 24 24" aria-hidden="true"
                    ><path
                        fill="currentColor"
                        d="M4 9V4h5v2H6v3zm0 6v5h5v-2H6v-3zm16 0v5h-5v-2h3v-3zM20 9V4h-5v2h3v3zm-8 6a3 3 0 1 1 0-6 3 3 0 0 1 0 6"
                    /></svg
                >
            </button>
            <div class="status" class:ended>
                <i></i>{ended ? "ZAKOŃCZONA" : "NA ŻYWO"}
            </div>
        </div>
    </header>

    {#if error || mapError}
        <div class="warning" role="status">
            {#if mapError}<span>Mapa: {mapError}</span>{/if}
            {#if error}<span>Dane na żywo: {error} — ponawiam co {REFRESH_MS / 1000} s</span>{/if}
        </div>
    {/if}

    <section class="rail">
        <div class="session">
            <div><span>CZAS</span><b>{elapsed(snapshot?.started_at ?? "")}</b></div>
            <div><span>START</span><b>{clock(snapshot?.started_at ?? "")}</b></div>
            <div>
                <span>TRASA</span><b>{route?.distance_m ? km(route.distance_m, 1) : "—"}</b>
            </div>
        </div>

        <div class="rail-head">
            <div>
                <span>ZAWODNICY</span>
                <strong>{riders.length}</strong>
                {#if riders.length}<em>{liveCount} na żywo</em>{/if}
            </div>
            <small>odświeżanie co {REFRESH_MS / 1000} s</small>
        </div>

        <div class="rider-list">
            {#if riders.length}
                {#each riders as rider, index (rider.id)}
                    <button
                        class="rider"
                        class:stale={!rider.fresh}
                        class:selected={selectedRiderId === rider.id}
                        style={`--rider-colour:${rider.colour}`}
                        onclick={() => focusRider(rider)}
                    >
                        <div class="rider-top">
                            <div class="avatar">{initials(rider.display_name)}</div>
                            <div class="who">
                                <strong>{rider.display_name}</strong>
                                <span>
                                    {#if rider.fresh}
                                        {riders.length > 1 ? `P${index + 1} · ` : ""}JEDZIE
                                    {:else}
                                        BRAK SYGNAŁU · {ago(rider.secondsSinceUpdate)}
                                    {/if}
                                </span>
                            </div>
                            <div class="speed">
                                <b>{rider.speed_kmh.toFixed(1)}</b><span>km/h</span>
                            </div>
                        </div>

                        {#if rider.progress !== null}
                            <div class="progress" title="Pozycja na trasie">
                                <div class="bar"><i style={`width:${rider.progress * 100}%`}></i></div>
                                <small>
                                    {Math.round(rider.progress * 100)}% trasy
                                    {#if rider.offRouteMeters !== null && rider.offRouteMeters > 80}
                                        · <b class="off">{Math.round(rider.offRouteMeters)} m od trasy</b>
                                    {/if}
                                </small>
                            </div>
                        {/if}

                        <div class="metrics">
                            <div><span>DYSTANS</span><b>{km(rider.distance_m)}</b></div>
                            <div>
                                <span>TĘTNO</span><b>{rider.heart_rate_bpm || "—"}{rider.heart_rate_bpm ? " bpm" : ""}</b>
                            </div>
                            <div><span>PRZEWYŻSZENIE</span><b>{Math.round(rider.elevation_gain_m)} m</b></div>
                            <div><span>WYSOKOŚĆ</span><b>{Math.round(rider.altitude_m)} m</b></div>
                        </div>

                        <footer>
                            {ago(rider.secondsSinceUpdate)} · GPS ±{Math.round(rider.accuracy_m)} m
                            {#if rider.heading_deg > 0}· kierunek {compass(rider.heading_deg)}{/if}
                        </footer>
                    </button>
                {/each}
            {:else}
                <div class="waiting">
                    <div class="pulse"></div>
                    <strong>Czekam na pierwszą pozycję</strong>
                    <span>
                        Mapa już działa. Zawodnicy pojawią się tutaj, gdy tylko ich
                        telefon wyśle pierwsze dane.
                    </span>
                </div>
            {/if}
        </div>

        <p class="rail-foot">Live Ride · własne śledzenie jazdy na żywo</p>
    </section>

    <section class="sheet" class:open={sheetOpen}>
        <button
            class="handle"
            onclick={() => (sheetOpen = !sheetOpen)}
            aria-label={sheetOpen ? "Zwiń listę zawodników" : "Rozwiń listę zawodników"}
        >
            <i></i>
        </button>

        <div class="sheet-summary">
            <div><span>ZAWODNICY</span><b>{riders.length}</b></div>
            <div><span>CZAS</span><b>{elapsed(snapshot?.started_at ?? "")}</b></div>
            <div><span>TRASA</span><b>{route?.distance_m ? km(route.distance_m, 1) : "—"}</b></div>
            <div class="sheet-status" class:ended><i></i>{ended ? "ZAKOŃCZONA" : "NA ŻYWO"}</div>
        </div>

        <div class="sheet-riders">
            {#each riders as rider (rider.id)}
                <button
                    class:stale={!rider.fresh}
                    class:selected={selectedRiderId === rider.id}
                    style={`--rider-colour:${rider.colour}`}
                    onclick={() => focusRider(rider)}
                >
                    <div class="avatar">{initials(rider.display_name)}</div>
                    <div class="who">
                        <strong>{rider.display_name}</strong>
                        <span>
                            {rider.speed_kmh.toFixed(1)} km/h · {km(rider.distance_m)}
                            {#if rider.progress !== null}· {Math.round(rider.progress * 100)}%{/if}
                        </span>
                    </div>
                    {#if rider.heart_rate_bpm}
                        <b class="hr">♥ {rider.heart_rate_bpm}</b>
                    {/if}
                </button>
            {:else}
                <p class="sheet-empty">Czekam na pierwszą pozycję…</p>
            {/each}
        </div>
    </section>
</main>

<style>
    :global(html),
    :global(body) {
        margin: 0;
        width: 100%;
        height: 100%;
        overflow: hidden;
        background: #07101a;
    }
    :global(body) {
        font-family:
            Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }

    :global(.lr-marker) {
        --rider-colour: #00bfd8;
        appearance: none;
        position: relative;
        width: 44px;
        height: 44px;
        padding: 0;
        display: grid;
        place-items: center;
        border: 3px solid var(--rider-colour);
        border-radius: 50%;
        background: #07101a;
        color: #fff;
        font-size: 15px;
        font-weight: 800;
        cursor: pointer;
        box-shadow:
            0 0 0 6px color-mix(in srgb, var(--rider-colour) 18%, transparent),
            0 8px 22px rgb(0 0 0 / 0.35);
        transition: transform 0.16s ease, opacity 0.16s ease;
    }
    :global(.lr-marker i) {
        position: absolute;
        bottom: -7px;
        width: 9px;
        height: 9px;
        border-radius: 2px;
        background: var(--rider-colour);
        transform: rotate(45deg);
    }
    :global(.lr-marker.stale) {
        opacity: 0.4;
        filter: grayscale(1);
    }
    :global(.lr-marker.selected) {
        transform: scale(1.14);
    }

    .viewer {
        position: relative;
        width: 100vw;
        height: 100dvh;
        overflow: hidden;
        color: #f3f8fc;
        background: #07101a;
    }
    .map {
        position: absolute;
        inset: 0;
        background: #dde6ed;
    }

    .topbar {
        position: absolute;
        z-index: 5;
        inset: 0 384px auto 0;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
        padding: 18px 20px;
        pointer-events: none;
        background: linear-gradient(180deg, rgb(7 16 26 / 0.8), transparent);
    }
    .brand {
        display: flex;
        align-items: center;
        gap: 12px;
        min-width: 0;
    }
    .mark {
        flex: none;
        width: 34px;
        height: 34px;
    }
    .brand-copy {
        display: grid;
        gap: 2px;
        min-width: 0;
    }
    .brand-copy span {
        font-size: 10px;
        font-weight: 900;
        letter-spacing: 0.24em;
        color: #6ceeff;
    }
    .brand-copy strong {
        max-width: min(56vw, 640px);
        overflow: hidden;
        white-space: nowrap;
        text-overflow: ellipsis;
        font-size: clamp(17px, 2.1vw, 26px);
        letter-spacing: -0.03em;
    }
    .top-actions {
        display: flex;
        align-items: center;
        gap: 8px;
        pointer-events: auto;
    }
    .ghost {
        width: 40px;
        height: 40px;
        display: grid;
        place-items: center;
        border: 1px solid rgb(255 255 255 / 0.16);
        border-radius: 8px;
        background: rgb(7 16 26 / 0.74);
        color: #fff;
        cursor: pointer;
        backdrop-filter: blur(12px);
    }
    .ghost svg {
        width: 20px;
        height: 20px;
    }
    .status {
        display: flex;
        align-items: center;
        gap: 8px;
        height: 40px;
        padding: 0 14px;
        border: 1px solid rgb(255 90 90 / 0.5);
        border-radius: 8px;
        background: rgb(7 16 26 / 0.78);
        color: #ff6b6b;
        font-size: 11px;
        font-weight: 900;
        letter-spacing: 0.12em;
        backdrop-filter: blur(12px);
    }
    .status i {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: currentColor;
        animation: pulse 1.6s ease-in-out infinite;
    }
    .status.ended {
        color: #9fb0bd;
        border-color: rgb(255 255 255 / 0.14);
    }
    .status.ended i {
        animation: none;
    }
    @keyframes pulse {
        50% {
            opacity: 0.3;
        }
    }

    .warning {
        position: absolute;
        z-index: 9;
        top: 84px;
        left: 20px;
        display: grid;
        gap: 4px;
        max-width: 520px;
        padding: 10px 13px;
        border-radius: 8px;
        background: rgb(160 38 32 / 0.95);
        color: #fff;
        font-size: 12px;
    }

    .rail {
        position: absolute;
        z-index: 6;
        inset: 0 0 0 auto;
        width: 384px;
        box-sizing: border-box;
        display: flex;
        flex-direction: column;
        gap: 14px;
        padding: 18px;
        background: rgb(7 16 26 / 0.96);
        border-left: 1px solid rgb(255 255 255 / 0.08);
        backdrop-filter: blur(18px);
    }
    .session {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 8px;
    }
    .session > div {
        display: grid;
        gap: 4px;
        padding: 11px 12px;
        border: 1px solid rgb(255 255 255 / 0.07);
        border-radius: 8px;
        background: #0d1a26;
    }
    .session span,
    .rail-head span,
    .metrics span,
    .sheet-summary span {
        font-size: 8.5px;
        font-weight: 900;
        letter-spacing: 0.13em;
        color: #7f919f;
    }
    .session b {
        font-size: 15px;
        font-variant-numeric: tabular-nums;
    }
    .rail-head {
        display: flex;
        align-items: flex-end;
        justify-content: space-between;
        padding: 2px 2px 0;
    }
    .rail-head > div {
        display: flex;
        align-items: baseline;
        gap: 8px;
    }
    .rail-head strong {
        font-size: 24px;
        color: #00bfd8;
    }
    .rail-head em {
        font-style: normal;
        font-size: 10px;
        font-weight: 800;
        color: #59e9a5;
    }
    .rail-head small {
        font-size: 9px;
        color: #62727f;
    }
    .rider-list {
        min-height: 0;
        overflow-y: auto;
        display: grid;
        align-content: start;
        gap: 10px;
    }
    .rider {
        --rider-colour: #00bfd8;
        width: 100%;
        appearance: none;
        text-align: left;
        padding: 14px;
        border: 1px solid rgb(255 255 255 / 0.08);
        border-left: 3px solid var(--rider-colour);
        border-radius: 8px;
        background: #0c1824;
        color: inherit;
        cursor: pointer;
        transition: background 0.16s ease, border-color 0.16s ease;
    }
    .rider:hover,
    .rider.selected {
        background: #112230;
        border-color: var(--rider-colour);
    }
    .rider.stale {
        opacity: 0.5;
    }
    .rider-top {
        display: flex;
        align-items: center;
        gap: 10px;
    }
    .avatar {
        flex: none;
        width: 38px;
        height: 38px;
        display: grid;
        place-items: center;
        border-radius: 10px;
        background: var(--rider-colour);
        color: #05121a;
        font-size: 14px;
        font-weight: 900;
    }
    .who {
        flex: 1;
        min-width: 0;
        display: grid;
        gap: 2px;
    }
    .who strong {
        overflow: hidden;
        white-space: nowrap;
        text-overflow: ellipsis;
        font-size: 14.5px;
    }
    .who span {
        font-size: 8.5px;
        font-weight: 900;
        letter-spacing: 0.1em;
        color: #59e9a5;
    }
    .stale .who span {
        color: #c08a8a;
    }
    .speed {
        text-align: right;
        line-height: 1;
    }
    .speed b {
        font-size: 25px;
        letter-spacing: -0.04em;
        font-variant-numeric: tabular-nums;
    }
    .speed span {
        display: block;
        margin-top: 3px;
        font-size: 8.5px;
        color: #8496a3;
    }
    .progress {
        margin-top: 12px;
        display: grid;
        gap: 5px;
    }
    .bar {
        height: 5px;
        border-radius: 3px;
        background: #0a141d;
        overflow: hidden;
    }
    .bar i {
        display: block;
        height: 100%;
        background: var(--rider-colour);
    }
    .progress small {
        font-size: 9.5px;
        color: #8496a3;
    }
    .progress .off {
        color: #ff8080;
    }
    .metrics {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 7px;
        margin-top: 12px;
    }
    .metrics > div {
        min-width: 0;
        display: grid;
        gap: 3px;
        padding: 9px;
        border-radius: 6px;
        background: #08131c;
    }
    .metrics b {
        font-size: 13px;
        overflow: hidden;
        white-space: nowrap;
        text-overflow: ellipsis;
        font-variant-numeric: tabular-nums;
    }
    .rider footer {
        margin-top: 10px;
        font-size: 9px;
        color: #667885;
    }
    .waiting {
        display: grid;
        justify-items: center;
        gap: 9px;
        padding: 36px 18px;
        text-align: center;
        color: #8c9ba7;
    }
    .waiting strong {
        color: #fff;
        font-size: 14px;
    }
    .waiting span {
        font-size: 11.5px;
        line-height: 1.5;
    }
    .pulse {
        width: 12px;
        height: 12px;
        border-radius: 50%;
        background: #00bfd8;
        box-shadow: 0 0 0 8px rgb(0 191 216 / 0.12);
        animation: pulse 1.6s ease-in-out infinite;
    }
    .rail-foot {
        margin: 0;
        font-size: 9px;
        letter-spacing: 0.08em;
        color: #4d5e6b;
        text-align: center;
    }

    .sheet {
        display: none;
    }

    @media (max-width: 900px) {
        .topbar {
            inset: 0 0 auto 0;
            padding: 14px 16px;
        }
        .rail {
            display: none;
        }
        .warning {
            top: 72px;
            left: 12px;
            right: 12px;
            max-width: none;
        }
        .sheet {
            position: absolute;
            z-index: 7;
            left: 0;
            right: 0;
            bottom: 0;
            display: block;
            max-height: 78dvh;
            padding: 0 12px calc(12px + env(safe-area-inset-bottom));
            border-top: 1px solid rgb(255 255 255 / 0.09);
            border-radius: 16px 16px 0 0;
            background: rgb(7 16 26 / 0.97);
            backdrop-filter: blur(18px);
            overflow: hidden;
        }
        .handle {
            display: grid;
            place-items: center;
            width: 100%;
            height: 26px;
            padding: 0;
            border: 0;
            background: none;
            cursor: pointer;
        }
        .handle i {
            width: 42px;
            height: 4px;
            border-radius: 2px;
            background: rgb(255 255 255 / 0.28);
        }
        .sheet-summary {
            display: flex;
            align-items: center;
            gap: 18px;
            padding: 2px 6px 12px;
        }
        .sheet-summary > div {
            display: grid;
            gap: 3px;
        }
        .sheet-summary b {
            font-size: 15px;
            font-variant-numeric: tabular-nums;
        }
        .sheet-status {
            margin-left: auto;
            display: flex;
            align-items: center;
            gap: 6px;
            padding: 5px 9px;
            border: 1px solid rgb(255 90 90 / 0.45);
            border-radius: 6px;
            color: #ff6b6b;
            font-size: 9.5px;
            font-weight: 900;
            letter-spacing: 0.1em;
        }
        .sheet-status i {
            width: 6px;
            height: 6px;
            border-radius: 50%;
            background: currentColor;
        }
        .sheet-status.ended {
            color: #9fb0bd;
            border-color: rgb(255 255 255 / 0.14);
        }
        .sheet-riders {
            display: grid;
            gap: 8px;
            max-height: 0;
            overflow-y: auto;
            transition: max-height 0.22s ease;
        }
        .sheet.open .sheet-riders {
            max-height: 56dvh;
            padding-bottom: 8px;
        }
        .sheet-riders button {
            --rider-colour: #00bfd8;
            display: flex;
            align-items: center;
            gap: 10px;
            width: 100%;
            padding: 10px;
            border: 1px solid rgb(255 255 255 / 0.08);
            border-left: 3px solid var(--rider-colour);
            border-radius: 8px;
            background: #0c1824;
            color: inherit;
            text-align: left;
            cursor: pointer;
        }
        .sheet-riders button.selected {
            border-color: var(--rider-colour);
            background: #112230;
        }
        .sheet-riders button.stale {
            opacity: 0.5;
        }
        .sheet-riders .avatar {
            width: 34px;
            height: 34px;
            font-size: 13px;
        }
        .sheet-riders .who span {
            color: #8496a3;
            font-size: 10px;
            font-weight: 600;
            letter-spacing: 0;
        }
        .hr {
            margin-left: auto;
            color: #ff8080;
            font-size: 13px;
            font-variant-numeric: tabular-nums;
        }
        .sheet-empty {
            margin: 0 0 10px;
            color: #8c9ba7;
            font-size: 12px;
            text-align: center;
        }
    }
</style>
