<script lang="ts">
    import { onMount } from "svelte";
    import * as M from "maplibre-gl";
    import "maplibre-gl/dist/maplibre-gl.css";
    import { ensureMapLibreWorker } from "$lib/util/maplibre_worker";
    import { initials, type LngLat, type StatusTone } from "$lib/live/live_viewer";

    /**
     * Mapa publicznego LIVE.
     *
     * Cała obsługa MapLibre siedzi tutaj, a nie w stronie: warstwy, znaczniki
     * i dociąganie pozycji to jedyny fragment tego widoku, który jest
     * imperatywny i nie da się go opisać deklaratywnie. Reszta strony układa
     * się z danych.
     */

    export type MapRider = {
        id: string;
        name: string;
        colour: string;
        lngLat: LngLat | null;
        tone: StatusTone;
        headingDeg: number | undefined;
    };

    let {
        riders,
        selectedId,
        routeCoordinates,
        routeCumulative = [],
        alongMeters = null,
        checkpoints = [],
        tracks,
        trackVersion,
        meetup,
        onselect,
    }: {
        riders: MapRider[];
        selectedId: string | null;
        routeCoordinates: LngLat[];
        /** Narastający dystans wzdłuż planu — dzieli go na przejechany i resztę. */
        routeCumulative?: number[];
        /** Gdzie na planie jest wybrany zawodnik. */
        alongMeters?: number | null;
        checkpoints?: { name: string; lat?: number; lon?: number }[];
        tracks: Map<string, LngLat[]>;
        trackVersion: number;
        meetup: { latitude: number; longitude: number; label: string } | null;
        onselect: (id: string) => void;
    } = $props();

    let map: M.Map | null = null;
    let styleReady = false;
    let firstFit = true;
    let error = $state("");

    /**
     * Czy mapa jedzie za zawodnikiem.
     *
     * Domyślnie tak. Pierwsze przeciągnięcie palcem ją zwalnia i pokazuje
     * przycisk powrotu — widz, który właśnie ogląda metę, nie ma być co trzy
     * sekundy odrzucany z powrotem do znacznika.
     */
    let following = $state(true);

    const markers = new Map<string, M.Marker>();
    const markerTargets = new Map<string, LngLat>();
    const markerPositions = new Map<string, LngLat>();
    let meetupMarker: M.Marker | null = null;
    let startMarker: M.Marker | null = null;
    let finishMarker: M.Marker | null = null;
    const checkpointMarkers: M.Marker[] = [];

    /** Mapa na cały ekran — do oglądania jazdy, a nie tylko zerkania. */
    let fullscreen = $state(false);

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

    /**
     * Plan podzielony na przejechany i pozostały.
     *
     * Bez tego podziału widz widzi jedną kreskę i musi porównywać ją ze
     * znacznikiem, żeby zgadnąć, ile zostało. Przejechany fragment planu to
     * NIE to samo co ślad: ślad pokazuje, którędy ktoś pojechał naprawdę,
     * a przejechany plan — dokąd doszedł względem zamiaru. Przy objeździe te
     * dwie linie się rozchodzą i właśnie to jest wtedy najciekawsze.
     */
    function splitRoute(): [LngLat[], LngLat[]] {
        const along = alongMeters;
        if (along === null || routeCumulative.length !== routeCoordinates.length) {
            return [[], routeCoordinates];
        }
        let index = 0;
        while (index < routeCumulative.length && routeCumulative[index] <= along) index++;
        if (index <= 1) return [[], routeCoordinates];
        if (index >= routeCoordinates.length) return [routeCoordinates, []];
        // Punkt styku należy do obu linii, żeby nie było między nimi dziury.
        return [routeCoordinates.slice(0, index), routeCoordinates.slice(index - 1)];
    }

    function syncRoute() {
        if (!map || !styleReady || routeCoordinates.length < 2) return;
        const [covered, remaining] = splitRoute();
        const data: GeoJSON.FeatureCollection<GeoJSON.LineString> = {
            type: "FeatureCollection",
            features: [
                {
                    type: "Feature",
                    properties: { part: "remaining" },
                    geometry: { type: "LineString", coordinates: remaining },
                },
                {
                    type: "Feature",
                    properties: { part: "covered" },
                    geometry: { type: "LineString", coordinates: covered },
                },
            ].filter((feature) => feature.geometry.coordinates.length > 1) as GeoJSON.Feature<GeoJSON.LineString>[],
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
                paint: { "line-color": "#ffffff", "line-width": 8, "line-opacity": 0.85 },
            });
            // Plan jest przerywany i przygaszony, przejechane ciągłe i mocne.
            // Widz ma rozróżnić jedno od drugiego rzutem oka, bez legendy.
            map.addLayer({
                id: "live-route-line",
                type: "line",
                source: "live-route",
                filter: ["==", ["get", "part"], "remaining"],
                layout: { "line-cap": "round", "line-join": "round" },
                paint: {
                    "line-color": "#47555f",
                    "line-width": 3,
                    "line-opacity": 0.75,
                    "line-dasharray": [1.8, 1.6],
                },
            });
            // Przejechany fragment planu: ciągły i wyraźniejszy, ale nadal
            // ciemny — kolor zawodnika należy do jego ŚLADU i nie wolno go
            // pożyczyć planowi, bo wtedy znikłaby różnica między jednym
            // a drugim.
            map.addLayer({
                id: "live-route-covered",
                type: "line",
                source: "live-route",
                filter: ["==", ["get", "part"], "covered"],
                layout: { "line-cap": "round", "line-join": "round" },
                paint: {
                    "line-color": "#0b1116",
                    "line-width": 3.5,
                    "line-opacity": 0.45,
                },
            });
        }
        syncRouteEnds();
        syncCheckpoints();
    }

    /** Nazwane punkty pośrednie trasy, tak jak nazwał je zawodnik. */
    function syncCheckpoints() {
        if (!map) return;
        for (const marker of checkpointMarkers.splice(0)) marker.remove();
        for (const checkpoint of checkpoints) {
            if (!Number.isFinite(checkpoint.lat) || !Number.isFinite(checkpoint.lon)) continue;
            const element = document.createElement("div");
            element.className = "lr-pin lr-pin-checkpoint";
            element.title = checkpoint.name;
            element.innerHTML = "<span>•</span>";
            checkpointMarkers.push(
                new M.Marker({ element, anchor: "center" })
                    .setLngLat([checkpoint.lon!, checkpoint.lat!])
                    .addTo(map),
            );
        }
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

    function featureCollection(): GeoJSON.FeatureCollection<GeoJSON.LineString> {
        // Zależność od `trackVersion` jest celowa: mapa śladów nie jest
        // reaktywna, więc to ona mówi Svelte, że coś się zmieniło.
        void trackVersion;
        // Wybrany rysuje się jako ostatni, czyli na wierzchu: w grupie jadącej
        // tą samą drogą ślady leżą jeden na drugim.
        const ordered = [
            ...riders.filter((rider) => rider.id !== selectedId),
            ...riders.filter((rider) => rider.id === selectedId),
        ];
        return {
            type: "FeatureCollection",
            features: ordered
                .map((rider) => ({
                    type: "Feature" as const,
                    properties: { colour: rider.colour },
                    geometry: {
                        type: "LineString" as const,
                        coordinates: tracks.get(rider.id) ?? [],
                    },
                }))
                .filter((feature) => feature.geometry.coordinates.length > 1),
        };
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
            paint: { "line-color": "#ffffff", "line-width": 9, "line-opacity": 0.9 },
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
        if (!meetup) {
            meetupMarker?.remove();
            meetupMarker = null;
            return;
        }
        const at: LngLat = [meetup.longitude, meetup.latitude];
        if (!meetupMarker) {
            meetupMarker = new M.Marker({
                element: pinElement("meetup", meetup.label || "Punkt zbiórki"),
                anchor: "bottom",
            })
                .setLngLat(at)
                .addTo(map);
        } else {
            meetupMarker.setLngLat(at);
        }
    }

    function markerElement(rider: MapRider) {
        const root = document.createElement("button");
        root.type = "button";
        root.className = "lr-marker";
        root.setAttribute("aria-label", rider.name);
        root.innerHTML = `<i class="arrow"></i><span class="lr-marker-initials"></span>`;
        root.onclick = () => onselect(rider.id);
        return root;
    }

    function syncMarkers() {
        if (!map) return;
        const alive = new Set<string>();
        for (const rider of riders) {
            if (!rider.lngLat) continue;
            alive.add(rider.id);
            let marker = markers.get(rider.id);
            if (!marker) {
                marker = new M.Marker({ element: markerElement(rider), anchor: "center" })
                    .setLngLat(rider.lngLat)
                    .addTo(map);
                markers.set(rider.id, marker);
                markerPositions.set(rider.id, rider.lngLat);
            }
            markerTargets.set(rider.id, rider.lngLat);

            const element = marker.getElement();
            element.style.setProperty("--rider-colour", rider.colour);
            const label = element.querySelector(".lr-marker-initials");
            if (label) label.textContent = initials(rider.name);
            // Strzałka kierunku tylko wtedy, gdy kurs jest znany. Zero stopni
            // z braku danych wskazywałoby uparcie na północ.
            const arrow = element.querySelector<HTMLElement>(".arrow");
            if (arrow) {
                const heading = rider.headingDeg;
                const known = heading !== undefined && Number.isFinite(heading) && heading > 0;
                arrow.style.display = known ? "block" : "none";
                if (known) arrow.style.transform = `rotate(${heading}deg)`;
            }
            element.classList.toggle("stale", rider.tone === "offline");
            element.classList.toggle("idle", rider.tone === "idle" || rider.tone === "waiting");
            element.classList.toggle("selected", selectedId === rider.id);
        }
        for (const [id, marker] of markers) {
            if (alive.has(id)) continue;
            marker.remove();
            markers.delete(id);
            markerTargets.delete(id);
            markerPositions.delete(id);
        }
        syncMeetup();
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
        if (changed && following && selectedId && markerPositions.has(selectedId)) {
            map?.panTo(markerPositions.get(selectedId)!, { duration: 0, animate: false });
        }
    }

    function fitAll(force = false) {
        if (!map || (!firstFit && !force)) return;
        // Pierwsze dopasowanie domyka dopiero geometria: widok ustawiony na
        // same znaczniki, zanim doszła trasa, zostawiłby znajomego z wycinkiem.
        const hasGeometry = routeCoordinates.length > 1 || tracks.size > 0;
        const bounds = new M.LngLatBounds();
        for (const point of routeCoordinates) bounds.extend(point);
        for (const [, points] of tracks) for (const point of points) bounds.extend(point);
        for (const rider of riders) if (rider.lngLat) bounds.extend(rider.lngLat);
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
            ? { top: 60, right: 60, bottom: 60, left: 60 }
            : { top: 46, right: 30, bottom: 44, left: 30 };
    }

    /** Powrót do zawodnika po ręcznym przesunięciu mapy. */
    export function recentre() {
        following = true;
        if (!map || !selectedId) return;
        const at = markerPositions.get(selectedId) ?? markerTargets.get(selectedId);
        if (!at) {
            fitAll(true);
            return;
        }
        map.easeTo({ center: at, zoom: Math.max(map.getZoom(), 14.5), duration: 450 });
    }

    /** Cała trasa i cały ślad w kadrze. */
    export function overview() {
        following = false;
        fitAll(true);
    }

    // Każda zmiana danych przechodzi przez warstwy mapy. Svelte nie zna
    // MapLibre, więc to jedyne miejsce, które musi o tym powiedzieć wprost.
    $effect(() => {
        void riders;
        void selectedId;
        syncMarkers();
    });
    $effect(() => {
        void routeCoordinates;
        void alongMeters;
        void checkpoints;
        syncRoute();
    });
    // Zmiana rozmiaru kontenera nie dociera do MapLibre sama — bez tego
    // pełny ekran rysowałby mapę w starym kadrze.
    $effect(() => {
        void fullscreen;
        map?.resize();
    });
    $effect(() => {
        void trackVersion;
        syncTracks();
    });

    onMount(() => {
        let frame = 0;
        void (async () => {
            try {
                const response = await fetch("/api/v1/map/style?theme=liberty", {
                    cache: "force-cache",
                });
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                const style = (await response.json()) as M.StyleSpecification;
                ensureMapLibreWorker();
                map = new M.Map({
                    container: "live-map",
                    style,
                    center: [19.4, 52.1],
                    zoom: 5.4,
                    attributionControl: false,
                    fadeDuration: 0,
                });
                map.addControl(new M.AttributionControl({ compact: true }), "bottom-right");
                map.on("load", () => {
                    // Własna flaga zamiast `map.isStyleLoaded()`: to drugie
                    // wraca do `false`, gdy tylko dołożymy źródło, więc warstwa
                    // śladu dokładana zaraz po trasie nigdy nie przechodziła
                    // przez taki warunek i przejechany odcinek się nie rysował.
                    styleReady = true;
                    syncRoute();
                    syncTracks();
                    syncMarkers();
                    fitAll();
                });
                // Ręczne przesunięcie zwalnia śledzenie, dokładnie jak
                // w aplikacji.
                map.on("dragstart", () => (following = false));
                map.on("error", (event) => console.warn("Live Ride map", event.error));
            } catch (e) {
                error = e instanceof Error ? e.message : "nie udało się uruchomić mapy";
            }
        })();

        const animate = () => {
            animateMarkers();
            frame = window.requestAnimationFrame(animate);
        };
        frame = window.requestAnimationFrame(animate);

        return () => {
            window.cancelAnimationFrame(frame);
            map?.remove();
            map = null;
        };
    });
</script>

<div class="wrap" class:fullscreen>
    <div id="live-map" class="canvas"></div>

    {#if error}
        <p class="failed">Mapa niedostępna. Dane poniżej działają normalnie.</p>
    {/if}

    <div class="controls">
        <button
            type="button"
            class="lr-button round"
            title={fullscreen ? "Zamknij pełny ekran" : "Mapa na pełnym ekranie"}
            aria-label={fullscreen ? "Zamknij pełny ekran" : "Mapa na pełnym ekranie"}
            onclick={() => (fullscreen = !fullscreen)}>{fullscreen ? "×" : "⛶"}</button
        >
        {#if !following}
            <button
                type="button"
                class="lr-button round"
                title="Wróć do zawodnika"
                aria-label="Wróć do zawodnika"
                onclick={recentre}>⌖</button
            >
        {/if}
        <button
            type="button"
            class="lr-button round"
            title="Pokaż całą trasę"
            aria-label="Pokaż całą trasę"
            onclick={overview}>⤢</button
        >
    </div>
</div>

<style>
    .wrap {
        position: relative;
        background: var(--lr-canvas);
        border-bottom: 1px solid var(--lr-line);
    }

    .canvas {
        height: var(--lr-map-height);
        min-height: 240px;
    }

    /* Pełny ekran zostaje w drzewie strony zamiast wołać Fullscreen API:
       na iOS w Safari tamto nie działa dla elementów innych niż wideo, więc
       przycisk nie robiłby nic dokładnie tam, gdzie ta strona jest oglądana
       najczęściej. */
    .fullscreen {
        position: fixed;
        inset: 0;
        z-index: 40;
        border-bottom: none;
    }

    .fullscreen .canvas {
        height: 100%;
    }

    .controls {
        position: absolute;
        right: 10px;
        bottom: 10px;
        display: flex;
        flex-direction: column;
        gap: 6px;
        z-index: 2;
    }

    .round {
        width: 38px;
        min-height: 38px;
        padding: 0;
        font-size: 17px;
        line-height: 1;
        box-shadow: 0 1px 2px rgba(11, 17, 22, 0.14);
    }

    .failed {
        position: absolute;
        inset: auto 10px 10px;
        margin: 0;
        padding: 8px 10px;
        background: var(--lr-surface);
        border: 1px solid var(--lr-line);
        border-radius: var(--lr-radius);
        font-size: 12px;
        color: var(--lr-ink-soft);
    }

    /* Znaczniki i szpilki żyją poza drzewem Svelte — MapLibre wstawia je
       bezpośrednio do DOM, więc ich style muszą być globalne. */
    :global(.lr-marker) {
        appearance: none;
        border: none;
        padding: 0;
        width: 32px;
        height: 32px;
        border-radius: 50%;
        background: var(--rider-colour, #00bfd8);
        color: #04121c;
        font-weight: 900;
        font-size: 11.5px;
        letter-spacing: 0.4px;
        display: grid;
        place-items: center;
        cursor: pointer;
        box-shadow: 0 0 0 2.5px #fff, 0 1px 4px rgba(11, 17, 22, 0.35);
        position: relative;
    }

    :global(.lr-marker.selected) {
        box-shadow: 0 0 0 3px #fff, 0 0 0 5px var(--rider-colour, #00bfd8);
    }

    :global(.lr-marker.idle) {
        filter: saturate(0.6);
    }

    :global(.lr-marker.stale) {
        filter: grayscale(1);
        opacity: 0.65;
    }

    :global(.lr-marker .arrow) {
        position: absolute;
        inset: -9px 0 auto 0;
        margin: auto;
        width: 0;
        height: 0;
        border-left: 5px solid transparent;
        border-right: 5px solid transparent;
        border-bottom: 8px solid var(--rider-colour, #00bfd8);
        transform-origin: 50% 25px;
        filter: drop-shadow(0 0 1.5px #fff);
    }

    :global(.lr-pin) {
        display: grid;
        place-items: center;
        font-size: 9.5px;
        font-weight: 900;
        letter-spacing: 0.8px;
        padding: 3px 6px;
        border-radius: 4px;
        background: var(--lr-surface, #fff);
        border: 1px solid var(--lr-ink, #0b1116);
        color: var(--lr-ink, #0b1116);
        box-shadow: 0 1px 3px rgba(11, 17, 22, 0.3);
    }

    :global(.lr-pin-checkpoint) {
        width: 18px;
        height: 18px;
        padding: 0;
        border-radius: 50%;
        font-size: 13px;
        line-height: 1;
        color: var(--lr-accent-deep, #0090a8);
    }

    :global(.lr-pin-finish) {
        background: var(--lr-ink, #0b1116);
        color: #fff;
    }

    :global(.lr-pin-meetup) {
        width: 26px;
        height: 26px;
        padding: 3px;
        border-radius: 50%;
        color: var(--lr-accent-deep, #0090a8);
    }

    :global(.lr-pin-meetup svg) {
        width: 100%;
        height: 100%;
    }
</style>
