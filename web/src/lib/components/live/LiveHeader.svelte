<script lang="ts">
    import StatusBadge from "./StatusBadge.svelte";
    import type { StatusTone } from "$lib/live/live_viewer";
    import { onMount } from "svelte";
    import {
        applyTheme,
        nextTheme,
        readTheme,
        themeLabel,
        type ThemeChoice,
    } from "$lib/live/theme";

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

    let theme = $state<ThemeChoice>("system");
    onMount(() => (theme = readTheme()));

    function cycleTheme() {
        theme = nextTheme(theme);
        applyTheme(theme);
    }
</script>

<header class="head">
    <div class="top">
        <span class="wordmark">LIVE<span>RIDE</span></span>
        <div class="right">
            <StatusBadge label={statusLabel} tone={statusTone} />
            <button
                type="button"
                class="theme"
                onclick={cycleTheme}
                title="Motyw: system, noc, dzień"
                aria-label="Zmień motyw">{themeLabel(theme)}</button
            >
        </div>
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

    .right {
        display: flex;
        align-items: center;
        gap: 8px;
    }

    .theme {
        appearance: none;
        background: none;
        border: 1px solid var(--lr-line-strong);
        border-radius: var(--lr-radius);
        color: var(--lr-muted);
        font: inherit;
        font-size: 10px;
        font-weight: 900;
        letter-spacing: 1px;
        padding: 3px 6px;
        cursor: pointer;
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
