<script lang="ts">
    import StatusBadge from "./StatusBadge.svelte";
    import type { StatusTone } from "$lib/live/live_viewer";

    /**
     * Pasek u góry, wzorowany na AppBarze aplikacji: marka, stan, tytuł.
     *
     * Kompaktowy z premedytacją. Nagłówek zabierający ćwierć ekranu telefonu
     * odsuwa mapę poniżej zgięcia, a mapa jest tym, po co znajomy tu wszedł.
     */
    let {
        title,
        statusLabel,
        statusTone,
        subtitle = "",
    }: {
        title: string;
        statusLabel: string;
        statusTone: StatusTone;
        subtitle?: string;
    } = $props();
</script>

<header class="head">
    <div class="top">
        <span class="wordmark">LIVE<span>RIDE</span></span>
        <StatusBadge label={statusLabel} tone={statusTone} />
    </div>
    <h1>{title}</h1>
    {#if subtitle}<p class="sub">{subtitle}</p>{/if}
</header>

<style>
    .head {
        background: var(--lr-surface);
        border-bottom: 1px solid var(--lr-line);
        padding: 10px 16px 11px;
        position: sticky;
        top: 0;
        z-index: 5;
    }

    .top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
    }

    .wordmark {
        font-size: 13px;
        font-weight: 900;
        letter-spacing: 2.4px;
        color: var(--lr-ink);
    }

    .wordmark span {
        color: var(--lr-accent-deep);
    }

    h1 {
        margin: 6px 0 0;
        font-size: 16px;
        font-weight: 800;
        letter-spacing: -0.2px;
        line-height: 1.25;
        color: var(--lr-ink);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    .sub {
        margin: 3px 0 0;
        font-size: 12px;
        color: var(--lr-muted);
    }
</style>
