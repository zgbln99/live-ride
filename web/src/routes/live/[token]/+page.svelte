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
    import RiderInsights from "$lib/components/live/RiderInsights.svelte";
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
    import Timeline from "$lib/components/live/Timeline.svelte";
    import Checkpoints from "$lib/components/live/Checkpoints.svelte";
    import NearProfile from "$lib/components/live/NearProfile.svelte";
    import TimeMachine from "$lib/components/live/TimeMachine.svelte";
    import SafetyAlert from "$lib/components/live/SafetyAlert.svelte";

    import {
        RIDER_COLOURS,
        clock as clockLabel,
        cumulativeDistances,
        freshValue,
        hasPosition,
        haversine,
        liveOnly,
        paceKmh,
        placeCheckpoints,
        projectOnRoute,
        relativeGap,
        rideTimes,
        riderStatus,
        routeProgress,
        type HistoryRider,
        type HistorySnapshot,
        type LiveEvent,
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
    /** Odpytywanie, gdy strumień działa — już tylko jako siatka bezpieczeństwa. */
    const STREAM_FALLBACK_REFRESH_MS = 30000;

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
    let events = $state<LiveEvent[]>([]);
    let history = $state<HistoryRider[]>([]);
    /**
     * Wybrana chwila z przeszłości albo null, gdy oglądamy bieżący stan.
     *
     * Cofnięcie NIE przerywa transmisji: telemetria dalej przychodzi, a strona
     * po prostu przez chwilę pokazuje co innego — i mówi o tym wprost, żeby
     * nikt nie pomylił nagrania z bieżącą pozycją.
     */
    let rewindIndex = $state<number | null>(null);
    let offline = $state(false);
    let selectedRiderId = $state<string | null>(null);
    let allClimbs = $state(false);
    let mapComponent = $state<LiveMap | null>(null);
    /** Czy strumień zdarzeń jest podłączony. Polling działa niezależnie. */
    let streaming = $state(false);

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
    let routeCumulative = $state<number[]>([]);
    let routeLengthMeters = $state(0);

    /**
     * Nazwa i długość planu z pierwszej odpowiedzi HTML.
     *
     * Ustępuje pobranej trasie, gdy tylko ta dojedzie — ale do tego czasu
     * nagłówek i sekcja trasy mają co pokazać zamiast pustej ramki.
     */
    const routeName = $derived(route?.name ?? data.routeMeta?.name ?? "");
    const routeTotalMeters = $derived(
        route?.distance_m || routeLengthMeters || data.routeMeta?.distance_m || 0,
    );

    /**
     * Numer wersji planu, który mamy narysowany.
     *
     * Trasa potrafi się zmienić w trakcie jazdy — zawodnik przelicza ją po
     * zjechaniu albo przestawia punkt. Pobieranie całej geometrii co kilka
     * sekund „na wszelki wypadek" byłoby najdroższą rzeczą na tej stronie,
     * więc porównujemy liczbę z migawki i pobieramy tylko wtedy, gdy urosła.
     */
    let routeRevision = -1;
    /** Najwyższy numer zdarzenia, który już mamy na osi czasu. */
    let eventSeq = -1;

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
    /** Przebieg wybranego zawodnika i próbka, na której stoi suwak. */
    const historySamples = $derived(
        history.find((entry) => entry.participant === selected?.id)?.samples ?? [],
    );
    const rewound = $derived(
        rewindIndex === null ? null : (historySamples[rewindIndex] ?? null),
    );

    const liveSpeed = $derived(
        rewound
            ? rewound.speed_kmh
            : selected
              ? liveOnly(selected.speed_kmh, tone)
              : undefined,
    );
    /**
     * Odczyty czujników, każdy z własnym terminem ważności.
     *
     * Świeżość całej transmisji nie wystarcza: GPS potrafi nadawać co
     * sekundę, gdy pas HR zsunął się z klatki cztery minuty wcześniej.
     * Wtedy „♥ 143" jest nie tyle nieaktualne, co nieprawdziwe — a wygląda
     * dokładnie tak samo jak pomiar sprzed sekundy.
     */
    const liveHeartRate = $derived(
        rewound
            ? rewound.heart_rate_bpm
            : selected
              ? freshValue(
                    liveOnly(selected.heart_rate_bpm, tone),
                    selected.hr_updated_at,
                    serverNow,
                )
              : undefined,
    );
    const livePower = $derived(
        rewound
            ? rewound.power_watts
            : selected
              ? freshValue(
                    liveOnly(selected.power_watts, tone),
                    selected.power_updated_at,
                    serverNow,
                )
              : undefined,
    );
    const liveCadence = $derived(
        rewound
            ? rewound.cadence_rpm
            : selected
              ? freshValue(
                    liveOnly(selected.cadence_rpm, tone),
                    selected.cadence_updated_at,
                    serverNow,
                )
              : undefined,
    );

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
    const nav = $derived(ended || rewound ? null : (selected?.nav ?? null));

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
    const checkpoints = $derived(
        placeCheckpoints(route?.checkpoints, alongMeters, pace, serverNow),
    );

    /**
     * Czy strona ma przestawić priorytety na podjazd.
     *
     * Na podjeździe liczy się nachylenie, to, ile zostało, i tętno — mapa
     * pokazuje wtedy głównie to, że ktoś jedzie wolno. Sekcje zmieniają
     * kolejność, ale żadna nie znika: układ, który coś chowa, zmusza widza
     * do zapamiętania, gdzie to było.
     */
    const climbFocus = $derived(climbNow !== null && !ended);

    /** Najnowszy alert bezpieczeństwa, jeśli w tej jeździe jakiś padł. */
    const safetyAlert = $derived(events.find((event) => event.kind === "sos") ?? null);
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
            lngLat:
                rewound && rider.id === selected?.id
                    ? ([rewound.lon, rewound.lat] as LngLat)
                    : hasPosition(rider)
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

    /**
     * Przyjmuje migawkę niezależnie od tego, czy przyszła strumieniem, czy
     * odpytaniem.
     *
     * Jedno miejsce dla obu dróg, bo inaczej strumień i polling z czasem
     * zaczęłyby robić trochę co innego — a różnica ujawniłaby się dopiero
     * u kogoś, komu pośrednik uciął SSE.
     */
    function applySnapshot(next: Snapshot) {
        fetched = next;
        applyServerTime(next.server_time);
        now = Date.now();
        offline = false;

        // Geometria pobierana tylko wtedy, gdy naprawdę się zmieniła.
        const revision = next.route_revision ?? 0;
        if (revision !== routeRevision) {
            routeRevision = revision;
            void loadRoute();
        }
        // Oś czasu dociągana tylko wtedy, gdy przybyło zdarzeń.
        const seq = next.event_seq ?? 0;
        if (seq !== eventSeq) {
            eventSeq = seq;
            void loadEvents();
        }
    }

    async function refresh() {
        try {
            const response = await fetch(api(""), { cache: "no-store" });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            applySnapshot((await response.json()) as Snapshot);
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

    /**
     * Przebieg jazdy: pełny po mecie, ostatnie pół godziny w trakcie.
     *
     * Pobierany RAZ na wejście i po zakończeniu — nie co odświeżenie. Suwak
     * po zakończonej jeździe ma sens od pierwszej sekundy, a w trwającej
     * transmisji to, co widać cofniętym, i tak jest przeszłością.
     */
    async function loadHistory() {
        try {
            const window_ = ended ? "" : "?minutes=30";
            const response = await fetch(api(`/history${window_}`), { cache: "no-store" });
            if (!response.ok) return;
            const payload = (await response.json()) as HistorySnapshot;
            history = payload.riders ?? [];
        } catch {
            // Bez historii znika suwak, nie strona.
        }
    }

    async function loadEvents() {
        try {
            const response = await fetch(api("/events"), { cache: "no-store" });
            if (!response.ok) return;
            const payload = (await response.json()) as { events?: LiveEvent[] };
            events = payload.events ?? [];
        } catch {
            // Oś czasu jest opowieścią o jeździe, nie warunkiem jej oglądania.
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

    /**
     * Strumień zmian.
     *
     * Odpytywanie co trzy sekundy znaczy, że widz dowiaduje się o skręcie
     * średnio półtorej sekundy po tym, jak zawodnik go zrobił. Dla dystansu
     * bez znaczenia; dla manewru i dla „zjechał z trasy" to różnica między
     * oglądaniem jazdy a oglądaniem jej nagrania.
     *
     * Polling zostaje włączony przez cały czas jako zapas — tyle że rzadszy.
     * Pośrednik, który utnie długie połączenie, nie ma prawa zatrzymać
     * strony; zwolni ją najwyżej do tempa sprzed tej zmiany.
     */
    function connectStream(): () => void {
        if (typeof EventSource === "undefined") return () => {};
        let source: EventSource | null = null;
        let retry = 0;
        let retryTimer = 0;
        let closed = false;

        const open = () => {
            if (closed) return;
            source = new EventSource(api("/stream"));
            source.addEventListener("snapshot", (message) => {
                retry = 0;
                streaming = true;
                try {
                    applySnapshot(JSON.parse((message as MessageEvent).data) as Snapshot);
                } catch {
                    // Uszkodzona wiadomość nie ma prawa wywrócić strony —
                    // najbliższe odpytanie i tak przyniesie pełny stan.
                }
            });
            source.addEventListener("status", () => {
                void refresh();
            });
            source.onerror = () => {
                streaming = false;
                source?.close();
                source = null;
                if (closed) return;
                // Odstępy rosną, ale nigdy ponad minutę: zerwany strumień to
                // zwykle pośrednik, a nie awaria, i warto próbować dalej.
                retry = Math.min(retry + 1, 6);
                retryTimer = window.setTimeout(open, Math.min(60000, 2 ** retry * 1000));
            };
        };
        open();

        return () => {
            closed = true;
            window.clearTimeout(retryTimer);
            source?.close();
        };
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

        void refresh();
        void loadTrack();
        void loadWeather();
        void loadMessages();
        void loadHistory();
        const closeStream = connectStream();

        let snapshotTimer = 0;
        let trackTimer = 0;
        let messageTimer = 0;
        let weatherTimer = 0;
        let historyTimer = 0;

        const schedule = () => {
            window.clearInterval(snapshotTimer);
            window.clearInterval(trackTimer);
            window.clearInterval(messageTimer);
            window.clearInterval(weatherTimer);
            window.clearInterval(historyTimer);
            if (ended) return;
            // Karta w tle dostaje rzadsze odświeżanie: przeglądarka i tak
            // dławi timery, a bateria telefonu widza nie jest za darmo.
            // Przy działającym strumieniu odpytywanie jest tylko siatką
            // bezpieczeństwa na zgubioną wiadomość, więc schodzi z trzech
            // sekund na trzydzieści.
            const period = document.hidden
                ? BACKGROUND_REFRESH_MS
                : streaming
                  ? STREAM_FALLBACK_REFRESH_MS
                  : REFRESH_MS;
            snapshotTimer = window.setInterval(() => void refresh(), period);
            trackTimer = window.setInterval(
                () => void loadTrack(),
                document.hidden ? BACKGROUND_REFRESH_MS * 2 : TRACK_REFRESH_MS,
            );
            messageTimer = window.setInterval(() => void loadMessages(), 20000);
            // Okno cofania przesuwa się razem z jazdą, ale wolno: to nie jest
            // dana, na którą ktokolwiek czeka.
            historyTimer = window.setInterval(() => void loadHistory(), 120000);
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

        // Zmiana stanu strumienia przestawia tempo odpytywania.
        const streamWatch = window.setInterval(schedule, 15000);

        return () => {
            closeStream();
            window.clearInterval(streamWatch);
            window.clearInterval(snapshotTimer);
            window.clearInterval(trackTimer);
            window.clearInterval(messageTimer);
            window.clearInterval(weatherTimer);
            window.clearInterval(historyTimer);
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
        subtitle={routeName && routeName !== snapshot?.title ? routeName : ""}
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
        <div class="stage">
            <LiveMap
                bind:this={mapComponent}
                riders={mapRiders}
                selectedId={selected?.id ?? null}
                {routeCoordinates}
                {routeCumulative}
                {alongMeters}
                checkpoints={route?.checkpoints ?? []}
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

            {#if safetyAlert}
                <SafetyAlert at={safetyAlert.at} />
            {/if}

            {#if rewound}
                <!-- Najważniejsze zdanie na stronie w tym trybie: liczby
                     poniżej nie są bieżące. -->
                <p class="rewind">
                    Podgląd z {clockLabel(rewound.at)} — to nie jest bieżąca pozycja.
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
                    {routeName}
                    totalMeters={routeTotalMeters}
                    progress={selected?.progress ?? null}
                    {offRouteMeters}
                />
            {/if}

            <!-- Na podjeździe kolejność się odwraca: najpierw podjazd
                 i czujniki, dopiero potem profil i pogoda. Nic nie znika —
                 układ, który coś chowa, zmusza widza do zapamiętania,
                 gdzie to było. -->
            {#if climbNow && !ended}
                <ClimbCard climb={climbNow} />
            {/if}

            <!-- Zdania licznika tuż pod podjazdem: to samo miejsce, w którym
                 zawodnik je widzi, i ta sama kolejność. Serwer przysłał
                 wyłącznie to, na co jest zgoda — strona nie ma tu nic do
                 odfiltrowania. -->
            {#if !ended && selected?.insights?.length}
                <RiderInsights insights={selected.insights} />
            {/if}

            {#if climbFocus && !ended}
                <SensorMetrics
                    heartRate={liveHeartRate}
                    power={livePower}
                    cadence={liveCadence}
                    batteryPercent={selected?.battery_percent}
                    maxSpeedKmh={selected?.max_speed_kmh}
                    gradientPercent={liveGradient}
                />
            {/if}

            {#if elevation}
                <ElevationProfile
                    profile={route?.elevation_profile ?? []}
                    {alongMeters}
                    insight={elevation}
                />
            {/if}

            {#if !ended}
                <NearProfile profile={route?.elevation_profile ?? []} {alongMeters} />
            {/if}

            {#if climbsAhead.length && !ended}
                <UpcomingClimbs
                    climbs={climbsAhead}
                    total={route?.climbs?.length ?? climbsAhead.length}
                    bind:expanded={allClimbs}
                />
            {/if}

            {#if !ended}
                <Checkpoints {checkpoints} />
            {/if}

            {#if forecasts.length && !ended}
                <RouteWeather {forecasts} {alert} {sunset} />
            {/if}

            {#if !ended && !climbFocus}
                <SensorMetrics
                    heartRate={liveHeartRate}
                    power={livePower}
                    cadence={liveCadence}
                    batteryPercent={selected?.battery_percent}
                    maxSpeedKmh={selected?.max_speed_kmh}
                    gradientPercent={liveGradient}
                />
            {/if}

            {#if !ended}
                <RideTimesSection {times} />
            {/if}

            {#if routeLengthMeters > 0}
                <RouteBriefing
                    totalMeters={routeTotalMeters}
                    ascentMeters={route?.ascent_m ?? data.routeMeta?.ascent_m}
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

            <TimeMachine
                count={historySamples.length}
                index={rewindIndex}
                at={rewound?.at ?? null}
                {ended}
                onseek={(index) => (rewindIndex = index)}
                onlive={() => (rewindIndex = null)}
            />

            <Timeline {events} />

            <p class="foot">
                Live Ride · śledzenie na żywo bez konta i bez aplikacji
            </p>
            </main>
        </div>
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

    /* Pasek cofnięcia jest ostrzeżeniem, nie ozdobą: dopóki wisi, żadna
       liczba na tej stronie nie opisuje tej chwili. */
    .rewind {
        margin: 0;
        padding: 9px 12px;
        border: 1px solid var(--lr-line-strong);
        background: var(--lr-ink);
        color: var(--lr-surface);
        border-radius: var(--lr-radius);
        font-size: 12.5px;
        font-weight: 700;
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
            height: 100vh;
            height: 100dvh;
            overflow: hidden;
        }

        /* Mapa po lewej na całą wysokość okna, dane przewijają się obok.
           To wciąż ta sama aplikacja, tylko z miejscem na obie rzeczy naraz
           — a nie pulpit z dwunastoma kafelkami. Kolejność sekcji zostaje
           identyczna jak na telefonie: widz, który zna jedną, zna obie. */
        .stage {
            flex: 1;
            min-height: 0;
            display: grid;
            grid-template-columns: minmax(0, 1fr) 460px;
        }

        .stage > :global(.wrap) {
            height: 100%;
            border-bottom: none;
            border-right: 1px solid var(--lr-line);
        }

        .stage > :global(.wrap) :global(.canvas) {
            height: 100%;
        }

        .body {
            overflow-y: auto;
            max-width: none;
            padding: 16px 18px 40px;
        }
    }

</style>
