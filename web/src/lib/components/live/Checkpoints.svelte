<script lang="ts">
    import Section from "./Section.svelte";
    import {
        clock,
        distance as fmtDistance,
        type PlacedCheckpoint,
    } from "$lib/live/live_viewer";

    /**
     * Punkty pośrednie trasy z godziną, o której zawodnik powinien tam być.
     *
     * To one odpowiadają na pytanie, które zadaje każdy, kto ma kogoś spotkać
     * po drodze: „o której będzie w Poczdamie". Dotąd jedyną odpowiedzią było
     * ETA na metę, czyli informacja dla kogoś zupełnie innego.
     *
     * Nazwy pochodzą od zawodnika — to jego waypointy. Bezimiennych tu nie ma,
     * bo „punkt 3" nie mówi nikomu nic.
     */
    let { checkpoints }: { checkpoints: PlacedCheckpoint[] } = $props();
</script>

{#if checkpoints.length}
    <Section title="Punkty na trasie">
        <ol class="lr-panel list">
            {#each checkpoints as checkpoint (checkpoint.name + checkpoint.distance_m)}
                <li class:done={checkpoint.reached}>
                    <span class="name">{checkpoint.name}</span>
                    <span class="meta">
                        {#if checkpoint.reached}
                            minięty
                        {:else}
                            {fmtDistance(checkpoint.remainingMeters)}
                            {#if checkpoint.etaAt}
                                · {clock(checkpoint.etaAt.toISOString())}
                            {/if}
                        {/if}
                    </span>
                </li>
            {/each}
        </ol>
    </Section>
{/if}

<style>
    .list {
        list-style: none;
        margin: 0;
        padding: 4px 0;
    }

    li {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 10px;
        padding: 7px 12px;
        font-size: 13.5px;
    }

    li + li {
        border-top: 1px solid var(--lr-line);
    }

    .name {
        font-weight: 700;
        color: var(--lr-ink);
    }

    .meta {
        font-variant-numeric: tabular-nums;
        color: var(--lr-ink-soft);
        font-size: 12.5px;
    }

    /* Minięty punkt zostaje na liście, tylko przygaszony: znika mu przyszłość,
       nie jego istnienie. Usuwanie go kasowałoby połowę informacji o tym,
       gdzie zawodnik już był. */
    .done .name,
    .done .meta {
        color: var(--lr-muted);
    }
</style>
