<script lang="ts">
    import type { StatusTone } from "$lib/live/live_viewer";

    /**
     * Plakietka stanu. Pięć stanów, pięć różnych zdań — bo dla obserwującego
     * „postój na światłach" i „zgubił zasięg" to zupełnie inne wiadomości.
     */
    let {
        label,
        tone,
        compact = false,
    }: { label: string; tone: StatusTone; compact?: boolean } = $props();

    const symbol = $derived(
        tone === "ended" ? "✓" : tone === "offline" ? "○" : "",
    );
</script>

<span class="lr-status lr-status-{tone}" class:compact>
    {#if symbol}
        <span aria-hidden="true">{symbol}</span>
    {:else}
        <span class="dot" aria-hidden="true"></span>
    {/if}
    {label}
</span>

<style>
    .compact {
        padding: 2px 6px;
        font-size: 10px;
    }
</style>
