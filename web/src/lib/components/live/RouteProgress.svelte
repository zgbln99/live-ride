<script lang="ts">
    import Section from "./Section.svelte";
    import Field from "./Field.svelte";
    import {
        clock,
        distance as fmtDistance,
        durationCoarse,
        type RouteProgress,
    } from "$lib/live/live_viewer";

    /**
     * Ile trasy za nim, ile przed nim, kiedy dojedzie.
     *
     * Cała sekcja pojawia się wyłącznie przy jeździe z zaplanowaną trasą.
     * Przy wolnej jeździe nie ma mety, więc nie ma też postępu — pasek
     * postępu do celu, którego nikt nie wyznaczył, byłby wymysłem.
     */
    let {
        routeName,
        totalMeters,
        progress,
        offRouteMeters,
    }: {
        routeName: string;
        totalMeters: number;
        progress: RouteProgress | null;
        offRouteMeters: number | null;
    } = $props();

    const percent = $derived(
        progress ? Math.round(progress.fraction * 100) : null,
    );
</script>

<Section title="Trasa" aside={fmtDistance(totalMeters)}>
    <div class="lr-panel wrap">
        {#if routeName}
            <p class="name">{routeName}</p>
        {/if}

        {#if progress}
            <div class="bar">
                <div class="lr-track">
                    <span style="width: {percent}%"></span>
                </div>
                <span class="percent">{percent}%</span>
            </div>
        {/if}
    </div>

    {#if progress}
        <div class="lr-grid">
            <Field label="Przejechano" value={fmtDistance(progress.alongMeters)} />
            <Field label="Pozostało" value={fmtDistance(progress.remainingMeters)} />
            <Field
                label="Szacowany czas"
                value={progress.etaSeconds != null
                    ? durationCoarse(progress.etaSeconds)
                    : "—"}
                size={21}
            />
            <Field
                label="ETA"
                value={progress.etaAt ? clock(progress.etaAt.toISOString()) : "—"}
                tone="accent"
            />
        </div>
    {/if}

    {#if offRouteMeters !== null}
        <p class="off">Poza trasą · {fmtDistance(offRouteMeters)}</p>
    {/if}
</Section>

<style>
    .wrap {
        padding: 12px 14px;
        display: flex;
        flex-direction: column;
        gap: 10px;
    }

    .name {
        margin: 0;
        font-size: 15px;
        font-weight: 800;
        color: var(--lr-ink);
    }

    .bar {
        display: flex;
        align-items: center;
        gap: 10px;
    }

    .bar .lr-track {
        flex: 1;
    }

    .percent {
        font-size: 13px;
        font-weight: 900;
        color: var(--lr-ink);
        min-width: 38px;
        text-align: right;
    }

    .off {
        margin: 0;
        padding: 9px 12px;
        border: 1px solid rgba(224, 43, 32, 0.4);
        background: rgba(224, 43, 32, 0.08);
        border-radius: var(--lr-radius);
        font-size: 12.5px;
        font-weight: 700;
        color: #a5180f;
    }
</style>
