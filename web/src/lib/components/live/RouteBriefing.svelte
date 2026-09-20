<script lang="ts">
    import Section from "./Section.svelte";
    import Field from "./Field.svelte";
    import { distance as fmtDistance, num } from "$lib/live/live_viewer";
    import type { ClimbSummary, SurfaceShare } from "$lib/live/route_insight";

    /**
     * O trasie: liczby, które nie zmieniają się w trakcie jazdy.
     *
     * Osobno od postępu, bo odpowiadają na inne pytanie — nie „gdzie on
     * jest", tylko „w co się wpakował".
     */
    let {
        totalMeters,
        ascentMeters,
        maxElevationMeters,
        climbs,
        surfaces,
    }: {
        totalMeters: number | undefined;
        ascentMeters: number | undefined;
        maxElevationMeters: number | null;
        climbs: ClimbSummary | null;
        surfaces: SurfaceShare[];
    } = $props();
</script>

<Section title="O trasie">
    <div class="lr-grid">
        <Field label="Dystans" value={fmtDistance(totalMeters)} />
        <Field label="Przewyższenie" value={num(ascentMeters, 0)} unit="m ↑" />
        {#if climbs}
            <Field label="Podjazdy" value={String(climbs.count)} />
        {/if}
        {#if maxElevationMeters !== null}
            <Field
                label="Najwyżej"
                value={num(maxElevationMeters, 0)}
                unit="m"
            />
        {/if}
    </div>

    {#if climbs}
        <div class="lr-grid">
            <Field
                label="Łącznie w górę"
                value={num(climbs.totalGainMeters, 0)}
                unit="m"
            />
            {#if climbs.longest}
                <Field
                    label="Największy"
                    value={fmtDistance(climbs.longest.length_m)}
                    hint="{num(climbs.longest.gain_m, 0)} m ↑"
                />
            {/if}
            {#if climbs.steepestPercent !== null}
                <Field
                    label="Najstromszy"
                    value={num(climbs.steepestPercent, 1)}
                    unit="%"
                />
            {/if}
        </div>
    {/if}

    {#if surfaces.length}
        <ul class="lr-panel surfaces">
            {#each surfaces as share (share.label)}
                <li>
                    <span class="what">{share.label}</span>
                    <span class="how-much">
                        {fmtDistance(share.meters)}
                        <em>{Math.round(share.fraction * 100)}%</em>
                    </span>
                </li>
            {/each}
        </ul>
    {/if}
</Section>

<style>
    .surfaces {
        list-style: none;
        margin: 0;
        padding: 0;
    }

    li {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 12px;
        padding: 9px 14px;
        font-size: 13px;
    }

    li + li {
        border-top: 1px solid var(--lr-line);
    }

    .what {
        font-weight: 700;
        color: var(--lr-ink);
    }

    .how-much {
        color: var(--lr-ink-soft);
    }

    em {
        font-style: normal;
        font-weight: 800;
        color: var(--lr-ink);
        margin-left: 8px;
    }
</style>
