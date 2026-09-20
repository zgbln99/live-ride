<script lang="ts">
    import { onMount } from "svelte";
    import { decodePolyline } from "$lib/util/polyline_util";
    import "$lib/live/live_theme.css";

    import LiveHeader from "$lib/components/live/LiveHeader.svelte";
    import RiderCard from "$lib/components/live/RiderCard.svelte";
    import LiveMap from "$lib/components/live/LiveMap.svelte";
    import PrimaryMetrics from "$lib/components/live/PrimaryMetrics.svelte";
    import RouteProgressSection from "$lib/components/live/RouteProgress.svelte";
    import ElevationProfile from "$lib/components/live/ElevationProfile.svelte";
    import ClimbCard from "$lib/components/live/ClimbCard.svelte";
    import NavigationCard from "$lib/components/live/NavigationCard.svelte";
    import RideTimesSection from "$lib/components/live/RideTimes.svelte";
    import UpcomingClimbs from "$lib/components/live/UpcomingClimbs.svelte";
    import RouteBriefing from "$lib/components/live/RouteBriefing.svelte";
    import RouteWeather from "$lib/components/live/RouteWeather.svelte";
    import SensorMetrics from "$lib/components/live/SensorMetrics.svelte";
    import GroupRiders from "$lib/components/live/GroupRiders.svelte";
    import MeetupCard from "$lib/components/live/MeetupCard.svelte";
    import LiveMessages from "$lib/components/live/LiveMessages.svelte";
    import RideSummary from "$lib/components/live/RideSummary.svelte";

    import {
        RIDER_COLOURS,
        cumulativeDistances,
        hasPosition,
        haversine,
        liveOnly,
        paceKmh,
        projectOnRoute,
        relativeGap,
        rideTimes,
        riderStatus,
        routeProgress,
        type LngLat,
        type Projection,
        type Rider,
        type RouteProgress,
        type RouteSnapshot,
        type Snapshot,
        type TrackSlice,
    } from "$lib/live/live_viewer";
    import {
        climbSummary,
        currentClimb,
        elevationInsight,
        reportedClimb,
        surfaceShares,
        upcomingClimbs,
    } from "$lib/live/route_insight";
    import {
        forecastAlongRoute,
        sunsetInfo,
        weatherAlert,
        type WeatherSnapshot,
    } from "$lib/live/weather";
    import type { PageData } from "./$types";

    let { data }: { data: PageData } = $props();

    /** Ile czekamy między migawkami, gdy karta jest widoczna. */
    const REFRESH_MS = 3000;
    /** …i gdy przeglądarka odłożyła kartę w tło. */
    const BACKGROUND_REFRESH_MS = 30000;
    /** Ślad rośnie wolniej niż pozycja, więc dociągamy go rzadziej. */
    const TRACK_REFRESH_MS = 9000;
    /** Prognoza godzinowa zmienia się rzadko; serwer i tak ją buforuje. */
    const WEATHER_REFRESH_MS = 600000;

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
     * więc znajomy widzi zawodnika, tytuł i stan już w pierwszej odpowiedzi,
     * a nie po rundzie do API.
     */
    let fetched = $state<Snapshot | null>(null);
    const snapshot = $derived(fetched ?? data.snapshot);
    let route = $state<RouteSnapshot | null>(null);
    let weather = $state<WeatherSnapshot | null>(null);
    let messages = $state<Message[]>([]);
    let offline = $state(false);
    let selectedRiderId = $state<string | null>(null);
    let allClimbs = $state(false);
    let mapComponent = $state<LiveMap | null>(null);

    /**
     * Przesunięcie zegara widza względem serwera, w milisekundach.
     *
     * Wszystkie „ile temu" liczymy po czasie serwera. Telefon z zegarem
     * przestawionym o dziesięć minut pokazywałby całą grupę jako offline mimo
     * idealnie działającej telemetrii.
     */
    let clockSkewMs = $state(0);
    let now = $state(Date.now());

    let routeCoordinates = $state<LngLat[]>([]);
    let routeCumulative: number[] = [];
    let routeLengthMeters = $state(0);

    /** Przejechany ślad każdego zawodnika, dosypywany przyrostami. */
    const tracks = new Map<string, LngLat[]>();
    const trackCursors = new Map<string, string>();
    let trackVersion = $state(0);

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
                    ? projectOnRoute(
                          routeCoordinates,
                          routeCumulative,
                          rider.longitude!,
                          rider.latitude!,
                      )
                    : null;
                return {
                    ...rider,
                    colour: RIDER_COLOURS[index % RIDER_COLOURS.length],
                    ageSeconds,
                    status: riderStatus(
                        // Zakończona sesja przebija stan zawodnika:
                        // ostatnia próbka mówiła „jedzie" i bez tego
                        // karta twierdziłaby to samo długo po mecie.
                        snapshot?.status === "ended" ? "ended" : rider.state,
                        ageSeconds,
                    ),
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

    const selected = $derived(
        riders.find((rider) => rider.id === selectedRiderId) ?? riders[0] ?? null,
    );
    const leader = $derived(riders[0] ?? null);
    const isGroup = $derived(riders.length > 1);
    const tone = $derived(selected?.status.tone ?? "offline");

    /**
     * Wartości chwilowe wolno pokazać tylko wtedy, gdy są chwilowe.
     *
     * Zawodnik bez sygnału nie jedzie 31 km/h — jechał tyle wtedy, gdy
     * ostatni raz było go słychać. Dystans i czas zostają, bo narastają.
     */
    const liveSpeed = $derived(
        selected ? liveOnly(selected.speed_kmh, tone) : undefined,
    );
    const liveHeartRate = $derived(
        selected ? liveOnly(selected.heart_rate_bpm, tone) : undefined,
    );
    const livePower = $derived(selected ? liveOnly(selected.power_watts, tone) : undefined);
    const liveCadence = $derived(selected ? liveOnly(selected.cadence_rpm, tone) : undefined);

    const times = $derived(
        rideTimes(selected, snapshot?.started_at, snapshot?.ended_at, serverNow),
    );

    const averageSpeedKmh = $derived.by(() => {
        // Serwer liczy średnią z tych samych dwóch liczb, ale zna je
        // dokładniej niż my po zaokrągleniu w migawce.
        if (selected?.average_speed_kmh !== undefined) return selected.average_speed_kmh;
        const metres = selected?.distance_m;
        const moving = selected?.moving_seconds;
        if (metres === undefined || moving === undefined || moving <= 0) return undefined;
        return (metres / moving) * 3.6;
    });

    /**
     * Nawigacja z telemetrii — tylko dopóki jazda trwa.
     *
     * Po mecie manewr jest wspomnieniem, a nie wskazówką.
     */
    const nav = $derived(ended ? null : (selected?.nav ?? null));

    /** Nachylenie chwilowe znika razem z resztą chwilowych po utracie sygnału. */
    const liveGradient = $derived(
        selected ? liveOnly(selected.gradient_percent, tone) : undefined,
    );

    /**
     * Pozycja na trasie — albo nic, gdy przejazd się skończył.
     *
     * Po mecie nie istnieje „przed zawodnikiem": kolejne podjazdy
     * i pozostałe przewyższenie to sekcje o przyszłości, której już nie
     * ma. Profil pokazuje wtedy całą trasę, bez znacznika i bez reszty
     * do wjechania.
     */
    const alongMeters = $derived(
        ended ? null : (selected?.progress?.alongMeters ?? null),
    );

    /**
     * Podjazd z licznika zawodnika wygrywa z podjazdem policzonym z trasy.
     *
     * Trasa bywa lokalna albo z GPX-a bez profilu, a telefon i tak liczy
     * ClimbPro. Gdy telemetria go niesie, widz dostaje tę samą liczbę, którą
     * zawodnik ma przed oczami — a nie jej drugą wersję.
     */
    const climbNow = $derived(
        (ended ? null : reportedClimb(selected?.climb)) ??
            currentClimb(route?.climbs, alongMeters),
    );
    const climbsAhead = $derived(
        upcomingClimbs(route?.climbs, alongMeters, allClimbs ? 50 : 3),
    );
    const climbTotals = $derived(climbSummary(route?.climbs));
    const elevation = $derived(elevationInsight(route?.elevation_profile, alongMeters));
    const surfaces = $derived(surfaceShares(route?.surfaces));

    const pace = $derived(selected ? paceKmh(selected) : null);
    const forecasts = $derived(forecastAlongRoute(weather, serverNow, pace));
    const alert = $derived(weatherAlert(forecasts));
    const sunset = $derived(
        sunsetInfo(weather, serverNow, selected?.progress?.etaAt ?? null),
    );

    /** Poza trasą pokazujemy odległość dopiero wtedy, gdy jest istotna. */
    const offRouteMeters = $derived.by(() => {
        const off = selected?.projection?.offRouteMeters;
        if (off === undefined || routeLengthMeters <= 0) return null;
        return off > 150 ? off : null;
    });

    /** Dystans do punktu zbiórki w linii prostej — i tylko tak nazwany. */
    const meetupDistance = $derived.by(() => {
        const meetup = snapshot?.meetup;
        if (!meetup || !selected || !hasPosition(selected)) return null;
        return haversine(
            [selected.longitude!, selected.latitude!],
            [meetup.longitude, meetup.latitude],
        );
    });

    const meetupEta = $derived.by(() => {
        const metres = meetupDistance;
        if (metres === null || pace === null || pace <= 0) return null;
        return new Date(serverNow + (metres / 1000 / pace) * 3600 * 1000);
    });

    const groupRiders = $derived(
        riders.map((rider) => ({
            id: rider.id,
            name: rider.display_name,
            colour: rider.colour,
            statusLabel: rider.status.short,
            statusTone: rider.status.tone,
            distanceMeters: rider.distance_m,
            gap:
                rider.id === leader?.id
                    ? null
                    : relativeGap(
                          rider.progress?.alongMeters ?? null,
                          leader?.progress?.alongMeters ?? null,
                      ),
        })),
    );

    const mapRiders = $derived(
        riders.map((rider) => ({
            id: rider.id,
            name: rider.display_name,
            colour: rider.colour,
            lngLat: hasPosition(rider)
                ? ([rider.longitude!, rider.latitude!] as LngLat)
                : null,
            tone: rider.status.tone,
            headingDeg: liveOnly(rider.heading_deg, rider.status.tone),
        })),
    );

    const summaryRider = $derived.by(() => {
        const rows = snapshot?.summary?.riders ?? [];
        return rows.find((row) => row.id === selected?.id) ?? rows[0] ?? null;
    });

    const headerStatus = $derived.by(() => {
        if (snapshot?.status === "expired")
            return { label: "LINK WYGASŁ", tone: "offline" as const };
        if (snapshot?.status === "disabled")
            return { label: "UDOSTĘPNIANIE WYŁĄCZONE", tone: "offline" as const };
        if (ended) return { label: "PRZEJAZD ZAKOŃCZONY", tone: "ended" as const };
        return {
            label: selected?.status.short ?? "OCZEKIWANIE",
            tone: selected?.status.tone ?? ("waiting" as const),
        };
    });

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
            offline = false;
        } catch {
            // Utrata sieci u WIDZA nie zmienia stanu zawodnika. Zostawiamy
            // ostatnią znaną migawkę i mówimy wprost, że to my nie mamy
            // połączenia — zamiast ogłaszać, że ktoś zniknął.
            offline = true;
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
            if (touched) trackVersion += 1;
        } catch {
            // Ślad jest ozdobą pozycji, nie warunkiem jej pokazania.
        }
    }

    async function loadWeather() {
        try {
            const response = await fetch(api("/weather"), { cache: "no-store" });
            if (!response.ok) return;
            const payload = (await response.json()) as WeatherSnapshot;
            weather = payload?.points?.length ? payload : null;
        } catch {
            // Dostawca pogody nie jest częścią jazdy: bez niego znika jedna
            // sekcja, a nie mapa.
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

    function selectRider(id: string) {
        selectedRiderId = id;
        mapComponent?.recentre();
    }

    onMount(() => {
        document.documentElement.lang = "pl";
        applyServerTime(snapshot?.server_time);

        if (linkDead) {
            // Wygasły link nie ma czego odpytywać ani rysować.
            return;
        }

        void loadRoute();
        void refresh();
        void loadTrack();
        void loadWeather();
        void loadMessages();

        let snapshotTimer = 0;
        let trackTimer = 0;
        let messageTimer = 0;
        let weatherTimer = 0;

        const schedule = () => {
            window.clearInterval(snapshotTimer);
            window.clearInterval(trackTimer);
            window.clearInterval(messageTimer);
            window.clearInterval(weatherTimer);
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
            weatherTimer = window.setInterval(() => void loadWeather(), WEATHER_REFRESH_MS);
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

        return () => {
            window.clearInterval(snapshotTimer);
            window.clearInterval(trackTimer);
            window.clearInterval(messageTimer);
            window.clearInterval(weatherTimer);
            window.clearInterval(tick);
            document.removeEventListener("visibilitychange", onVisibility);
        };
    });
</script>

<svelte:head>
    <title>{data.meta.title}</title>
    <meta name="description" content={data.meta.description} />
    <meta property="og:type" content="website" />
    <meta property="og:title" content={data.meta.title} />
    <meta property="og:description" content={data.meta.description} />
    <meta property="og:image" content={data.meta.image} />
    <meta property="og:url" content={data.meta.url} />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content={data.meta.title} />
    <meta name="twitter:description" content={data.meta.description} />
    <meta name="twitter:image" content={data.meta.image} />
    <meta name="theme-color" content="#ffffff" />
    {#if !data.indexable}
        <meta name="robots" content="noindex, nofollow" />
    {/if}
</svelte:head>

<div class="lr page">
    <LiveHeader
        title={snapshot?.title || "Live Ride"}
        statusLabel={headerStatus.label}
        statusTone={headerStatus.tone}
        subtitle={route?.name && route.name !== snapshot?.title ? route.name : ""}
    />

    {#if linkDead}
        <div class="dead">
            <p class="headline">
                {snapshot?.status === "disabled"
                    ? "Zawodnik wyłączył udostępnianie tego przejazdu."
                    : "Ten link do śledzenia już nie działa."}
            </p>
            <p class="lr-body">
                Poproś o nowy — Live Ride generuje go jednym dotknięciem.
            </p>
        </div>
    {:else}
        <LiveMap
            bind:this={mapComponent}
            riders={mapRiders}
            selectedId={selected?.id ?? null}
            {routeCoordinates}
            {tracks}
            {trackVersion}
            meetup={snapshot?.meetup ?? null}
            onselect={selectRider}
        />

        <main class="body">
            {#if offline}
                <p class="notice">
                    Brak połączenia z serwerem. Pokazujemy ostatnie znane dane.
                </p>
            {/if}

            {#if selected}
                <RiderCard
                    name={selected.display_name}
                    statusLabel={selected.status.label}
                    statusTone={selected.status.tone}
                    ageSeconds={selected.ageSeconds}
                    colour={selected.colour}
                    hasFix={hasPosition(selected)}
                />
            {/if}

            {#if ended && summaryRider}
                <RideSummary
                    rider={summaryRider}
                    elapsedSeconds={snapshot?.summary?.elapsed_seconds ??
                        times.elapsedSeconds}
                    climbs={climbTotals}
                />
            {:else}
                <PrimaryMetrics
                    distanceMeters={selected?.distance_m}
                    {times}
                    speedKmh={liveSpeed}
                    remainingMeters={selected?.progress?.remainingMeters}
                    {averageSpeedKmh}
                    elevationGainMeters={selected?.elevation_gain_m}
                    altitudeMeters={selected?.altitude_m}
                    etaAt={selected?.progress?.etaAt ?? null}
                />
            {/if}

            {#if nav}
                <NavigationCard
                    {nav}
                    etaAt={selected?.progress?.etaAt ?? null}
                />
            {/if}

            {#if routeLengthMeters > 0 && !ended}
                <RouteProgressSection
                    routeName={route?.name ?? ""}
                    totalMeters={route?.distance_m || routeLengthMeters}
                    progress={selected?.progress ?? null}
                    {offRouteMeters}
                />
            {/if}

            {#if climbNow && !ended}
                <ClimbCard climb={climbNow} />
            {/if}

            {#if elevation}
                <ElevationProfile
                    profile={route?.elevation_profile ?? []}
                    {alongMeters}
                    insight={elevation}
                />
            {/if}

            {#if climbsAhead.length && !ended}
                <UpcomingClimbs
                    climbs={climbsAhead}
                    total={route?.climbs?.length ?? climbsAhead.length}
                    bind:expanded={allClimbs}
                />
            {/if}

            {#if forecasts.length && !ended}
                <RouteWeather {forecasts} {alert} {sunset} />
            {/if}

            {#if !ended}
                <SensorMetrics
                    heartRate={liveHeartRate}
                    power={livePower}
                    cadence={liveCadence}
                    batteryPercent={selected?.battery_percent}
                    maxSpeedKmh={selected?.max_speed_kmh}
                    gradientPercent={liveGradient}
                />
                <RideTimesSection {times} />
            {/if}

            {#if routeLengthMeters > 0}
                <RouteBriefing
                    totalMeters={route?.distance_m || routeLengthMeters}
                    ascentMeters={route?.ascent_m}
                    maxElevationMeters={elevation?.maxMeters ?? null}
                    climbs={climbTotals}
                    {surfaces}
                />
            {/if}

            {#if isGroup}
                <GroupRiders
                    riders={groupRiders}
                    selectedId={selected?.id ?? null}
                    onselect={selectRider}
                />
            {/if}

            {#if snapshot?.meetup}
                <MeetupCard
                    label={snapshot.meetup.label}
                    straightLineMeters={meetupDistance}
                    etaAt={meetupEta}
                />
            {/if}

            {#if messages.length}
                <LiveMessages {messages} />
            {/if}

            <p class="foot">
                Live Ride · śledzenie na żywo bez konta i bez aplikacji
            </p>
        </main>
    {/if}
</div>

<style>
    .page {
        min-height: 100vh;
        min-height: 100dvh;
        display: flex;
        flex-direction: column;
    }

    .body {
        display: flex;
        flex-direction: column;
        gap: 18px;
        padding: 14px 16px 36px;
        max-width: 720px;
        width: 100%;
        margin: 0 auto;
    }

    /* Bez tego siatki danych zapadają się do zera w przewijanej kolumnie
       na desktopie: element flex kurczy się do swojej minimalnej wysokości,
       a ta przy `overflow: hidden` wynosi zero. Na telefonie problem nie
       występuje, bo kolumna nie ma narzuconej wysokości — i dlatego łatwo go
       przeoczyć. */
    .body > :global(*) {
        flex: none;
    }

    .notice {
        margin: 0;
        padding: 9px 12px;
        border: 1px solid var(--lr-line-strong);
        background: var(--lr-panel);
        border-radius: var(--lr-radius);
        font-size: 12.5px;
        color: var(--lr-ink-soft);
    }

    .dead {
        padding: 40px 20px;
        max-width: 480px;
        margin: 0 auto;
        text-align: center;
    }

    .headline {
        margin: 0 0 8px;
        font-size: 17px;
        font-weight: 800;
        color: var(--lr-ink);
    }

    .foot {
        margin: 6px 0 0;
        text-align: center;
        font-size: 11px;
        letter-spacing: 0.6px;
        color: var(--lr-muted);
    }

    /* ------------------------------------------------------------ tablet */
    @media (min-width: 760px) {
        .page {
            --lr-map-height: 46vh;
        }
    }

    /* ----------------------------------------------------------- desktop */
    @media (min-width: 1040px) {
        .page {
            /* Mapa po lewej na całą wysokość okna, dane przewijają się obok.
               To wciąż ta sama aplikacja, tylko z miejscem na obie rzeczy
               naraz — a nie pulpit z dwunastoma kafelkami. */
            display: grid;
            grid-template-columns: minmax(0, 1fr) 460px;
            grid-template-rows: auto 1fr;
            height: 100vh;
            height: 100dvh;
            overflow: hidden;
        }

        .page > :global(header) {
            grid-column: 1 / -1;
        }

        .page > :global(.wrap) {
            grid-column: 1;
            grid-row: 2;
            height: 100%;
            border-bottom: none;
            border-right: 1px solid var(--lr-line);
        }

        .page > :global(.wrap) :global(.canvas) {
            height: 100%;
        }

        .body {
            grid-column: 2;
            grid-row: 2;
            overflow-y: auto;
            max-width: none;
            padding: 16px 18px 40px;
        }

        .dead {
            grid-column: 1 / -1;
        }
    }
</style>
