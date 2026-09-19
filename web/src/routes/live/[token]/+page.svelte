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
    let mapError = $state("");
    let map: M.Map | null = null;
    let routeCoordinates: [number, number][] = [];
    let firstFit = true;
    let selectedRiderId = $state<string | null>(null);
    const markers = new Map<string, M.Marker>();

    const km = (m: number) => `${(m / 1000).toFixed(m >= 10000 ? 1 : 2)} km`;
    const fresh = (date: string) => !!date && Date.now() - new Date(date).getTime() < 20_000;
    const clock = (date: string) => date ? new Date(date).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) : "—";
    const elapsed = (date: string) => {
        if (!date) return "—";
        const seconds = Math.max(0, Math.floor((Date.now() - new Date(date).getTime()) / 1000));
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
    };

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

    function validRiderPosition(rider: Rider) {
        return Number.isFinite(rider.latitude) && Number.isFinite(rider.longitude) && !(rider.latitude === 0 && rider.longitude === 0);
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
            paint: { "line-color": "#00bfd8", "line-width": 6, "line-opacity": 1 },
        });
    }

    function fitAll(force = false) {
        if (!map || (!firstFit && !force)) return;
        const bounds = new M.LngLatBounds();
        for (const p of routeCoordinates) bounds.extend(p);
        for (const rider of snapshot?.riders ?? []) {
            if (validRiderPosition(rider)) bounds.extend([rider.longitude, rider.latitude]);
        }
        if (!bounds.isEmpty()) {
            map.fitBounds(bounds, {
                padding: { top: 100, right: 80, bottom: 180, left: 80 },
                maxZoom: 15,
                duration: force ? 550 : 0,
            });
            firstFit = false;
        }
    }

    function createMarkerElement(rider: Rider) {
        const root = document.createElement("button");
        root.type = "button";
        root.className = "lr-rider-marker";
        root.setAttribute("aria-label", rider.display_name);
        root.innerHTML = `<span>${rider.display_name.slice(0, 1).toUpperCase()}</span><i></i>`;
        root.onclick = () => {
            selectedRiderId = rider.id;
            if (map && validRiderPosition(rider)) {
                map.easeTo({ center: [rider.longitude, rider.latitude], zoom: Math.max(map.getZoom(), 14), duration: 450 });
            }
        };
        return root;
    }

    function syncMarkers() {
        if (!map || !snapshot) return;
        const alive = new Set<string>();
        for (const rider of snapshot.riders) {
            if (!validRiderPosition(rider)) continue;
            alive.add(rider.id);
            let marker = markers.get(rider.id);
            if (!marker) {
                marker = new M.Marker({ element: createMarkerElement(rider), anchor: "center" })
                    .setLngLat([rider.longitude, rider.latitude])
                    .addTo(map);
                markers.set(rider.id, marker);
            } else {
                marker.setLngLat([rider.longitude, rider.latitude]);
            }
            const el = marker.getElement();
            el.classList.toggle("stale", !fresh(rider.last_seen_at));
            el.classList.toggle("selected", selectedRiderId === rider.id);
        }
        for (const [id, marker] of markers) {
            if (!alive.has(id)) {
                marker.remove();
                markers.delete(id);
            }
        }
        fitAll();
    }

    async function loadRoute() {
        try {
            const response = await fetch(`/api/v1/live/${encodeURIComponent(page.params.token!)}/route`, { cache: "no-store" });
            if (!response.ok) return;
            route = await response.json() as RouteSnapshot;
            routeCoordinates = route.polyline ? decodePolyline(route.polyline) : [];
            syncRoute();
            fitAll();
        } catch {
            // A LIVE without a saved route is still valid; rider markers continue working.
        }
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

    async function initMap() {
        try {
            const styleResponse = await fetch('/api/v1/map/style?theme=liberty', { cache: 'force-cache' });
            if (!styleResponse.ok) throw new Error(`style HTTP ${styleResponse.status}`);
            const style = await styleResponse.json() as M.StyleSpecification;
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
            map.on("error", (event) => {
                console.warn('Live Ride map error', event.error);
            });
        } catch (e) {
            mapError = e instanceof Error ? e.message : 'Nie udało się uruchomić mapy';
        }
    }

    onMount(() => {
        void initMap();
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
    <meta name="theme-color" content="#071018" />
    <meta name="description" content="Live Ride — śledzenie przejazdu na żywo" />
    <link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 64 64%22><rect width=%2264%22 height=%2264%22 rx=%2218%22 fill=%22%23070b10%22/><path d=%22M19 43 32 14l13 29-13-7z%22 fill=%22%2300bfd8%22/></svg>" />
</svelte:head>

<main class="viewer">
    <div id="live-map" class="map"></div>

    <header class="brandbar">
        <div class="brand">
            <div class="mark">➤</div>
            <div class="brand-copy">
                <span>LIVE RIDE</span>
                <strong>{snapshot?.title ?? "Ładowanie przejazdu…"}</strong>
            </div>
        </div>
        <div class="top-actions">
            <button class="map-fit" onclick={() => fitAll(true)} title="Pokaż wszystkich">⌖</button>
            <div class:ended={snapshot?.status === "ended"} class="status">
                <i></i>{snapshot?.status === "ended" ? "ZAKOŃCZONY" : "LIVE"}
            </div>
        </div>
    </header>

    {#if error || mapError}
        <div class="warning">
            {#if mapError}<span>Mapa: {mapError}</span>{/if}
            {#if error}<span>Dane LIVE: {error}</span>{/if}
        </div>
    {/if}

    <section class="desktop-telemetry">
        <div class="session-row">
            <div><span>CZAS</span><b>{elapsed(snapshot?.started_at ?? "")}</b></div>
            <div><span>TRASA</span><b>{route?.distance_m ? km(route.distance_m) : "—"}</b></div>
            <div><span>START</span><b>{snapshot?.started_at ? clock(snapshot.started_at) : "—"}</b></div>
        </div>

        <div class="riders-head">
            <div><span>UCZESTNICY</span><strong>{snapshot?.riders.length ?? 0}</strong></div>
            <small>odświeżanie co 3 s</small>
        </div>

        <div class="riders-list">
            {#if snapshot?.riders.length}
                {#each snapshot.riders as rider (rider.id)}
                    <button
                        class:stale={!fresh(rider.last_seen_at)}
                        class:selected={selectedRiderId === rider.id}
                        class="rider-card"
                        onclick={() => {
                            selectedRiderId = rider.id;
                            if (map && validRiderPosition(rider)) map.easeTo({ center: [rider.longitude, rider.latitude], zoom: 15, duration: 450 });
                        }}
                    >
                        <div class="rider-line">
                            <div class="avatar">{rider.display_name.slice(0, 1).toUpperCase()}</div>
                            <div class="rider-name"><strong>{rider.display_name}</strong><span>{fresh(rider.last_seen_at) ? "AKTYWNY" : "BRAK SYGNAŁU"}</span></div>
                            <div class="speed"><b>{rider.speed_kmh.toFixed(1)}</b><span>km/h</span></div>
                        </div>
                        <div class="metrics">
                            <div><span>HR</span><b>{rider.heart_rate_bpm || "—"}{rider.heart_rate_bpm ? " bpm" : ""}</b></div>
                            <div><span>DYSTANS</span><b>{km(rider.distance_m)}</b></div>
                            <div><span>W GÓRĘ</span><b>+{Math.round(rider.elevation_gain_m)} m</b></div>
                            <div><span>WYS.</span><b>{Math.round(rider.altitude_m)} m</b></div>
                        </div>
                        <footer>GPS ±{Math.round(rider.accuracy_m)} m · {clock(rider.last_seen_at)}</footer>
                    </button>
                {/each}
            {:else}
                <div class="waiting"><div class="pulse"></div><strong>Czekam na pierwszą pozycję</strong><span>Mapa działa niezależnie; zawodnik pojawi się po pierwszej telemetrii.</span></div>
            {/if}
        </div>
    </section>

    <section class="mobile-sheet">
        <div class="handle"></div>
        <div class="mobile-summary">
            <div><span>LIVE</span><b>{snapshot?.riders.length ?? 0} os.</b></div>
            <div><span>CZAS</span><b>{elapsed(snapshot?.started_at ?? "")}</b></div>
            <div><span>TRASA</span><b>{route?.distance_m ? km(route.distance_m) : "—"}</b></div>
        </div>
        <div class="mobile-riders">
            {#each snapshot?.riders ?? [] as rider (rider.id)}
                <button onclick={() => {
                    selectedRiderId = rider.id;
                    if (map && validRiderPosition(rider)) map.easeTo({ center: [rider.longitude, rider.latitude], zoom: 15, duration: 450 });
                }}>
                    <div class="avatar">{rider.display_name.slice(0, 1).toUpperCase()}</div>
                    <div><strong>{rider.display_name}</strong><span>{rider.speed_kmh.toFixed(1)} km/h</span></div>
                    <b class="mobile-hr">♥ {rider.heart_rate_bpm || "—"}</b>
                </button>
            {/each}
        </div>
    </section>
</main>

<style>
    :global(html), :global(body) { margin: 0; width: 100%; height: 100%; overflow: hidden; background: #071018; }
    :global(body) { font-family: Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    :global(.lr-rider-marker) { appearance: none; border: 4px solid #00bfd8; padding: 0; position: relative; width: 46px; height: 46px; border-radius: 50%; display: grid; place-items: center; background: #071018; color: white; box-shadow: 0 0 0 7px rgb(0 191 216 / .16), 0 8px 25px rgb(0 0 0 / .38); font-size: 17px; font-weight: 900; cursor: pointer; transition: .18s ease; }
    :global(.lr-rider-marker i) { position: absolute; bottom: -8px; width: 10px; height: 10px; background: #00bfd8; transform: rotate(45deg); border-radius: 2px; }
    :global(.lr-rider-marker.stale) { opacity: .42; filter: grayscale(1); }
    :global(.lr-rider-marker.selected) { transform: scale(1.16); box-shadow: 0 0 0 9px rgb(0 191 216 / .24), 0 12px 32px rgb(0 0 0 / .46); }
    .viewer { position: relative; width: 100vw; height: 100dvh; overflow: hidden; background: #071018; color: #f8fbff; }
    .map { position: absolute; inset: 0; background: #dfe8ee; }
    .brandbar { position: absolute; z-index: 5; top: 0; left: 0; right: 390px; padding: 20px 22px; display: flex; align-items: center; justify-content: space-between; gap: 16px; pointer-events: none; background: linear-gradient(180deg, rgb(7 16 24 / .78), transparent); }
    .brand { min-width: 0; display: flex; align-items: center; gap: 12px; }
    .mark { flex: none; width: 44px; height: 44px; border-radius: 14px; display: grid; place-items: center; color: #061017; background: #00bfd8; font-weight: 1000; font-size: 23px; transform: rotate(-45deg); box-shadow: 0 9px 26px rgb(0 191 216 / .2); }
    .brand-copy { min-width: 0; display: grid; gap: 3px; }
    .brand-copy span { color: #6ceeff; font-size: 10px; letter-spacing: .22em; font-weight: 950; }
    .brand-copy strong { max-width: min(55vw, 700px); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: clamp(18px, 2.2vw, 28px); letter-spacing: -.04em; }
    .top-actions { display: flex; align-items: center; gap: 9px; pointer-events: auto; }
    .map-fit { width: 42px; height: 42px; border: 1px solid rgb(255 255 255 / .14); border-radius: 13px; background: rgb(7 16 24 / .72); color: white; backdrop-filter: blur(14px); font-size: 23px; cursor: pointer; }
    .status { height: 42px; padding: 0 14px; border-radius: 13px; display: flex; align-items: center; gap: 8px; background: rgb(7 16 24 / .78); border: 1px solid rgb(70 255 165 / .28); color: #67f7b5; backdrop-filter: blur(14px); font-size: 11px; font-weight: 950; letter-spacing: .1em; }
    .status i { width: 8px; height: 8px; border-radius: 50%; background: currentColor; box-shadow: 0 0 0 5px rgb(103 247 181 / .12); }
    .status.ended { color: #9eabb7; border-color: rgb(255 255 255 / .13); }
    .warning { position: absolute; z-index: 9; top: 86px; left: 22px; display: grid; gap: 4px; max-width: 520px; padding: 10px 13px; border-radius: 12px; background: rgb(139 38 38 / .94); color: white; font-size: 12px; box-shadow: 0 10px 25px rgb(0 0 0 / .25); }
    .desktop-telemetry { position: absolute; z-index: 6; top: 0; right: 0; bottom: 0; width: 365px; box-sizing: border-box; padding: 18px; display: flex; flex-direction: column; gap: 15px; background: rgb(7 16 24 / .95); border-left: 1px solid rgb(255 255 255 / .08); backdrop-filter: blur(20px); box-shadow: -18px 0 45px rgb(0 0 0 / .16); }
    .session-row { display: grid; grid-template-columns: repeat(3, 1fr); gap: 7px; }
    .session-row > div { padding: 11px 10px; border-radius: 13px; background: #0f1b25; border: 1px solid rgb(255 255 255 / .06); display: grid; gap: 3px; }
    .session-row span, .riders-head span, .metrics span { font-size: 8px; font-weight: 900; letter-spacing: .12em; color: #7d8e9c; }
    .session-row b { font-size: 14px; }
    .riders-head { display: flex; align-items: end; justify-content: space-between; padding: 1px 3px 0; }
    .riders-head > div { display: flex; align-items: baseline; gap: 8px; }
    .riders-head strong { font-size: 25px; color: #00bfd8; }
    .riders-head small { color: #60717e; font-size: 9px; }
    .riders-list { min-height: 0; overflow-y: auto; display: grid; align-content: start; gap: 9px; padding-right: 2px; }
    .rider-card { width: 100%; appearance: none; text-align: left; border: 1px solid rgb(255 255 255 / .075); border-radius: 17px; padding: 14px; color: inherit; background: #0d1821; cursor: pointer; transition: border-color .16s ease, background .16s ease, opacity .16s ease; }
    .rider-card:hover, .rider-card.selected { background: #10212d; border-color: rgb(0 191 216 / .5); }
    .rider-card.stale { opacity: .46; }
    .rider-line { display: flex; align-items: center; gap: 10px; }
    .avatar { flex: none; width: 39px; height: 39px; border-radius: 50%; background: #00bfd8; color: #061017; display: grid; place-items: center; font-size: 15px; font-weight: 950; }
    .rider-name { min-width: 0; display: grid; gap: 2px; flex: 1; }
    .rider-name strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 14px; }
    .rider-name span { font-size: 8px; font-weight: 900; letter-spacing: .09em; color: #59e9a5; }
    .stale .rider-name span { color: #9c6970; }
    .speed { text-align: right; line-height: 1; }
    .speed b { font-size: 26px; letter-spacing: -.05em; }
    .speed span { display: block; margin-top: 3px; font-size: 8px; color: #81919d; }
    .metrics { display: grid; grid-template-columns: repeat(2, 1fr); gap: 7px; margin-top: 12px; }
    .metrics > div { min-width: 0; padding: 9px; border-radius: 11px; background: #08121a; display: grid; gap: 3px; }
    .metrics b { font-size: 13px; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
    .rider-card footer { margin-top: 10px; color: #647582; font-size: 9px; }
    .waiting { padding: 35px 18px; display: grid; justify-items: center; text-align: center; gap: 8px; color: #8b9aa6; }
    .waiting strong { color: white; font-size: 14px; }
    .waiting span { font-size: 11px; line-height: 1.45; }
    .pulse { width: 12px; height: 12px; border-radius: 50%; background: #00bfd8; box-shadow: 0 0 0 8px rgb(0 191 216 / .12); }
    .mobile-sheet { display: none; }
    @media (max-width: 820px) {
        .brandbar { right: 0; padding: max(12px, env(safe-area-inset-top)) 14px 20px; }
        .brand-copy strong { max-width: 53vw; font-size: 17px; }
        .mark { width: 38px; height: 38px; border-radius: 12px; font-size: 20px; }
        .map-fit { display: none; }
        .status { height: 36px; padding: 0 10px; font-size: 9px; }
        .desktop-telemetry { display: none; }
        .warning { top: 74px; left: 12px; right: 12px; max-width: none; }
        :global(.maplibregl-ctrl-top-right) { top: 72px; right: 5px; }
        :global(.maplibregl-ctrl-bottom-right) { bottom: 152px; }
        .mobile-sheet { position: absolute; z-index: 7; left: 8px; right: 8px; bottom: max(8px, env(safe-area-inset-bottom)); display: block; padding: 6px 12px 11px; border-radius: 20px; background: rgb(7 16 24 / .94); border: 1px solid rgb(255 255 255 / .1); backdrop-filter: blur(20px); box-shadow: 0 15px 45px rgb(0 0 0 / .38); }
        .handle { width: 34px; height: 4px; border-radius: 999px; background: rgb(255 255 255 / .24); margin: 0 auto 7px; }
        .mobile-summary { display: grid; grid-template-columns: repeat(3, 1fr); gap: 5px; }
        .mobile-summary > div { min-width: 0; padding: 6px 8px; display: grid; gap: 1px; text-align: center; }
        .mobile-summary span { color: #72838f; font-size: 7px; font-weight: 900; letter-spacing: .12em; }
        .mobile-summary b { font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .mobile-riders { display: flex; gap: 7px; overflow-x: auto; padding-top: 7px; scrollbar-width: none; }
        .mobile-riders::-webkit-scrollbar { display: none; }
        .mobile-riders button { flex: 0 0 auto; min-width: 205px; appearance: none; border: 1px solid rgb(255 255 255 / .08); border-radius: 14px; padding: 8px 10px; display: flex; align-items: center; gap: 9px; background: #0c1821; color: white; text-align: left; }
        .mobile-riders button > div:nth-child(2) { min-width: 0; flex: 1; display: grid; gap: 2px; }
        .mobile-riders strong { font-size: 12px; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
        .mobile-riders span { color: #82929e; font-size: 9px; }
        .mobile-riders .avatar { width: 31px; height: 31px; font-size: 12px; }
        .mobile-hr { color: #ff7380; font-size: 11px; }
    }
</style>
