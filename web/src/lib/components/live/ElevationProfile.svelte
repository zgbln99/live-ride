<script lang="ts">
    import Section from "./Section.svelte";
    import Field from "./Field.svelte";
    import { elevationAtDistance, type ElevationInsight, type ElevationPoint } from "$lib/live/route_insight";
    import { num } from "$lib/live/live_viewer";

    /**
     * Profil wysokości z zaznaczoną pozycją.
     *
     * Przejechana część jest wypełniona i mocna, pozostała pusta i cienka —
     * ta sama zasada co na mapie, gdzie ślad jest ciągły, a plan przerywany.
     * Bez legendy, bo legenda do dwóch stanów to przyznanie się, że rysunek
     * jest nieczytelny.
     */
    let {
        profile,
        alongMeters,
        insight,
    }: {
        profile: ElevationPoint[];
        alongMeters: number | null;
        insight: ElevationInsight;
    } = $props();

    const WIDTH = 100;
    const HEIGHT = 30;

    const geometry = $derived.by(() => {
        if (profile.length < 2) return null;
        const total = profile[profile.length - 1].d || 1;
        const span = Math.max(20, insight.maxMeters - insight.minMeters);
        const x = (d: number) => (d / total) * WIDTH;
        const y = (e: number) =>
            HEIGHT - ((e - insight.minMeters) / span) * (HEIGHT - 3) - 1.5;

        const line = profile
            .map((point, i) => `${i ? "L" : "M"}${x(point.d).toFixed(2)} ${y(point.e).toFixed(2)}`)
            .join(" ");

        // Przejechana część jako osobny obszar, obcięty w miejscu zawodnika.
        let done: string | null = null;
        if (alongMeters !== null && alongMeters > 0) {
            const passed = profile.filter((point) => point.d <= alongMeters);
            const hereElevation = elevationAtDistance(profile, alongMeters);
            if (passed.length && hereElevation !== null) {
                const path = passed
                    .map((point, i) => `${i ? "L" : "M"}${x(point.d).toFixed(2)} ${y(point.e).toFixed(2)}`)
                    .join(" ");
                done = `${path} L${x(alongMeters).toFixed(2)} ${y(hereElevation).toFixed(2)} L${x(alongMeters).toFixed(2)} ${HEIGHT} L0 ${HEIGHT} Z`;
            }
        }

        const here = alongMeters === null ? null : elevationAtDistance(profile, alongMeters);
        return {
            line,
            done,
            marker:
                alongMeters === null || here === null
                    ? null
                    : { x: x(alongMeters), y: y(here) },
        };
    });
</script>

{#if geometry}
    <Section
        title="Profil wysokości"
        aside="{num(insight.minMeters, 0)}–{num(insight.maxMeters, 0)} m"
    >
        <div class="lr-panel chart">
            <svg viewBox="0 0 {WIDTH} {HEIGHT}" preserveAspectRatio="none" role="img"
                aria-label="Profil wysokości trasy">
                {#if geometry.done}
                    <path class="done" d={geometry.done} />
                {/if}
                <path class="line" d={geometry.line} vector-effect="non-scaling-stroke" />
                {#if geometry.marker}
                    <line
                        class="here"
                        x1={geometry.marker.x}
                        x2={geometry.marker.x}
                        y1="0"
                        y2={HEIGHT}
                        vector-effect="non-scaling-stroke"
                    />
                    <circle class="dot" cx={geometry.marker.x} cy={geometry.marker.y} r="1.8" />
                {/if}
            </svg>
        </div>

        {#if insight.currentMeters !== null}
            <div class="lr-grid">
                <Field
                    label="Wysokość"
                    value={num(insight.currentMeters, 0)}
                    unit="m"
                />
                {#if insight.highestAheadMeters !== null && insight.highestAheadMeters > insight.currentMeters + 5}
                    <Field
                        label="Najwyższy punkt"
                        value={num(insight.highestAheadMeters, 0)}
                        unit="m"
                    />
                {/if}
                {#if insight.remainingGainMeters !== null && insight.remainingGainMeters > 0}
                    <Field
                        label="Zostało w górę"
                        value={num(insight.remainingGainMeters, 0)}
                        unit="m"
                    />
                {/if}
            </div>
        {/if}
    </Section>
{/if}

<style>
    .chart {
        padding: 8px 10px 6px;
    }

    svg {
        display: block;
        width: 100%;
        height: 92px;
    }

    .done {
        fill: rgba(0, 191, 216, 0.22);
        stroke: none;
    }

    .line {
        fill: none;
        stroke: var(--lr-ink-soft);
        stroke-width: 1.4;
        stroke-linejoin: round;
    }

    .here {
        stroke: var(--lr-accent-deep);
        stroke-width: 1.2;
        stroke-dasharray: 2 2;
    }

    .dot {
        fill: var(--lr-accent-deep);
        stroke: #fff;
        stroke-width: 0.6;
    }
</style>
