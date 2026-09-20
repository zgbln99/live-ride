<script lang="ts">
    import Section from "./Section.svelte";
    import { distance as fmtDistance, num } from "$lib/live/live_viewer";
    import { normalizeGradient, type PlacedClimb } from "$lib/live/route_insight";

    /**
     * Najbliższe podjazdy, po jednym wierszu.
     *
     * Domyślnie trzy. Piętnaście podjazdów naraz to nie informacja, tylko
     * spis treści — a obserwujący chce wiedzieć, co czeka zawodnika teraz,
     * nie za cztery godziny.
     */
    let {
        climbs,
        total,
        expanded = $bindable(false),
    }: { climbs: PlacedClimb[]; total: number; expanded?: boolean } = $props();
</script>

<Section title="Kolejne podjazdy" aside={total > climbs.length ? `${total}` : ""}>
    <ul class="lr-panel list">
        {#each climbs as climb (climb.start_m)}
            <li>
                <span class="when">Za {fmtDistance(climb.distanceAheadMeters)}</span>
                <span class="name">{climb.name || "Podjazd"}</span>
                <span class="spec">
                    {fmtDistance(climb.length_m)} · {num(climb.gain_m, 0)} m ↑ ·
                    {num(normalizeGradient(climb.avg_gradient), 1)}%
                </span>
            </li>
        {/each}
    </ul>

    {#if total > climbs.length || expanded}
        <button
            type="button"
            class="lr-button"
            aria-pressed={expanded}
            onclick={() => (expanded = !expanded)}
        >
            {expanded ? "POKAŻ MNIEJ" : "POKAŻ WSZYSTKIE PODJAZDY"}
        </button>
    {/if}
</Section>

<style>
    .list {
        list-style: none;
        margin: 0;
        padding: 0;
    }

    li {
        padding: 10px 14px;
        display: grid;
        grid-template-columns: auto 1fr;
        grid-template-areas: "when name" "when spec";
        column-gap: 12px;
        row-gap: 2px;
        align-items: center;
    }

    li + li {
        border-top: 1px solid var(--lr-line);
    }

    .when {
        grid-area: when;
        font-size: 10.5px;
        font-weight: 900;
        letter-spacing: 0.8px;
        text-transform: uppercase;
        color: var(--lr-accent-deep);
        white-space: nowrap;
    }

    .name {
        grid-area: name;
        font-size: 14px;
        font-weight: 800;
        color: var(--lr-ink);
    }

    .spec {
        grid-area: spec;
        font-size: 12px;
        color: var(--lr-ink-soft);
    }
</style>
