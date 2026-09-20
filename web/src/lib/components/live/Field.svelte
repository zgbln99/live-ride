<script lang="ts">
    /**
     * Jedno pole danych — dokładnie to, co pokazuje licznik na kierownicy.
     *
     * Etykieta mała i wersalikami, liczba duża i tabelaryczna, jednostka
     * mniejsza obok. Brak wartości to kreska, nigdy zero: „—" znaczy „nie
     * wiemy", a „0" znaczy „zmierzyliśmy zero" i to są dwie różne rzeczy.
     */
    let {
        label,
        value,
        unit = "",
        size = 26,
        hint = "",
        tone = "ink",
    }: {
        label: string;
        value: string;
        unit?: string;
        size?: number;
        hint?: string;
        tone?: "ink" | "accent" | "muted";
    } = $props();
</script>

<div class="lr-cell">
    <span class="lr-label">{label}</span>
    <span class="lr-cell-value">
        <span
            class="lr-value"
            class:accent={tone === "accent"}
            class:muted={tone === "muted"}
            style="font-size: {size}px">{value}</span
        >
        <!-- Jednostka tylko przy liczbie. „— km/h" wygląda jak zepsuty
             pomiar, a nie jak brak pomiaru. -->
        {#if unit && value !== "—"}<span class="lr-unit">{unit}</span>{/if}
    </span>
    {#if hint}<span class="hint">{hint}</span>{/if}
</div>

<style>
    .accent {
        color: var(--lr-accent-deep);
    }
    .muted {
        color: var(--lr-muted);
    }
    .hint {
        font-size: 11px;
        color: var(--lr-muted);
        line-height: 1.2;
    }
</style>
