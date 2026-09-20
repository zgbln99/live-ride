<script lang="ts">
    import Section from "./Section.svelte";
    import { clock } from "$lib/live/live_viewer";

    /** Ostatnie komunikaty od zawodników. Kilka, nie czat. */
    let {
        messages,
    }: {
        messages: { id: string; body: string; sent_at: string; display_name: string }[];
    } = $props();
</script>

<Section title="Ostatnie komunikaty">
    <ul class="lr-panel list">
        {#each messages as message (message.id)}
            <li>
                <div class="meta">
                    <span class="time">{clock(message.sent_at)}</span>
                    <span class="who">{message.display_name}</span>
                </div>
                <p>{message.body}</p>
            </li>
        {/each}
    </ul>
</Section>

<style>
    .list {
        list-style: none;
        margin: 0;
        padding: 0;
    }

    li {
        padding: 10px 14px;
    }

    li + li {
        border-top: 1px solid var(--lr-line);
    }

    .meta {
        display: flex;
        gap: 8px;
        align-items: baseline;
    }

    .time {
        font-size: 11px;
        font-weight: 800;
        color: var(--lr-muted);
    }

    .who {
        font-size: 12px;
        font-weight: 800;
        color: var(--lr-ink);
    }

    p {
        margin: 3px 0 0;
        font-size: 13.5px;
        color: var(--lr-ink-soft);
        line-height: 1.4;
    }
</style>
