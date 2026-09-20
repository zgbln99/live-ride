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
    <div class="brand" aria-label="Live Ride">
        <span class="live-dot" aria-hidden="true"></span>
        <span>LIVE RIDE</span>
    </div>

    <div class="copy">
        <h1>{title}</h1>
        {#if subtitle}<p>{subtitle}</p>{/if}
    </div>

    <div class="actions">
        <StatusBadge label={statusLabel} tone={statusTone} />
        <button
            type="button"
            class="theme"
            onclick={cycleTheme}
            title={`Motyw: ${themeLabel(theme)}`}
            aria-label={`Zmień motyw. Teraz: ${themeLabel(theme)}`}>◐</button
        >
    </div>
</header>

<style>
    .head {
        min-height: 54px;
        display: grid;
        grid-template-columns: auto minmax(0, 1fr) auto;
        align-items: center;
        gap: 14px;
        background: var(--lr-surface);
        border-bottom: 1px solid var(--lr-line);
        padding: 8px 14px;
        position: sticky;
        top: 0;
        z-index: 5;
    }

    .brand {
        display: inline-flex;
        align-items: center;
        gap: 7px;
        font-size: 10px;
        font-weight: 760;
        letter-spacing: 0.12em;
        color: var(--lr-ink);
        white-space: nowrap;
    }

    .live-dot {
        width: 7px;
        height: 7px;
        border-radius: 50%;
        background: var(--lr-go);
        box-shadow: 0 0 0 3px color-mix(in srgb, var(--lr-go) 12%, transparent);
    }

    .copy {
        min-width: 0;
        padding-left: 14px;
        border-left: 1px solid var(--lr-line);
    }

    h1 {
        margin: 0;
        font-size: 14px;
        font-weight: 690;
        letter-spacing: -0.015em;
        line-height: 1.25;
        color: var(--lr-ink);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    .copy p {
        margin: 2px 0 0;
        font-size: 10.5px;
        color: var(--lr-muted);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    .actions {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        gap: 12px;
        min-width: 0;
    }

    .theme {
        appearance: none;
        width: 28px;
        height: 28px;
        display: grid;
        place-items: center;
        padding: 0;
        border: 0;
        background: transparent;
        color: var(--lr-muted);
        font: inherit;
        font-size: 17px;
        line-height: 1;
        cursor: pointer;
    }

    .theme:hover {
        color: var(--lr-ink);
    }

    @media (max-width: 620px) {
        .head {
            grid-template-columns: minmax(0, 1fr) auto;
            gap: 10px;
            padding: 8px 12px;
        }

        .brand {
            display: none;
        }

        .copy {
            padding-left: 0;
            border-left: 0;
        }

        .actions {
            gap: 9px;
        }
    }
</style>
