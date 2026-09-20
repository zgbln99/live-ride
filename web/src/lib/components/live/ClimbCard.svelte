<script lang="ts">
    import Section from "./Section.svelte";
    import Field from "./Field.svelte";
    import { distance as fmtDistance, num } from "$lib/live/live_viewer";
    import { normalizeGradient, type PlacedClimb } from "$lib/live/route_insight";

    /**
     * Podjazd, na którym zawodnik właśnie jest.
     *
     * Najważniejsza liczba to nie długość podjazdu, tylko ile z niego zostało
     * — bo to jedyna rzecz, o którą pyta ktoś, kto na nim stoi, i jedyna,
     * o którą pyta ktoś, kto go obserwuje.
     */
    let { climb }: { climb: PlacedClimb } = $props();

    const percent = $derived(Math.round(climb.fraction * 100));
    const maximum = $derived(
        climb.max_gradient === undefined
            ? null
            : normalizeGradient(climb.max_gradient),
    );
    const gainToTop = $derived(
        Math.max(0, Math.round(climb.gain_m * (1 - climb.fraction))),
    );
</script>

<Section title="Aktualny podjazd">
    <div class="lr-panel head">
        <div class="row">
            <span class="name">{climb.name || "Podjazd"}</span>
            {#if climb.category}<span class="cat">{climb.category}</span>{/if}
        </div>
        <div class="row measure">
            <span class="done">{fmtDistance(climb.doneMeters)}</span>
            <span class="of">z {fmtDistance(climb.length_m)}</span>
        </div>
        <div class="lr-track"><span style="width: {percent}%"></span></div>
    </div>

    <div class="lr-grid">
        <Field
            label="Zostało"
            value={fmtDistance(climb.remainingMeters)}
            tone="accent"
        />
        <Field label="Do szczytu" value={num(gainToTop, 0)} unit="m ↑" />
        <Field
            label="Średnio"
            value={num(normalizeGradient(climb.avg_gradient), 1)}
            unit="%"
        />
        {#if maximum !== null}
            <Field label="Maks." value={num(maximum, 1)} unit="%" />
        {:else}
            <Field label="Przewyższenie" value={num(climb.gain_m, 0)} unit="m" />
        {/if}
    </div>
</Section>

<style>
    .head {
        padding: 12px 14px;
        display: flex;
        flex-direction: column;
        gap: 9px;
    }

    .row {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 10px;
    }

    .name {
        font-size: 15px;
        font-weight: 800;
        color: var(--lr-ink);
    }

    .cat {
        font-size: 10.5px;
        font-weight: 900;
        letter-spacing: 1px;
        color: var(--lr-accent-deep);
        border: 1px solid rgba(0, 144, 168, 0.4);
        border-radius: var(--lr-radius);
        padding: 2px 6px;
    }

    .measure {
        justify-content: flex-start;
        gap: 6px;
    }

    .done {
        font-size: 22px;
        font-weight: 800;
        letter-spacing: -0.03em;
        color: var(--lr-ink);
    }

    .of {
        font-size: 13px;
        color: var(--lr-ink-soft);
        font-weight: 700;
    }
</style>
