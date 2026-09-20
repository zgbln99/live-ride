<script lang="ts">
    import StatusBadge from "./StatusBadge.svelte";
    import { ago, type StatusTone } from "$lib/live/live_viewer";

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
            ? "Czekamy na pierwszą pozycję GPS"
            : hasFix
              ? `Aktualizacja ${ago(ageSeconds)}`
              : "Brak pozycji GPS",
    );
</script>

<section class="rider" style="--rider-colour: {colour}">
    <span class="marker" aria-hidden="true"></span>
    <div class="who">
        <p class="eyebrow">Obserwujesz</p>
        <p class="name">{name}</p>
        <p class="detail">{detail}</p>
    </div>
    <div class="state">
        <StatusBadge label={statusLabel} tone={statusTone} />
    </div>
</section>

<style>
    .rider {
        position: relative;
        display: grid;
        grid-template-columns: 3px minmax(0, 1fr) auto;
        gap: 0 13px;
        align-items: center;
        padding: 4px 0 14px;
        border-bottom: 1px solid var(--lr-line);
    }

    .marker {
        align-self: stretch;
        min-height: 48px;
        background: var(--rider-colour, var(--lr-accent));
    }

    .who {
        min-width: 0;
    }

    .eyebrow {
        margin: 0 0 3px;
        font-size: 10px;
        font-weight: 650;
        letter-spacing: 0.01em;
        color: var(--lr-muted);
    }

    .name {
        margin: 0;
        font-size: 22px;
        font-weight: 760;
        letter-spacing: -0.035em;
        line-height: 1.05;
        color: var(--lr-ink);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    .detail {
        margin: 5px 0 0;
        font-size: 11.5px;
        color: var(--lr-muted);
    }

    .state {
        align-self: start;
        padding-top: 2px;
    }

    @media (max-width: 380px) {
        .rider {
            grid-template-columns: 3px minmax(0, 1fr);
        }

        .state {
            grid-column: 2;
            margin-top: 8px;
        }
    }
</style>
