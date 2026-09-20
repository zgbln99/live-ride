<script lang="ts">
    import Section from "./Section.svelte";
    import {
        clock,
        distance as fmtDistance,
        eventLabel,
        type LiveEvent,
    } from "$lib/live/live_viewer";

    /**
     * Co się wydarzyło w tej jeździe.
     *
     * Migawka odpowiada wyłącznie na pytanie „jak jest teraz", więc ktoś, kto
     * wszedł kwadrans po starcie, nie miał jak się dowiedzieć, że zawodnik
     * zjechał z trasy i po kilometrze wrócił. Oś czasu nie jest logiem dla
     * ciekawskich — to jedyne miejsce, w którym w ogóle widać przebieg.
     *
     * Kolejność od najnowszego, bo tak się to czyta. Zmian prędkości tu nie
     * ma: lista, która rośnie co sekundę, przestaje być listą zdarzeń.
     */
    let { events, limit = 8 }: { events: LiveEvent[]; limit?: number } = $props();

    let expanded = $state(false);
    const shown = $derived(expanded ? events : events.slice(0, limit));
    const alarming = (kind: string) => kind === "off_route" || kind === "sos";
</script>

{#if events.length}
    <Section title="Przebieg">
        {#snippet action()}
            {#if events.length > limit}
                <button type="button" class="more" onclick={() => (expanded = !expanded)}>
                    {expanded ? "MNIEJ" : `WSZYSTKIE (${events.length})`}
                </button>
            {/if}
        {/snippet}

        <ol class="lr-panel list">
            {#each shown as event (event.seq)}
                <li class:alarm={alarming(event.kind)}>
                    <span class="time">{clock(event.at)}</span>
                    <span class="what">{eventLabel(event)}</span>
                    {#if event.distance_m !== undefined && event.distance_m > 0}
                        <span class="where">{fmtDistance(event.distance_m)}</span>
                    {/if}
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
        display: grid;
        grid-template-columns: 48px 1fr auto;
        align-items: baseline;
        gap: 8px;
        padding: 6px 12px;
        font-size: 13px;
    }

    li + li {
        border-top: 1px solid var(--lr-line);
    }

    .time {
        font-variant-numeric: tabular-nums;
        font-weight: 700;
        color: var(--lr-muted);
        font-size: 12px;
    }

    .what {
        font-weight: 700;
        color: var(--lr-ink);
    }

    .alarm .what {
        color: var(--lr-alert);
    }

    .where {
        font-variant-numeric: tabular-nums;
        color: var(--lr-ink-soft);
        font-size: 12px;
    }

    .more {
        appearance: none;
        background: none;
        border: none;
        padding: 0;
        font: inherit;
        font-size: 11px;
        font-weight: 800;
        letter-spacing: 0.08em;
        color: var(--lr-accent-deep);
        cursor: pointer;
    }
</style>
