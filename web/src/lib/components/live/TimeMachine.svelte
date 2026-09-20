<script lang="ts">
    import { clock, duration as fmtDuration } from "$lib/live/live_viewer";

    /**
     * Cofanie się w trwającej jeździe i odtwarzanie zakończonej.
     *
     * Jedna kontrolka, bo to jedno pytanie: „jak było o 14:12". W trwającej
     * transmisji zadaje je ktoś, kto wszedł za późno i chce zobaczyć ten
     * podjazd; po mecie zadaje je ten sam człowiek, tylko o całą jazdę.
     *
     * Cofnięcie NIE przerywa transmisji. Telemetria dalej przychodzi, mapa
     * dalej ją zna — po prostu przez chwilę pokazujemy co innego, i mówimy
     * o tym wprost, żeby nikt nie pomylił nagrania z bieżącą pozycją.
     */
    let {
        count,
        index,
        at,
        ended,
        onseek,
        onlive,
    }: {
        count: number;
        /** Wybrana próbka albo null, gdy oglądamy bieżący stan. */
        index: number | null;
        at: string | null;
        ended: boolean;
        onseek: (index: number | null) => void;
        onlive: () => void;
    } = $props();

    /** Skróty do cofania w trwającej jeździe. */
    const JUMPS = [5, 15, 30];

    function jump(minutes: number) {
        // Historia jest równomierna w czasie tylko z grubsza, więc zamiast
        // liczyć indeks z minut, cofamy się proporcjonalnie i pozwalamy
        // stronie dobrać najbliższą próbkę.
        onseek(Math.max(0, count - 1 - Math.round((minutes / 30) * (count - 1))));
    }
</script>

{#if count > 1}
    <section class="lr-section">
        <header class="lr-section-head">
            <h2 class="lr-section-title">{ended ? "Odtwórz przejazd" : "Cofnij się"}</h2>
            {#if at}<span class="aside">{clock(at)}</span>{/if}
        </header>

        <div class="lr-panel box">
            {#if ended}
                <input
                    class="slider"
                    type="range"
                    min="0"
                    max={count - 1}
                    value={index ?? count - 1}
                    aria-label="Moment przejazdu"
                    oninput={(event) =>
                        onseek(Number((event.currentTarget as HTMLInputElement).value))}
                />
            {:else}
                <div class="jumps">
                    {#each JUMPS as minutes (minutes)}
                        <button type="button" class="lr-button" onclick={() => jump(minutes)}>
                            −{fmtDuration(minutes * 60)}
                        </button>
                    {/each}
                </div>
            {/if}

            {#if index !== null}
                <!-- Duży i jednoznaczny: to jedyne wyjście z trybu, w którym
                     liczby na stronie nie są bieżące. -->
                <button type="button" class="lr-button live" onclick={onlive}>
                    {ended ? "POKAŻ METĘ" : "WRÓĆ DO LIVE"}
                </button>
            {/if}
        </div>
    </section>
{/if}

<style>
    .aside {
        font-size: 11.5px;
        font-weight: 700;
        color: var(--lr-muted);
        font-variant-numeric: tabular-nums;
    }

    .box {
        display: flex;
        flex-direction: column;
        gap: 10px;
        padding: 12px;
    }

    .jumps {
        display: flex;
        gap: 8px;
    }

    .jumps .lr-button {
        flex: 1;
    }

    .slider {
        width: 100%;
        accent-color: var(--lr-accent-deep);
    }

    .live {
        background: var(--lr-ink);
        border-color: var(--lr-ink);
        color: var(--lr-surface);
        min-height: 42px;
    }
</style>
