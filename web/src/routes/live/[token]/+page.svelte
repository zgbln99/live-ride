<script lang="ts">
    import { onMount } from "svelte";
    import * as M from "maplibre-gl";
    import "maplibre-gl/dist/maplibre-gl.css";
    import { ensureMapLibreWorker } from "$lib/util/maplibre_worker";
    import { decodePolyline } from "$lib/util/polyline_util";
    import {
        RIDER_COLOURS,
        ago,
        clock,
        compass,
        cumulativeDistances,
        distance as fmtDistance,
        duration as fmtDuration,
        elevationAt,
        hasPosition,
        initials,
        liveOnly,
        nextClimb,
        num,
        projectOnRoute,
        relativeGap,
        riderStatus,
        routeProgress,
        type Climb,
        type LngLat,
        type Projection,
        type Rider,
        type RouteProgress,
        type RouteSnapshot,
        type Snapshot,
        type TrackSlice,
    } from "$lib/live/live_viewer";
    import type { PageData } from "./$types";

    let { data }: { data: PageData } = $props();

    /** Ile czekamy między migawkami, gdy karta jest widoczna. */
    const REFRESH_MS = 3000;
    /** …i gdy przeglądarka odłożyła kartę w tło. */
    const BACKGROUND_REFRESH_MS = 30000;
    /** Ślad rośnie wolniej niż pozycja, więc dociągamy go rzadziej. */
    const TRACK_REFRESH_MS = 9000;

    type RiderView = Rider & {
        colour: string;
        status: ReturnType<typeof riderStatus>;
        ageSeconds: number;
        projection: Projection | null;
        progress: RouteProgress | null;
    };

    type Message = { id: string; body: string; sent_at: string; display_name: string };

    /**
     * Migawka narysowana na stronie.
     *
     * Do pierwszego udanego pobrania w przeglądarce obowiązuje ta z serwera,
     * więc znajomy widzi tytuł i stan już w pierwszej odpowiedzi, a nie po
     * rundzie do API.
     */
    let fetched = $state<Snapshot | null>(null);
    const snapshot = $derived(fetched ?? data.snapshot);
    let route = $state<RouteSnapshot | null>(null);
    let messages = $state<Message[]>([]);
    let error = $state("");
    let mapError = $state("");
    let selectedRiderId = $state<string | null>(null);
    let followSelected = $state(false);

    /**
     * Przesunięcie zegara widza względem serwera, w milisekundach.
     *
     * Wszystkie „ile temu" liczymy po czasie serwera. Telefon z zegarem
     * przestawionym o dziesięć minut inaczej pokazywałby całą grupę jako
     * offline mimo idealnie działającej telemetrii.
     */
    let clockSkewMs = $state(0);
    let now = $state(Date.now());

    let map: M.Map | null = null;
    let routeCoordinates: LngLat[] = [];
    let routeCumulative: number[] = [];
    let routeLengthMeters = $state(0);
    let styleReady = false;
    let firstFit = true;

    /** Przejechany ślad każdego zawodnika, dosypywany przyrostami. */
    const tracks = new Map<string, LngLat[]>();
    const trackCursors = new Map<string, string>();
    let trackVersion = $state(0);

    const markers = new Map<string, M.Marker>();
    /** Docelowa i aktualnie rysowana pozycja znacznika — do płynnego dojazdu. */
    const markerTargets = new Map<string, LngLat>();
    const markerPositions = new Map<string, LngLat>();
    let meetupMarker: M.Marker | null = null;
    let startMarker: M.Marker | null = null;
    let finishMarker: M.Marker | null = null;

    // ------------------------------------------------------------- pochodne

    const serverNow = $derived(now + clockSkewMs);
    const linkDead = $derived(
        snapshot?.status === "expired" || snapshot?.status === "disabled",
    );
    const ended = $derived(snapshot?.status === "ended");

    const riders = $derived.by<RiderView[]>(() => {
        const list = snapshot?.riders ?? [];
        return list
            .map((rider, index) => {
                const seen = rider.last_seen_at ? new Date(rider.last_seen_at).getTime() : NaN;
                const ageSeconds = Number.isNaN(seen)
                    ? Number.POSITIVE_INFINITY
                    : Math.max(0, (serverNow - seen) / 1000);
                const projection = hasPosition(rider)
                    ? projectOnRoute(routeCoordinates, routeCumulative, rider.longitude!, rider.latitude!)
                    : null;
                return {
                    ...rider,
                    colour: RIDER_COLOURS[index % RIDER_COLOURS.length],
                    ageSeconds,
                    status: riderStatus(rider.state, ageSeconds),
                    projection,
                    progress: routeProgress(rider, projection, routeLengthMeters, now),
                };
            })
            .sort((a, b) => {
                const pa = a.progress?.alongMeters ?? null;
                const pb = b.progress?.alongMeters ?? null;
                if (pa !== null && pb !== null) return pb - pa;
                if (pa !== null) return -1;
                if (pb !== null) return 1;
                // Zawodnik, który nie udostępnia dystansu, trafia na koniec
                // listy zamiast na jej czoło z zerem.
                return (b.distance_m ?? -1) - (a.distance_m ?? -1);
            });
    });

    const leader = $derived(riders[0] ?? null);
    const selected = $derived(riders.find((rider) => rider.id === selectedRiderId) ?? riders[0] ?? null);
    const liveCount = $derived(riders.filter((rider) => rider.status.tone === "live").length);
    const isGroup = $derived(riders.length > 1);

    /**
     * Prędkość, którą wolno pokazać jako „teraz".
     *
     * Zawodnik bez sygnału nie jedzie 31 km/h — jechał tyle wtedy, gdy ostatni
     * raz było go słychać. Dystans i czas zostają, bo są narastające.
     */
    const liveSpeed = $derived(
        selected ? liveOnly(selected.speed_kmh, selected.status.tone) : undefined,
    );

    const climb = $derived.by(() => {
        const along = selected?.progress?.alongMeters;
        if (along === undefined) return null;
        return nextClimb(route?.climbs, along);
    });

    /** Czas od startu — zatrzymany na mecie, a nie tykający w nieskończoność. */
    const elapsedSeconds = $derived.by(() => {
        const startedAt = snapshot?.started_at;
        if (!startedAt) return undefined;
        const started = new Date(startedAt).getTime();
        if (Number.isNaN(started)) return undefined;
        const endedAt = snapshot?.ended_at ? new Date(snapshot.ended_at).getTime() : NaN;
        const reference = Number.isNaN(endedAt) ? serverNow : endedAt;
        return Math.max(0, (reference - started) / 1000);
    });

    const summaryRider = $derived.by(() => {
        const rows = snapshot?.summary?.riders ?? [];
        return rows.find((row) => row.id === selected?.id) ?? rows[0] ?? null;
    });

    /** Ścieżka SVG profilu wysokości plus znacznik pozycji. */
    const profile = $derived.by(() => {
        const points = route?.elevation_profile ?? [];
        if (points.length < 2) return null;
        const width = 100;
        const height = 34;
        const total = points[points.length - 1].d || 1;
        let min = Infinity;
        let max = -Infinity;
        for (const point of points) {
            if (point.e < min) min = point.e;
            if (point.e > max) max = point.e;
        }
        const span = Math.max(20, max - min);
        const x = (d: number) => (d / total) * width;
        const y = (e: number) => height - ((e - min) / span) * (height - 3) - 1.5;

        const line = points.map((point, i) => `${i ? "L" : "M"}${x(point.d).toFixed(2)} ${y(point.e).toFixed(2)}`).join(" ");
        const area = `${line} L${width} ${height} L0 ${height} Z`;

        const along = selected?.progress?.alongMeters ?? null;
        const here = along === null ? null : elevationAt(points, along);
        return {
            line,
            area,
            min,
            max,
            marker: along === null || here === null ? null : { x: x(along), y: y(here), elevation: here },
        };
    });

    // -------------------------------------------------------------- mapa

    function riderTrack(id: string): LngLat[] {
        return tracks.get(id) ?? [];
    }

    function featureCollection(): GeoJSON.FeatureCollection<GeoJSON.LineString> {
        // Zależność od `trackVersion` jest celowa: to ona mówi Svelte, że ślad
        // się zmienił, bo sama mapa (`tracks`) nie jest reaktywna.
        void trackVersion;
        // Wybrany zawodnik rysuje się jako ostatni, czyli na wierzchu. W
        // grupie jadącej tą samą drogą ślady leżą jeden na drugim i bez tego
        // ten, którego akurat oglądamy, znikałby pod cudzym.
        const ordered = [
            ...riders.filter((rider) => rider.id !== selected?.id),
            ...riders.filter((rider) => rider.id === selected?.id),
        ];
        return {
            type: "FeatureCollection",
            features: ordered
                .map((rider) => ({
                    type: "Feature" as const,
                    properties: { colour: rider.colour },
                    geometry: { type: "LineString" as const, coordinates: riderTrack(rider.id) },
                }))
                .filter((feature) => feature.geometry.coordinates.length > 1),
        };
    }

    function syncRoute() {
        if (!map || !styleReady || routeCoordinates.length < 2) return;

        const data: GeoJSON.Feature<GeoJSON.LineString> = {
            type: "Feature",
            properties: {},
            geometry: { type: "LineString", coordinates: routeCoordinates },
        };
        const existing = map.getSource("live-route") as M.GeoJSONSource | undefined;
        if (existing) {
            existing.setData(data);
        } else {
            map.addSource("live-route", { type: "geojson", data });
            map.addLayer({
                id: "live-route-case",
                type: "line",
                source: "live-route",
                layout: { "line-cap": "round", "line-join": "round" },
                paint: { "line-color": "#04121c", "line-width": 11, "line-opacity": 0.55 },
            });
            // Plan jest przerywany i przygaszony, przejechane jest ciągłe i
            // mocne. Widz ma rozróżnić jedno od drugiego rzutem oka, bez legendy.
            map.addLayer({
                id: "live-route-line",
                type: "line",
                source: "live-route",
                layout: { "line-cap": "round", "line-join": "round" },
                paint: {
                    "line-color": "#9fd9e6",
                    "line-width": 5,
                    "line-opacity": 0.62,
                    "line-dasharray": [1.6, 1.5],
                },
            });
        }
        syncRouteEnds();
    }

    function pinElement(kind: "start" | "finish" | "meetup", label: string) {
        const element = document.createElement("div");
        element.className = `lr-pin lr-pin-${kind}`;
        element.title = label;
        element.innerHTML =
            kind === "meetup"
                ? '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 2a7 7 0 0 0-7 7c0 5.25 7 13 7 13s7-7.75 7-13a7 7 0 0 0-7-7m0 9.5A2.5 2.5 0 1 1 12 6.5a2.5 2.5 0 0 1 0 5"/></svg>'
                : `<span>${kind === "start" ? "START" : "META"}</span>`;
        return element;
    }

    function syncRouteEnds() {
        if (!map || routeCoordinates.length < 2) return;
        const start = routeCoordinates[0];
        const finish = routeCoordinates[routeCoordinates.length - 1];
        if (!startMarker) {
            startMarker = new M.Marker({ element: pinElement("start", "Start"), anchor: "bottom" })
                .setLngLat(start)
                .addTo(map);
        } else {
            startMarker.setLngLat(start);
        }
        if (!finishMarker) {
            finishMarker = new M.Marker({ element: pinElement("finish", "Meta"), anchor: "bottom" })
                .setLngLat(finish)
                .addTo(map);
        } else {
            finishMarker.setLngLat(finish);
        }
    }

    function syncTracks() {
        if (!map || !styleReady) return;
        const data = featureCollection();
        const existing = map.getSource("live-track") as M.GeoJSONSource | undefined;
        if (existing) {
            existing.setData(data);
            return;
        }
        map.addSource("live-track", { type: "geojson", data });
        map.addLayer({
            id: "live-track-case",
            type: "line",
            source: "live-track",
            layout: { "line-cap": "round", "line-join": "round" },
            paint: { "line-color": "#04121c", "line-width": 9, "line-opacity": 0.6 },
        });
        map.addLayer({
            id: "live-track-line",
            type: "line",
            source: "live-track",
            layout: { "line-cap": "round", "line-join": "round" },
            paint: { "line-color": ["get", "colour"], "line-width": 5 },
        });
    }

    function syncMeetup() {
        if (!map) return;
        const meetup = snapshot?.meetup;
        if (!meetup) {
            meetupMarker?.remove();
            meetupMarker = null;
            return;
        }
        if (!meetupMarker) {
            meetupMarker = new M.Marker({
                element: pinElement("meetup", meetup.label || "Punkt zbiórki"),
                anchor: "bottom",
            })
                .setLngLat([meetup.longitude, meetup.latitude])
                .addTo(map);
        } else {
            meetupMarker.setLngLat([meetup.longitude, meetup.latitude]);
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
        if (!map) return;
        const alive = new Set<string>();
        for (const rider of riders) {
            if (!hasPosition(rider)) continue;
            alive.add(rider.id);
            const target: LngLat = [rider.longitude!, rider.latitude!];
            let marker = markers.get(rider.id);
            if (!marker) {
                marker = new M.Marker({ element: markerElement(rider), anchor: "center" })
                    .setLngLat(target)
                    .addTo(map);
                markers.set(rider.id, marker);
                markerPositions.set(rider.id, target);
            }
            markerTargets.set(rider.id, target);

            const element = marker.getElement();
            element.style.setProperty("--rider-colour", rider.colour);
            const label = element.querySelector(".lr-marker-initials");
            if (label) label.textContent = initials(rider.display_name);
            element.classList.toggle("stale", rider.status.tone === "offline");
            element.classList.toggle("idle", rider.status.tone === "idle");
            element.classList.toggle("selected", selected?.id === rider.id);
        }
        for (const [id, marker] of markers) {
            if (alive.has(id)) continue;
            marker.remove();
            markers.delete(id);
            markerTargets.delete(id);
            markerPositions.delete(id);
        }
        syncMeetup();
        // Kolejność śladów zależy od wyboru zawodnika, więc warstwa musi
        // dostać nowe dane razem ze znacznikami.
        syncTracks();
        fitAll();
    }

    /**
     * Dociąganie znaczników do nowej pozycji.
     *
     * Telemetria przychodzi co trzy sekundy. Przestawiony znacznik skacze,
     * dociągany jedzie — a strona ma wyglądać jak przyrząd, nie jak odświeżana
     * lista.
     */
    function animateMarkers() {
        let changed = false;
        for (const [id, marker] of markers) {
            const target = markerTargets.get(id);
            if (!target) continue;
            const current = markerPositions.get(id) ?? target;
            const dx = target[0] - current[0];
            const dy = target[1] - current[1];
            if (Math.abs(dx) < 1e-7 && Math.abs(dy) < 1e-7) {
                if (current !== target) markerPositions.set(id, target);
                continue;
            }
            const next: LngLat = [current[0] + dx * 0.16, current[1] + dy * 0.16];
            markerPositions.set(id, next);
            marker.setLngLat(next);
            changed = true;
        }
        if (changed && followSelected && selected && markerPositions.has(selected.id)) {
            map?.panTo(markerPositions.get(selected.id)!, { duration: 0, animate: false });
        }
    }

    function fitAll(force = false) {
        if (!map || (!firstFit && !force)) return;
        // Pierwsze dopasowanie domyka dopiero geometria. Widok ustawiony na
        // same znaczniki, zanim doszła trasa, zostawiłby znajomego z wycinkiem
        // mapy zamiast z całym przejazdem.
        const hasGeometry = routeCoordinates.length > 1 || tracks.size > 0;
        const bounds = new M.LngLatBounds();
        for (const point of routeCoordinates) bounds.extend(point);
        for (const [, points] of tracks) for (const point of points) bounds.extend(point);
        for (const rider of snapshot?.riders ?? []) {
            if (hasPosition(rider)) bounds.extend([rider.longitude!, rider.latitude!]);
        }
        if (bounds.isEmpty()) return;
        map.fitBounds(bounds, {
            padding: fitPadding(),
            maxZoom: 15,
            duration: force ? 550 : 0,
        });
        if (hasGeometry) firstFit = false;
    }

    function fitPadding() {
        const wide = typeof window !== "undefined" && window.innerWidth > 900;
        return wide
            ? { top: 96, right: 72, bottom: 72, left: 72 }
            : { top: 90, right: 36, bottom: 56, left: 36 };
    }

    function focusRider(rider: RiderView) {
        selectedRiderId = rider.id;
        followSelected = true;
        if (map && hasPosition(rider)) {
            map.easeTo({
                center: [rider.longitude!, rider.latitude!],
                zoom: Math.max(map.getZoom(), 14.5),
                duration: 450,
            });
        }
    }

    // ------------------------------------------------------------ pobieranie

    function api(path: string) {
        return `/api/v1/live/${encodeURIComponent(data.token)}${path}`;
    }

    function applyServerTime(value: string | undefined) {
        if (!value) return;
        const server = new Date(value).getTime();
        if (Number.isNaN(server)) return;
        clockSkewMs = server - Date.now();
    }

    async function refresh() {
        try {
            const response = await fetch(api(""), { cache: "no-store" });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const next = (await response.json()) as Snapshot;
            fetched = next;
            applyServerTime(next.server_time);
            now = Date.now();
            error = "";
            syncMarkers();
        } catch (e) {
            // Utrata sieci u WIDZA nie zmienia stanu zawodnika. Zostawiamy
            // ostatnią znaną migawkę i mówimy wprost, że to my nie mamy
            // połączenia — zamiast ogłaszać, że ktoś zniknął.
            error = e instanceof Error ? e.message : "brak połączenia";
        }
    }

    async function loadRoute() {
        try {
            const response = await fetch(api("/route"), { cache: "no-store" });
            if (!response.ok) return;
            const next = (await response.json()) as RouteSnapshot;
            if (!next?.polyline) return;
            route = next;
            routeCoordinates = decodePolyline(next.polyline, next.precision ?? 6) as LngLat[];
            routeCumulative = cumulativeDistances(routeCoordinates);
            routeLengthMeters = routeCumulative[routeCumulative.length - 1] ?? 0;
            syncRoute();
            fitAll();
        } catch {
            // LIVE bez zaplanowanej trasy jest w pełni poprawny: znaczniki,
            // telemetria i mapa działają bez niej.
        }
    }

    async function loadTrack() {
        try {
            // Pierwsze pobranie bierze cały ślad, kolejne tylko przyrost.
            const cursor = [...trackCursors.values()].sort().at(-1);
            const response = await fetch(
                api(`/track${cursor ? `?since=${encodeURIComponent(cursor)}` : ""}`),
                { cache: "no-store" },
            );
            if (!response.ok) return;
            const payload = (await response.json()) as {
                tracks: TrackSlice[];
                incremental?: boolean;
            };
            let touched = false;
            for (const slice of payload.tracks ?? []) {
                const points = decodePolyline(slice.polyline, slice.precision ?? 6) as LngLat[];
                if (!points.length) continue;
                const existing = payload.incremental ? (tracks.get(slice.participant) ?? []) : [];
                tracks.set(slice.participant, existing.concat(points));
                if (slice.cursor) trackCursors.set(slice.participant, slice.cursor);
                touched = true;
            }
            if (touched) {
                trackVersion += 1;
                syncTracks();
                fitAll();
            }
        } catch {
            // Ślad jest ozdobą pozycji, nie warunkiem jej pokazania.
        }
    }

    async function loadMessages() {
        try {
            const response = await fetch(api("/messages"), { cache: "no-store" });
            if (!response.ok) return;
            const payload = (await response.json()) as { messages?: Message[] };
            messages = (payload.messages ?? []).slice(0, 5);
        } catch {
            // Wiadomości są dodatkiem — ich brak nie może zepsuć podglądu.
        }
    }

    // -------------------------------------------------------------- start

    async function initMap() {
        try {
            const styleResponse = await fetch("/api/v1/map/style?theme=liberty", {
                cache: "force-cache",
            });
            if (!styleResponse.ok) throw new Error(`HTTP ${styleResponse.status}`);
            const style = (await styleResponse.json()) as M.StyleSpecification;
            ensureMapLibreWorker();
            map = new M.Map({
                container: "live-map",
                style,
                center: [19.4, 52.1],
                zoom: 5.4,
                attributionControl: false,
                fadeDuration: 0,
            });
            // Lewy dolny róg, bo prawy górny zajmuje status „JEDZIE / POSTÓJ".
            map.addControl(new M.NavigationControl({ showCompass: false }), "bottom-left");
            map.addControl(new M.AttributionControl({ compact: true }), "bottom-right");
            map.on("load", () => {
                // Własna flaga zamiast `map.isStyleLoaded()`: to drugie wraca
                // do `false`, gdy tylko dołożymy źródło, więc warstwa śladu
                // dodawana zaraz po trasie nigdy nie przechodziła przez taki
                // warunek i przejechany odcinek się nie rysował.
                styleReady = true;
                syncRoute();
                syncTracks();
                syncMarkers();
                fitAll();
            });
            // Ręczne przesunięcie mapy zwalnia śledzenie, dokładnie jak w aplikacji.
            map.on("dragstart", () => (followSelected = false));
            map.on("error", (event) => console.warn("Live Ride map", event.error));
        } catch (e) {
            mapError = e instanceof Error ? e.message : "nie udało się uruchomić mapy";
        }
    }

    onMount(() => {
        document.documentElement.lang = "pl";
        applyServerTime(snapshot?.server_time);

        if (linkDead) {
            // Wygasły link nie ma czego odpytywać ani rysować.
            return;
        }

        void initMap();
        void loadRoute();
        void refresh();
        void loadTrack();
        void loadMessages();

        let snapshotTimer = 0;
        let trackTimer = 0;
        let messageTimer = 0;

        const schedule = () => {
            window.clearInterval(snapshotTimer);
            window.clearInterval(trackTimer);
            window.clearInterval(messageTimer);
            if (ended) return;
            // Karta w tle dostaje rzadsze odświeżanie: przeglądarka i tak
            // dławi timery, a bateria telefonu widza nie jest za darmo.
            const period = document.hidden ? BACKGROUND_REFRESH_MS : REFRESH_MS;
            snapshotTimer = window.setInterval(() => void refresh(), period);
            trackTimer = window.setInterval(
                () => void loadTrack(),
                document.hidden ? BACKGROUND_REFRESH_MS * 2 : TRACK_REFRESH_MS,
            );
            messageTimer = window.setInterval(() => void loadMessages(), 20000);
        };
        schedule();

        const onVisibility = () => {
            schedule();
            // Powrót do karty ma dać świeży stan natychmiast, a nie po
            // kolejnym tyknięciu odliczania.
            if (!document.hidden) {
                void refresh();
                void loadTrack();
            }
        };
        document.addEventListener("visibilitychange", onVisibility);

        // Osobny zegar, żeby „12 s temu" nie kłamało między migawkami.
        const tick = window.setInterval(() => (now = Date.now()), 1000);
        let frame = 0;
        const animate = () => {
            animateMarkers();
            frame = window.requestAnimationFrame(animate);
        };
        frame = window.requestAnimationFrame(animate);

        return () => {
            window.clearInterval(snapshotTimer);
            window.clearInterval(trackTimer);
            window.clearInterval(messageTimer);
            window.clearInterval(tick);
            window.cancelAnimationFrame(frame);
            document.removeEventListener("visibilitychange", onVisibility);
            for (const marker of markers.values()) marker.remove();
            markers.clear();
            map?.remove();
            map = null;
        };
    });

    // Gdy jazda się kończy, przestajemy odpytywać, ale raz jeszcze bierzemy
    // komplet: podsumowanie i ostatni fragment śladu.
    let finalised = false;
    $effect(() => {
        if (!ended || finalised) return;
        finalised = true;
        void loadTrack();
        setTimeout(() => fitAll(true), 400);
    });

    function climbLabel(value: Climb) {
        return `${fmtDistance(value.length_m)} · ${Math.round(value.gain_m)} m ↑ · średnio ${num(value.avg_gradient, 1)} %`;
    }
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

{#if linkDead}
    <main class="gone">
        <div class="gone-card">
            <svg class="mark" viewBox="0 0 64 64" aria-hidden="true">
                <path d="M10 52 33 9l9 18H23z" fill="#ffffff" />
                <path d="M30 56 58 12 49 56z" fill="#00bfd8" />
            </svg>
            <span class="eyebrow">LIVE RIDE</span>
            <h1>
                {snapshot?.status === "disabled"
                    ? "Udostępnianie zostało wyłączone"
                    : "Ten link już wygasł"}
            </h1>
            <p>
                {snapshot?.status === "disabled"
                    ? "Zawodnik zatrzymał udostępnianie tego przejazdu. Poproś go o nowy link, jeżeli chcesz go dalej śledzić."
                    : "Link do śledzenia na żywo działał przez ograniczony czas i właśnie się skończył. Poproś zawodnika o nowy."}
            </p>
            <small>Live Ride · własne śledzenie jazdy na żywo</small>
        </div>
    </main>
{:else}
    <main class="viewer" class:ended>
        <div class="stage">
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
                    <button class="ghost" onclick={() => fitAll(true)} title="Pokaż całość" aria-label="Pokaż całość">
                        <svg viewBox="0 0 24 24" aria-hidden="true"
                            ><path
                                fill="currentColor"
                                d="M4 9V4h5v2H6v3zm0 6v5h5v-2H6v-3zm16 0v5h-5v-2h3v-3zM20 9V4h-5v2h3v3zm-8 6a3 3 0 1 1 0-6 3 3 0 0 1 0 6"
                            /></svg
                        >
                    </button>
                    <div class="status" data-tone={ended ? "ended" : (selected?.status.tone ?? "offline")}>
                        <i></i>{ended ? "ZAKOŃCZONY" : (selected?.status.short ?? "ŁĄCZĘ…")}
                    </div>
                </div>
            </header>

            {#if error || mapError}
                <div class="warning" role="status">
                    {#if mapError}<span>Mapa: {mapError}</span>{/if}
                    {#if error}<span>Brak połączenia z serwerem — ponawiam co {REFRESH_MS / 1000} s.</span>{/if}
                </div>
            {/if}
        </div>

        <section class="rail">
            <div class="rider-head">
                <div class="avatar" style={`--rider-colour:${selected?.colour ?? "#00BFD8"}`}>
                    {initials(selected?.display_name ?? "")}
                </div>
                <div class="who">
                    <strong>{selected?.display_name ?? "Czekam na zawodnika"}</strong>
                    <span data-tone={ended ? "ended" : (selected?.status.tone ?? "offline")}>
                        <i></i>{ended ? "PRZEJAZD ZAKOŃCZONY" : (selected?.status.label ?? "ŁĄCZĘ…")}
                    </span>
                </div>
            </div>
            <p class="updated">
                {#if selected}
                    ostatnia aktualizacja: {ago(selected.ageSeconds)}
                    {#if selected.status.tone === "offline" && Number.isFinite(selected.ageSeconds)}
                        · ostatnia znana pozycja zostaje na mapie
                    {/if}
                {:else}
                    czekam na pierwszą pozycję…
                {/if}
            </p>

            {#if ended && snapshot?.summary}
                <div class="panel summary">
                    <h2>PODSUMOWANIE</h2>
                    <div class="grid big">
                        <div><span>DYSTANS</span><b>{fmtDistance(summaryRider?.distance_m)}</b></div>
                        <div><span>CZAS W RUCHU</span><b>{fmtDuration(summaryRider?.moving_seconds)}</b></div>
                        <div><span>CZAS CAŁKOWITY</span><b>{fmtDuration(snapshot.summary.elapsed_seconds)}</b></div>
                        <div><span>PRZEWYŻSZENIE</span><b>{summaryRider?.elevation_gain_m === undefined ? "—" : `${Math.round(summaryRider.elevation_gain_m)} m`}</b></div>
                    </div>
                    <div class="grid">
                        <div><span>ŚREDNIA</span><b>{summaryRider?.avg_speed_kmh === undefined ? "—" : `${num(summaryRider.avg_speed_kmh, 1)} km/h`}</b></div>
                        <div><span>MAKSYMALNA</span><b>{summaryRider?.max_speed_kmh === undefined ? "—" : `${num(summaryRider.max_speed_kmh, 1)} km/h`}</b></div>
                        {#if summaryRider?.avg_heart_rate_bpm !== undefined}
                            <div><span>TĘTNO ŚR.</span><b>{summaryRider.avg_heart_rate_bpm} bpm</b></div>
                            <div><span>TĘTNO MAKS.</span><b>{summaryRider.max_heart_rate_bpm} bpm</b></div>
                        {/if}
                        {#if summaryRider?.avg_power_watts !== undefined}
                            <div><span>MOC ŚR.</span><b>{summaryRider.avg_power_watts} W</b></div>
                            <div><span>MOC MAKS.</span><b>{summaryRider.max_power_watts} W</b></div>
                        {/if}
                        <div><span>START</span><b>{clock(snapshot.summary.started_at)}</b></div>
                        <div><span>KONIEC</span><b>{clock(snapshot.summary.ended_at)}</b></div>
                    </div>
                </div>
            {:else}
                <div class="panel">
                    <div class="grid big">
                        <div><span>DYSTANS</span><b>{fmtDistance(selected?.distance_m)}</b></div>
                        <div><span>CZAS</span><b>{fmtDuration(elapsedSeconds)}</b></div>
                        <div>
                            <span>PRĘDKOŚĆ</span>
                            <b>{liveSpeed === undefined ? "—" : num(liveSpeed, 1)}<em>km/h</em></b>
                        </div>
                        <div>
                            <span>ETA</span>
                            <b>{selected?.progress?.etaAt ? clock(selected.progress.etaAt.toISOString()) : "—"}</b>
                        </div>
                    </div>
                </div>
            {/if}

            {#if selected?.progress && !ended}
                <div class="panel">
                    <div class="progress-head">
                        <span>NA TRASIE</span>
                        <b>{Math.round(selected.progress.fraction * 100)}%</b>
                    </div>
                    <div class="bar" style={`--rider-colour:${selected.colour}`}>
                        <i style={`width:${selected.progress.fraction * 100}%`}></i>
                    </div>
                    <div class="progress-foot">
                        <span>do mety <b>{fmtDistance(selected.progress.remainingMeters)}</b></span>
                        {#if selected.progress.etaSeconds !== null}
                            <span>zostało <b>{fmtDuration(selected.progress.etaSeconds)}</b></span>
                        {/if}
                        {#if selected.progress.offRouteMeters > 80}
                            <span class="off">{Math.round(selected.progress.offRouteMeters)} m od trasy</span>
                        {/if}
                    </div>
                </div>
            {/if}

            {#if profile}
                <div class="panel profile">
                    <div class="panel-head">
                        <h2>PROFIL WYSOKOŚCI</h2>
                        <small>{Math.round(profile.min)}–{Math.round(profile.max)} m n.p.m.</small>
                    </div>
                    <svg viewBox="0 0 100 34" preserveAspectRatio="none" aria-hidden="true">
                        <path class="profile-area" d={profile.area} />
                        <path class="profile-line" d={profile.line} />
                        {#if profile.marker}
                            <line
                                class="profile-now"
                                x1={profile.marker.x}
                                y1="0"
                                x2={profile.marker.x}
                                y2="34"
                            />
                            <circle class="profile-dot" cx={profile.marker.x} cy={profile.marker.y} r="2.1" />
                        {/if}
                    </svg>
                </div>
            {/if}

            {#if climb && !ended}
                <div class="panel climb">
                    <span>NASTĘPNY PODJAZD</span>
                    <strong>za {fmtDistance(climb.distanceAheadMeters)}</strong>
                    <small>{climbLabel(climb)}</small>
                </div>
            {/if}

            {#if !ended}
            <div class="panel">
                <div class="grid">
                    <div><span>W RUCHU</span><b>{fmtDuration(selected?.moving_seconds)}</b></div>
                    <div><span>PRZEWYŻSZENIE</span><b>{selected?.elevation_gain_m === undefined ? "—" : `${Math.round(selected.elevation_gain_m)} m`}</b></div>
                    <div><span>WYSOKOŚĆ</span><b>{selected?.altitude_m === undefined ? "—" : `${Math.round(selected.altitude_m)} m`}</b></div>
                    <div><span>MAKS. PRĘDKOŚĆ</span><b>{selected?.max_speed_kmh ? `${num(selected.max_speed_kmh, 1)} km/h` : "—"}</b></div>
                    {#if selected?.heart_rate_bpm !== undefined}
                        <div><span>TĘTNO</span><b>{liveOnly(selected.heart_rate_bpm, selected.status.tone) || "—"}{liveOnly(selected.heart_rate_bpm, selected.status.tone) ? " bpm" : ""}</b></div>
                    {/if}
                    {#if selected?.power_watts !== undefined}
                        <div><span>MOC</span><b>{liveOnly(selected.power_watts, selected.status.tone) || "—"}{liveOnly(selected.power_watts, selected.status.tone) ? " W" : ""}</b></div>
                    {/if}
                    {#if selected?.cadence_rpm !== undefined}
                        <div><span>KADENCJA</span><b>{liveOnly(selected.cadence_rpm, selected.status.tone) || "—"}{liveOnly(selected.cadence_rpm, selected.status.tone) ? " rpm" : ""}</b></div>
                    {/if}
                    {#if selected?.battery_percent !== undefined && selected.battery_percent > 0}
                        <div><span>BATERIA</span><b>{selected.battery_percent}%</b></div>
                    {/if}
                </div>
                <footer class="meta-foot">
                    start {clock(snapshot?.started_at)}
                    {#if snapshot?.ended_at}· koniec {clock(snapshot.ended_at)}{/if}
                    {#if selected?.accuracy_m !== undefined}· GPS ±{Math.round(selected.accuracy_m)} m{/if}
                    {#if selected?.heading_deg}· kierunek {compass(selected.heading_deg)}{/if}
                </footer>
            </div>
            {/if}

            {#if isGroup}
                <div class="panel">
                    <div class="panel-head">
                        <h2>UCZESTNICY</h2>
                        <small>{liveCount} z {riders.length} na żywo</small>
                    </div>
                    <div class="people">
                        {#each riders as rider (rider.id)}
                            {@const gap = relativeGap(
                                rider.progress?.alongMeters ?? null,
                                leader?.progress?.alongMeters ?? null,
                            )}
                            <button
                                class="person"
                                class:selected={selected?.id === rider.id}
                                data-tone={rider.status.tone}
                                style={`--rider-colour:${rider.colour}`}
                                onclick={() => focusRider(rider)}
                            >
                                <div class="avatar small">{initials(rider.display_name)}</div>
                                <div class="who">
                                    <strong>{rider.display_name}</strong>
                                    <span>
                                        {rider.status.label.toLowerCase()}
                                        {#if gap && rider.id !== leader?.id}· {gap}{/if}
                                    </span>
                                </div>
                                <small>{ago(rider.ageSeconds)}</small>
                            </button>
                        {/each}
                    </div>
                </div>
            {/if}

            {#if messages.length}
                <div class="panel">
                    <div class="panel-head"><h2>WIADOMOŚCI GRUPY</h2></div>
                    <ul class="messages">
                        {#each messages as message (message.id)}
                            <li>
                                <b>{message.display_name || "Zawodnik"}</b>
                                <span>{message.body}</span>
                                <small>{clock(message.sent_at)}</small>
                            </li>
                        {/each}
                    </ul>
                </div>
            {/if}

            {#if !riders.length}
                <div class="panel waiting">
                    <div class="pulse"></div>
                    <strong>Czekam na pierwszą pozycję</strong>
                    <span>
                        Mapa już działa. Zawodnik pojawi się tutaj, gdy tylko jego telefon
                        wyśle pierwsze dane.
                    </span>
                </div>
            {/if}

            <p class="rail-foot">
                Live Ride · własne śledzenie jazdy na żywo
                {#if snapshot?.expires_at && !ended}
                    <br />link działa do {clock(snapshot.expires_at)}
                {/if}
            </p>
        </section>
    </main>
{/if}

<style>
    :global(html),
    :global(body) {
        margin: 0;
        background: #07101a;
        overscroll-behavior-y: none;
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
        transition:
            transform 0.16s ease,
            opacity 0.16s ease;
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
        opacity: 0.42;
        filter: grayscale(1);
    }
    :global(.lr-marker.idle) {
        box-shadow:
            0 0 0 6px color-mix(in srgb, var(--rider-colour) 10%, transparent),
            0 8px 22px rgb(0 0 0 / 0.35);
    }
    :global(.lr-marker.selected) {
        transform: scale(1.12);
    }

    :global(.lr-pin) {
        display: grid;
        place-items: center;
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
    :global(.lr-pin-finish) {
        background: #31d07c;
    }
    :global(.lr-pin-meetup) {
        width: 30px;
        height: 30px;
        padding: 0;
        background: none;
        box-shadow: none;
        color: #f2c037;
        filter: drop-shadow(0 2px 5px rgb(0 0 0 / 0.55));
    }

    .gone {
        display: grid;
        place-items: center;
        min-height: 100dvh;
        padding: 24px;
        background:
            radial-gradient(900px 520px at 80% -10%, rgb(0 191 216 / 0.14), transparent 60%),
            #07101a;
        color: #eaf3f8;
    }
    .gone-card {
        max-width: 420px;
        display: grid;
        justify-items: center;
        gap: 10px;
        padding: 34px 26px;
        border: 1px solid rgb(255 255 255 / 0.08);
        border-radius: 18px;
        background: rgb(12 24 36 / 0.85);
        text-align: center;
    }
    .gone-card .mark {
        width: 40px;
        height: 40px;
    }
    .gone-card .eyebrow {
        font-size: 10px;
        font-weight: 900;
        letter-spacing: 0.26em;
        color: #6ceeff;
    }
    .gone-card h1 {
        margin: 4px 0 0;
        font-size: 22px;
        letter-spacing: -0.02em;
    }
    .gone-card p {
        margin: 0;
        font-size: 13.5px;
        line-height: 1.55;
        color: #93a6b4;
    }
    .gone-card small {
        margin-top: 8px;
        font-size: 9.5px;
        letter-spacing: 0.1em;
        color: #4d5e6b;
    }

    .viewer {
        color: #f3f8fc;
        background: #07101a;
    }
    .stage {
        position: relative;
    }
    .map {
        position: absolute;
        inset: 0;
        background: #dde6ed;
    }

    .topbar {
        position: absolute;
        z-index: 5;
        inset: 0 0 auto 0;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 14px;
        padding: max(14px, env(safe-area-inset-top)) 16px 16px;
        pointer-events: none;
        background: linear-gradient(180deg, rgb(7 16 26 / 0.86), transparent);
    }
    .brand {
        flex: 1 1 auto;
        display: flex;
        align-items: center;
        gap: 11px;
        min-width: 0;
    }
    .mark {
        flex: none;
        width: 32px;
        height: 32px;
    }
    .brand-copy {
        display: grid;
        gap: 2px;
        min-width: 0;
    }
    .brand-copy span {
        font-size: 9.5px;
        font-weight: 900;
        letter-spacing: 0.24em;
        color: #6ceeff;
    }
    .brand-copy strong {
        overflow: hidden;
        white-space: nowrap;
        text-overflow: ellipsis;
        font-size: clamp(15px, 4.2vw, 24px);
        letter-spacing: -0.03em;
    }
    .top-actions {
        flex: none;
        display: flex;
        align-items: center;
        gap: 8px;
        pointer-events: auto;
    }
    .ghost {
        flex: none;
        width: 38px;
        height: 38px;
        display: grid;
        place-items: center;
        border: 1px solid rgb(255 255 255 / 0.16);
        border-radius: 9px;
        background: rgb(7 16 26 / 0.74);
        color: #fff;
        cursor: pointer;
        backdrop-filter: blur(12px);
    }
    .ghost svg {
        width: 19px;
        height: 19px;
    }

    .status {
        display: flex;
        align-items: center;
        gap: 7px;
        height: 38px;
        padding: 0 13px;
        border: 1px solid currentColor;
        border-radius: 9px;
        background: rgb(7 16 26 / 0.8);
        font-size: 10px;
        font-weight: 900;
        letter-spacing: 0.1em;
        white-space: nowrap;
        backdrop-filter: blur(12px);
    }
    .status i {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: currentColor;
    }
    [data-tone="live"] {
        color: #ff6b6b;
    }
    [data-tone="live"] i {
        animation: pulse 1.6s ease-in-out infinite;
    }
    [data-tone="idle"] {
        color: #f2c037;
    }
    [data-tone="offline"] {
        color: #8ea0ad;
    }
    [data-tone="ended"] {
        color: #59e9a5;
    }
    @keyframes pulse {
        50% {
            opacity: 0.25;
        }
    }

    .warning {
        position: absolute;
        z-index: 9;
        left: 16px;
        right: 16px;
        bottom: 16px;
        display: grid;
        gap: 3px;
        padding: 9px 12px;
        border-radius: 9px;
        background: rgb(148 40 34 / 0.94);
        color: #fff;
        font-size: 11.5px;
    }

    .rail {
        display: grid;
        align-content: start;
        gap: 12px;
        box-sizing: border-box;
        padding: 16px 16px calc(28px + env(safe-area-inset-bottom));
        background: #07101a;
    }

    .rider-head {
        display: flex;
        align-items: center;
        gap: 12px;
        min-width: 0;
    }
    .avatar {
        --rider-colour: #00bfd8;
        flex: none;
        width: 44px;
        height: 44px;
        display: grid;
        place-items: center;
        border-radius: 13px;
        background: var(--rider-colour);
        color: #05121a;
        font-size: 15px;
        font-weight: 900;
    }
    .avatar.small {
        width: 34px;
        height: 34px;
        border-radius: 10px;
        font-size: 12.5px;
    }
    .who {
        min-width: 0;
        display: grid;
        gap: 3px;
    }
    .who strong {
        overflow: hidden;
        white-space: nowrap;
        text-overflow: ellipsis;
        font-size: 18px;
        letter-spacing: -0.02em;
    }
    .who span {
        display: flex;
        align-items: center;
        gap: 6px;
        font-size: 9.5px;
        font-weight: 900;
        letter-spacing: 0.11em;
    }
    .who span i {
        width: 7px;
        height: 7px;
        border-radius: 50%;
        background: currentColor;
    }
    .updated {
        margin: -4px 0 2px;
        font-size: 11.5px;
        color: #7c8e9c;
    }

    .panel {
        display: grid;
        gap: 10px;
        padding: 14px;
        border: 1px solid rgb(255 255 255 / 0.07);
        border-radius: 13px;
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
        font-size: 9.5px;
        color: #62727f;
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
        padding: 10px 11px;
        border-radius: 9px;
        background: #08131c;
    }
    .grid span {
        font-size: 8.5px;
        font-weight: 900;
        letter-spacing: 0.13em;
        color: #7f919f;
    }
    .grid b {
        overflow: hidden;
        white-space: nowrap;
        text-overflow: ellipsis;
        font-size: 15px;
        font-variant-numeric: tabular-nums;
    }
    .grid.big b {
        font-size: 24px;
        letter-spacing: -0.035em;
    }
    .grid b em {
        margin-left: 4px;
        font-style: normal;
        font-size: 10px;
        font-weight: 600;
        color: #8496a3;
    }

    .progress-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
    }
    .progress-head span {
        font-size: 9px;
        font-weight: 900;
        letter-spacing: 0.15em;
        color: #7f919f;
    }
    .progress-head b {
        font-size: 17px;
        font-variant-numeric: tabular-nums;
    }
    .bar {
        --rider-colour: #00bfd8;
        height: 6px;
        border-radius: 3px;
        background: #08131c;
        overflow: hidden;
    }
    .bar i {
        display: block;
        height: 100%;
        border-radius: 3px;
        background: var(--rider-colour);
        transition: width 0.6s ease;
    }
    .progress-foot {
        display: flex;
        flex-wrap: wrap;
        gap: 4px 14px;
        font-size: 11px;
        color: #8496a3;
    }
    .progress-foot b {
        color: #eaf3f8;
        font-variant-numeric: tabular-nums;
    }
    .progress-foot .off {
        color: #ff8080;
    }

    .profile svg {
        width: 100%;
        height: 78px;
        display: block;
    }
    .profile-area {
        fill: rgb(0 191 216 / 0.14);
    }
    .profile-line {
        fill: none;
        stroke: #00bfd8;
        stroke-width: 0.9;
        vector-effect: non-scaling-stroke;
    }
    .profile-now {
        stroke: rgb(255 255 255 / 0.45);
        stroke-width: 1;
        vector-effect: non-scaling-stroke;
    }
    .profile-dot {
        fill: #ffffff;
    }

    .climb {
        gap: 4px;
    }
    .climb span {
        font-size: 9px;
        font-weight: 900;
        letter-spacing: 0.15em;
        color: #7f919f;
    }
    .climb strong {
        font-size: 17px;
        letter-spacing: -0.02em;
    }
    .climb small {
        font-size: 11.5px;
        color: #8496a3;
    }

    .meta-foot {
        font-size: 10px;
        color: #62727f;
    }

    .people {
        display: grid;
        gap: 7px;
    }
    .person {
        --rider-colour: #00bfd8;
        display: flex;
        align-items: center;
        gap: 10px;
        width: 100%;
        padding: 9px 10px;
        border: 1px solid rgb(255 255 255 / 0.07);
        border-left: 3px solid var(--rider-colour);
        border-radius: 9px;
        background: #08131c;
        color: inherit;
        text-align: left;
        cursor: pointer;
    }
    .person.selected {
        background: #112230;
        border-color: var(--rider-colour);
    }
    .person[data-tone="offline"] {
        opacity: 0.55;
    }
    .person .who strong {
        font-size: 13.5px;
    }
    .person .who span {
        font-size: 10.5px;
        font-weight: 600;
        letter-spacing: 0;
        color: #8496a3;
        text-transform: none;
    }
    .person > small {
        margin-left: auto;
        flex: none;
        font-size: 9.5px;
        color: #62727f;
    }

    .messages {
        margin: 0;
        padding: 0;
        list-style: none;
        display: grid;
        gap: 7px;
    }
    .messages li {
        display: grid;
        grid-template-columns: auto 1fr auto;
        gap: 8px;
        align-items: baseline;
        padding: 8px 10px;
        border-radius: 8px;
        background: #08131c;
        font-size: 12px;
    }
    .messages b {
        color: #6ceeff;
        font-size: 11px;
    }
    .messages small {
        color: #62727f;
        font-size: 10px;
    }

    .waiting {
        justify-items: center;
        gap: 8px;
        padding: 30px 18px;
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
        margin: 2px 0 0;
        font-size: 9.5px;
        line-height: 1.7;
        letter-spacing: 0.06em;
        color: #4d5e6b;
        text-align: center;
    }

    /* --- telefon: mapa na pierwszym ekranie, karty pionowo pod nią ------ */
    @media (max-width: 900px) {
        .stage {
            position: sticky;
            top: 0;
            z-index: 1;
            height: 56dvh;
            min-height: 280px;
        }
        .rail {
            position: relative;
            z-index: 2;
            margin-top: -16px;
            border-radius: 18px 18px 0 0;
            border-top: 1px solid rgb(255 255 255 / 0.08);
            box-shadow: 0 -18px 40px rgb(0 0 0 / 0.45);
        }
        .grid.big {
            grid-template-columns: repeat(2, minmax(0, 1fr));
        }
    }

    /* --- bardzo wąsko (iPhone SE): nie ściskamy liczb do nieczytelności - */
    @media (max-width: 360px) {
        .grid.big b {
            font-size: 21px;
        }
        .status {
            padding: 0 9px;
            font-size: 9px;
        }
    }

    /* --- desktop i tablet w poziomie: mapa po lewej, dane po prawej ----- */
    @media (min-width: 901px) {
        :global(body) {
            overflow: hidden;
        }
        .viewer {
            display: grid;
            grid-template-columns: minmax(0, 1fr) 420px;
            height: 100dvh;
        }
        .stage {
            height: 100dvh;
        }
        .rail {
            height: 100dvh;
            overflow-y: auto;
            padding: 20px;
            border-left: 1px solid rgb(255 255 255 / 0.08);
            background: rgb(7 16 26 / 0.98);
        }
        /* Cztery kolumny w szynie szerokiej na 420 px ucinają „21,4 km" do
           „21,…", więc największe liczby zostają w dwóch kolumnach. */
        .grid.big b {
            font-size: 22px;
        }
    }
</style>
