<script lang="ts">
    import Section from "./Section.svelte";
    import Field from "./Field.svelte";
    import {
        clock,
        distance as fmtDistance,
        durationCoarse,
        type RouteProgress,
    } from "$lib/live/live_viewer";

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
    <div class="progress-head">
        <div class="copy">
            {#if routeName}<p class="name">{routeName}</p>{/if}
            {#if progress}
                <p class="summary">
                    {fmtDistance(progress.alongMeters)} przejechane · {fmtDistance(
                        progress.remainingMeters,
                    )} zostało
                </p>
            {/if}
        </div>
        {#if progress}<span class="percent">{percent}%</span>{/if}
    </div>

    {#if progress}
        <div class="lr-track" aria-label={`Postęp trasy ${percent}%`}>
            <span style="width: {percent}%"></span>
        </div>

        <div class="lr-grid stats">
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
    .progress-head {
        display: flex;
        align-items: flex-end;
        justify-content: space-between;
        gap: 16px;
        padding-top: 4px;
    }

    .copy {
        min-width: 0;
    }

    .name {
        margin: 0;
        font-size: 15px;
        font-weight: 700;
        letter-spacing: -0.02em;
        color: var(--lr-ink);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    .summary {
        margin: 4px 0 0;
        font-size: 11.5px;
        color: var(--lr-muted);
    }

    .percent {
        flex: none;
        font-size: 25px;
        font-weight: 720;
        letter-spacing: -0.045em;
        line-height: 1;
        color: var(--lr-ink);
    }

    .stats {
        margin-top: 2px;
    }

    .off {
        margin: 0;
        padding: 9px 0;
        border-top: 1px solid color-mix(in srgb, var(--lr-alert) 35%, var(--lr-line));
        border-bottom: 1px solid color-mix(in srgb, var(--lr-alert) 35%, var(--lr-line));
        font-size: 12px;
        font-weight: 650;
        color: var(--lr-alert);
    }
</style>
