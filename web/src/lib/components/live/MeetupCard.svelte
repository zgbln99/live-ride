<script lang="ts">
    import Section from "./Section.svelte";
    import Field from "./Field.svelte";
    import { clock, distance as fmtDistance } from "$lib/live/live_viewer";

    /**
     * Punkt zbiórki grupy.
     *
     * Dystans w linii prostej, i tak to nazwany — bez trasy do zbiórki nie
     * mamy jak policzyć drogi, a „8,3 km" sugerujące przejazd byłoby
     * obietnicą, której nikt nie składał.
     */
    let {
        label,
        straightLineMeters,
        etaAt,
    }: {
        label: string;
        straightLineMeters: number | null;
        etaAt: Date | null;
    } = $props();
</script>

<Section title="Punkt zbiórki">
    <div class="lr-panel head">
        <p>{label || "Umówione miejsce"}</p>
    </div>
    {#if straightLineMeters !== null}
        <div class="lr-grid">
            <Field
                label="W linii prostej"
                value={fmtDistance(straightLineMeters)}
            />
            <Field
                label="ETA"
                value={etaAt ? clock(etaAt.toISOString()) : "—"}
            />
        </div>
    {/if}
</Section>

<style>
    .head {
        padding: 12px 14px;
    }

    p {
        margin: 0;
        font-size: 15px;
        font-weight: 800;
        color: var(--lr-ink);
    }
</style>
