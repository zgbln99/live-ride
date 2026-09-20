<script lang="ts">
    import Section from "./Section.svelte";
    import Field from "./Field.svelte";
    import { num } from "$lib/live/live_viewer";

    /**
     * Czujniki i bateria.
     *
     * Pole, którego zawodnik nie udostępnia, nie przychodzi z serwera i nie
     * pojawia się tutaj — nie jako kreska, tylko w ogóle. Sekcja znika
     * w całości, gdy nie ma czego pokazać: panel „MOC —" mówi obserwującemu,
     * że coś się zepsuło, choć po prostu nikt nie ma miernika.
     */
    let {
        heartRate,
        power,
        cadence,
        batteryPercent,
        maxSpeedKmh,
    }: {
        heartRate: number | undefined;
        power: number | undefined;
        cadence: number | undefined;
        batteryPercent: number | undefined;
        maxSpeedKmh: number | undefined;
    } = $props();

    const anything = $derived(
        heartRate !== undefined ||
            power !== undefined ||
            cadence !== undefined ||
            batteryPercent !== undefined ||
            maxSpeedKmh !== undefined,
    );
</script>

{#if anything}
    <Section title="Dane z jazdy">
        <div class="lr-grid">
            {#if heartRate !== undefined}
                <Field label="Tętno" value={num(heartRate, 0)} unit="bpm" />
            {/if}
            {#if power !== undefined}
                <Field label="Moc" value={num(power, 0)} unit="W" />
            {/if}
            {#if cadence !== undefined}
                <Field label="Kadencja" value={num(cadence, 0)} unit="rpm" />
            {/if}
            {#if maxSpeedKmh !== undefined}
                <Field
                    label="Prędkość maks."
                    value={num(maxSpeedKmh, 1)}
                    unit="km/h"
                />
            {/if}
            {#if batteryPercent !== undefined}
                <Field label="Telefon" value={num(batteryPercent, 0)} unit="%" />
            {/if}
        </div>
    </Section>
{/if}
