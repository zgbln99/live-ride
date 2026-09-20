<script lang="ts">
    import Avatar from "./Avatar.svelte";
    import StatusBadge from "./StatusBadge.svelte";
    import { ago, type StatusTone } from "$lib/live/live_viewer";

    /**
     * Kto jedzie i czy w ogóle jedzie — pierwsze pytanie obserwującego.
     *
     * Karta istnieje od chwili udostępnienia linku, także zanim przyjdzie
     * pierwsza pozycja. Wtedy zamiast „ostatnia aktualizacja" pisze wprost,
     * że czekamy na GPS, żeby nikt nie odczytał braku znacznika jako awarii.
     */
    let {
        name,
        statusLabel,
        statusTone,
        ageSeconds,
        colour,
        hasFix,
    }: {
        name: string;
        statusLabel: string;
        statusTone: StatusTone;
        ageSeconds: number;
        colour: string;
        hasFix: boolean;
    } = $props();

    const detail = $derived(
        statusTone === "waiting"
            ? "Pozycja pojawi się za chwilę."
            : hasFix
              ? `Ostatnia aktualizacja: ${ago(ageSeconds)}`
              : "Brak pozycji.",
    );
</script>

<div class="lr-panel card">
    <Avatar {name} size={44} {colour} />
    <div class="who">
        <p class="name">{name}</p>
        <p class="detail">{detail}</p>
    </div>
    <StatusBadge label={statusLabel} tone={statusTone} />
</div>

<style>
    .card {
        display: grid;
        grid-template-columns: auto minmax(0, 1fr);
        align-items: center;
        gap: 6px 12px;
        padding: 12px 14px;
    }

    .who {
        min-width: 0;
    }

    /* Przy długiej etykiecie stanu („OCZEKIWANIE NA GPS") plakietka nie
       mieści się obok nazwy i ściskałaby opis do słupka po jednym słowie.
       Wtedy schodzi pod spód, na pełną szerokość. */
    .card > :global(.lr-status) {
        grid-column: 2;
        justify-self: start;
    }

    @media (min-width: 380px) {
        .card {
            grid-template-columns: auto minmax(0, 1fr) auto;
        }

        .card > :global(.lr-status) {
            grid-column: 3;
        }
    }

    .name {
        margin: 0;
        font-size: 17px;
        font-weight: 800;
        letter-spacing: -0.2px;
        color: var(--lr-ink);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    .detail {
        margin: 2px 0 0;
        font-size: 12px;
        color: var(--lr-muted);
    }
</style>
