<script lang="ts">
    import type { Snippet } from "svelte";

    /** Nagłówek sekcji z opcjonalną liczbą po prawej, jak w aplikacji. */
    let {
        title,
        aside = "",
        children,
        action,
    }: {
        title: string;
        aside?: string;
        children: Snippet;
        action?: Snippet;
    } = $props();
</script>

<section class="lr-section">
    <header class="lr-section-head">
        <h2 class="lr-section-title">{title}</h2>
        {#if action}
            {@render action()}
        {:else if aside}
            <span class="aside">{aside}</span>
        {/if}
    </header>
    {@render children()}
</section>

<style>
    .aside {
        font-size: 11.5px;
        font-weight: 700;
        color: var(--lr-muted);
    }
</style>
