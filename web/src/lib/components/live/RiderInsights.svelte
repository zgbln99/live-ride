<script lang="ts">
    import Section from "./Section.svelte";
    import type { RiderInsight } from "$lib/live/live_viewer";

    /**
     * To, co licznik powiedział zawodnikowi — powtórzone widzowi.
     *
     * Ta strona niczego tu nie filtruje i nie ma czym: wszystko, na co
     * zawodnik nie pozwolił, oraz wszystko, co dotyczy jego ciała, zostało
     * odcięte na serwerze i nigdy tu nie dotarło. Filtr w przeglądarce byłby
     * pozorem prywatności — dane i tak leżałyby w odpowiedzi HTTP.
     *
     * Zdania przychodzą gotowe i po polsku. Nie składamy ich z liczb, żeby
     * obserwujący czytał dokładnie to samo, co rowerzysta ma przed oczami.
     */
    let { insights }: { insights: RiderInsight[] } = $props();

    const visible = $derived(insights.filter((insight) => insight.body));
</script>

{#if visible.length > 0}
    <Section title="Licznik mówi">
        <div class="list">
            {#each visible as insight (insight.kind + insight.body)}
                <div
                    class="lr-panel item"
                    class:urgent={insight.priority === "urgent"}
                    class:notable={insight.priority === "notable"}
                >
                    {#if insight.title}
                        <span class="title">{insight.title}</span>
                    {/if}
                    <span class="body">{insight.body}</span>
                </div>
            {/each}
        </div>
    </Section>
{/if}

<style>
    .list {
        display: flex;
        flex-direction: column;
        gap: 8px;
    }

    .item {
        display: flex;
        flex-direction: column;
        gap: 3px;
        padding: 11px 13px;
        border-left: 3px solid var(--lr-line);
    }

    .item.notable {
        border-left-color: var(--lr-accent);
    }

    .item.urgent {
        border-left-color: var(--lr-alert);
    }

    .title {
        font-size: 10.5px;
        font-weight: 700;
        letter-spacing: 0.09em;
        color: var(--lr-ink-soft);
    }

    .body {
        font-size: 13.5px;
        line-height: 1.4;
        color: var(--lr-ink);
    }
</style>
