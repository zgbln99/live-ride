<script lang="ts">
    import Section from "./Section.svelte";
    import { elevationAtDistance, type ElevationPoint } from "$lib/live/route_insight";
    import { distance as fmtDistance } from "$lib/live/live_viewer";

    /**
     * Najbliższe dziesięć kilometrów.
     *
     * Pełny profil odpowiada na pytanie „jak wygląda cała trasa" i przy
     * dwustukilometrowej pętli nie odpowiada na żadne inne: podjazd na
     * trzysta metrów jest tam szpilką o szerokości piksela. To jest ten sam
     * profil w skali, w której widać, co czeka ZARAZ — czyli w jedynej, jaka
     * ma znaczenie dla kogoś, kto patrzy na jadącego człowieka.
     *
     * Kolor odcinka bierze się z nachylenia, a nie z wysokości: zielony to
     * zjazd, czerwony strome podejście. Bez tego wykres w oknie dziesięciu
     * kilometrów jest prawie płaską kreską i nie mówi nic.
     */
    let {
        profile,
        alongMeters,
        windowMeters = 10000,
    }: {
        profile: ElevationPoint[];
        alongMeters: number | null;
        windowMeters?: number;
    } = $props();

    const WIDTH = 100;
    const HEIGHT = 26;

    const window_ = $derived.by(() => {
        if (alongMeters === null || profile.length < 2) return null;
        const from = alongMeters;
        const to = from + windowMeters;
        const inside = profile.filter((point) => point.d >= from && point.d <= to);
        if (inside.length < 2) return null;

        // Punkt dokładnie w miejscu zawodnika, żeby wykres zaczynał się tam,
        // gdzie on stoi, a nie na najbliższej próbce profilu przed nim.
        const here = elevationAtDistance(profile, from);
        const points = here === null ? inside : [{ d: from, e: here }, ...inside];

        let min = Infinity;
        let max = -Infinity;
        for (const point of points) {
            if (point.e < min) min = point.e;
            if (point.e > max) max = point.e;
        }
        const span = Math.max(20, max - min);
        const length = points[points.length - 1].d - from;
        if (length <= 0) return null;

        const x = (d: number) => ((d - from) / length) * WIDTH;
        const y = (e: number) => HEIGHT - ((e - min) / span) * (HEIGHT - 3) - 1.5;

        const segments = [];
        for (let i = 1; i < points.length; i++) {
            const run = points[i].d - points[i - 1].d;
            const rise = points[i].e - points[i - 1].e;
            const gradient = run > 0 ? (rise / run) * 100 : 0;
            segments.push({
                d: `M${x(points[i - 1].d).toFixed(2)} ${y(points[i - 1].e).toFixed(2)} L${x(points[i].d).toFixed(2)} ${y(points[i].e).toFixed(2)}`,
                colour: colourFor(gradient),
            });
        }

        return { segments, min, max, length };
    });

    /** Skala nachylenia, ta sama, którą licznik maluje na wykresie podjazdu. */
    function colourFor(gradient: number): string {
        if (gradient <= -3) return "#31d07c";
        if (gradient < 2) return "#7c8a95";
        if (gradient < 5) return "#f2c037";
        if (gradient < 9) return "#ff8a3d";
        return "#e02b20";
    }
</script>

{#if window_}
    <Section title="Najbliższe {fmtDistance(window_.length)}"
        aside="{Math.round(window_.min)}–{Math.round(window_.max)} m">
        <div class="lr-panel chart">
            <svg
                viewBox="0 0 {WIDTH} {HEIGHT}"
                preserveAspectRatio="none"
                role="img"
                aria-label="Profil najbliższych kilometrów"
            >
                {#each window_.segments as segment, index (index)}
                    <path
                        d={segment.d}
                        stroke={segment.colour}
                        fill="none"
                        stroke-width="2.4"
                        stroke-linecap="round"
                        vector-effect="non-scaling-stroke"
                    />
                {/each}
            </svg>
        </div>
    </Section>
{/if}

<style>
    .chart {
        padding: 8px 10px;
    }

    svg {
        display: block;
        width: 100%;
        height: 64px;
    }
</style>
