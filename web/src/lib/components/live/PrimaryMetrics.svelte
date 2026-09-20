<script lang="ts">
    import Field from "./Field.svelte";
    import {
        clock,
        distance as fmtDistance,
        duration as fmtDuration,
        num,
        type RideTimes,
    } from "$lib/live/live_viewer";

    /**
     * Cztery liczby, po które ktoś tu wszedł: ile przejechał, jak długo,
     * jak szybko i ile zostało. Reszta jest niżej.
     *
     * Pola bez danych pokazują kreskę, ale „DO METY" znika w całości, gdy
     * jazda nie ma trasy — puste pole sugeruje, że meta istnieje i tylko
     * czegoś nie doliczyliśmy.
     */
    let {
        distanceMeters,
        times,
        speedKmh,
        remainingMeters,
        averageSpeedKmh,
        elevationGainMeters,
        altitudeMeters,
        etaAt,
    }: {
        distanceMeters: number | undefined;
        times: RideTimes;
        speedKmh: number | undefined;
        remainingMeters: number | undefined;
        averageSpeedKmh: number | undefined;
        elevationGainMeters: number | undefined;
        altitudeMeters: number | undefined;
        etaAt: Date | null;
    } = $props();

    const hasSecondRow = $derived(
        averageSpeedKmh !== undefined ||
            elevationGainMeters !== undefined ||
            altitudeMeters !== undefined ||
            etaAt !== null ||
            times.pausedSeconds !== undefined,
    );
</script>

<div class="lr-grid">
    <Field label="Dystans" value={fmtDistance(distanceMeters)} size={30} />
    <Field
        label="Czas w ruchu"
        value={fmtDuration(times.movingSeconds)}
        size={30}
    />
    <Field label="Prędkość" value={num(speedKmh, 1)} unit="km/h" size={30} />
    {#if remainingMeters !== undefined}
        <Field label="Do mety" value={fmtDistance(remainingMeters)} size={30} />
    {:else}
        <Field
            label="Czas całkowity"
            value={fmtDuration(times.elapsedSeconds)}
            size={30}
        />
    {/if}
</div>

{#if hasSecondRow}
    <div class="lr-grid second">
        <Field label="Średnia" value={num(averageSpeedKmh, 1)} unit="km/h" />
        <Field
            label="Przewyższenie"
            value={num(elevationGainMeters, 0)}
            unit="m"
        />
        {#if remainingMeters !== undefined}
            <Field
                label="Czas całkowity"
                value={fmtDuration(times.elapsedSeconds)}
            />
        {:else}
            <Field label="Wysokość" value={num(altitudeMeters, 0)} unit="m" />
        {/if}
        {#if etaAt}
            <Field label="ETA" value={clock(etaAt.toISOString())} />
        {:else if times.pausedSeconds !== undefined}
            <Field label="Postoje" value={fmtDuration(times.pausedSeconds)} />
        {:else}
            <Field label="Wysokość" value={num(altitudeMeters, 0)} unit="m" />
        {/if}
    </div>
{/if}

<style>
    .second {
        margin-top: 8px;
    }
</style>
