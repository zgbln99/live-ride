<script lang="ts">
    import Section from "./Section.svelte";
    import Field from "./Field.svelte";
    import {
        distance as fmtDistance,
        duration as fmtDuration,
        num,
        type SummaryRider,
    } from "$lib/live/live_viewer";
    import type { ClimbSummary } from "$lib/live/route_insight";

    /**
     * Podsumowanie po mecie.
     *
     * Ta sama strona, ten sam wygląd — zmienia się tylko to, że liczby
     * przestają rosnąć. Znajomy, który otworzy link wieczorem, ma zobaczyć
     * przejazd, a nie komunikat, że coś się skończyło.
     */
    let {
        rider,
        elapsedSeconds,
        climbs,
    }: {
        rider: SummaryRider | null;
        elapsedSeconds: number | undefined;
        climbs: ClimbSummary | null;
    } = $props();

    const averageSpeedKmh = $derived(
        rider?.avg_speed_kmh ??
            (rider?.distance_m !== undefined &&
            rider?.moving_seconds !== undefined &&
            rider.moving_seconds > 0
                ? (rider.distance_m / rider.moving_seconds) * 3.6
                : undefined),
    );
</script>

<Section title="Podsumowanie przejazdu">
    <div class="lr-grid">
        <Field label="Dystans" value={fmtDistance(rider?.distance_m)} size={30} />
        <Field
            label="Czas w ruchu"
            value={fmtDuration(rider?.moving_seconds)}
            size={30}
        />
        <Field
            label="Czas całkowity"
            value={fmtDuration(elapsedSeconds)}
            size={30}
        />
        <Field
            label="Średnia"
            value={num(averageSpeedKmh, 1)}
            unit="km/h"
            size={30}
        />
    </div>

    <div class="lr-grid">
        <Field label="Maks." value={num(rider?.max_speed_kmh, 1)} unit="km/h" />
        <Field
            label="Przewyższenie"
            value={num(rider?.elevation_gain_m, 0)}
            unit="m"
        />
        {#if rider?.avg_heart_rate_bpm !== undefined}
            <Field
                label="Tętno śr."
                value={num(rider.avg_heart_rate_bpm, 0)}
                unit="bpm"
                hint={rider.max_heart_rate_bpm !== undefined
                    ? `maks. ${Math.round(rider.max_heart_rate_bpm)}`
                    : ""}
            />
        {/if}
        {#if rider?.avg_power_watts !== undefined}
            <Field
                label="Moc śr."
                value={num(rider.avg_power_watts, 0)}
                unit="W"
                hint={rider.max_power_watts !== undefined
                    ? `maks. ${Math.round(rider.max_power_watts)}`
                    : ""}
            />
        {/if}
    </div>

    {#if climbs}
        <div class="lr-grid">
            <Field label="Podjazdy" value={String(climbs.count)} />
            <Field
                label="Łącznie w górę"
                value={num(climbs.totalGainMeters, 0)}
                unit="m"
            />
        </div>
    {/if}
</Section>
