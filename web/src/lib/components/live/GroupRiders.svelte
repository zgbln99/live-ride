<script lang="ts">
    import Section from "./Section.svelte";
    import Avatar from "./Avatar.svelte";
    import StatusBadge from "./StatusBadge.svelte";
    import { distance as fmtDistance, type StatusTone } from "$lib/live/live_viewer";

    export type GroupRider = {
        id: string;
        name: string;
        colour: string;
        statusLabel: string;
        statusTone: StatusTone;
        distanceMeters: number | undefined;
        gap: string | null;
    };

    /**
     * Uczestnicy grupy. Dotknięcie przełącza CAŁĄ stronę na wybranego —
     * mapa nadal pokazuje wszystkich, bo to ona jest wspólna.
     */
    let {
        riders,
        selectedId,
        onselect,
    }: {
        riders: GroupRider[];
        selectedId: string | null;
        onselect: (id: string) => void;
    } = $props();
</script>

<Section title="Uczestnicy" aside={String(riders.length)}>
    <ul class="lr-panel list">
        {#each riders as rider (rider.id)}
            <li>
                <button
                    type="button"
                    class:selected={rider.id === selectedId}
                    aria-pressed={rider.id === selectedId}
                    onclick={() => onselect(rider.id)}
                >
                    <Avatar name={rider.name} size={34} colour={rider.colour} />
                    <span class="who">
                        <span class="name">{rider.name}</span>
                        {#if rider.gap}<span class="gap">{rider.gap}</span>{/if}
                    </span>
                    <span class="right">
                        <StatusBadge
                            label={rider.statusLabel}
                            tone={rider.statusTone}
                            compact
                        />
                        <span class="km">{fmtDistance(rider.distanceMeters)}</span>
                    </span>
                </button>
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

    li + li {
        border-top: 1px solid var(--lr-line);
    }

    button {
        appearance: none;
        background: none;
        border: none;
        width: 100%;
        display: flex;
        align-items: center;
        gap: 11px;
        padding: 10px 14px;
        cursor: pointer;
        text-align: left;
        font: inherit;
        color: inherit;
        border-left: 3px solid transparent;
    }

    button.selected {
        background: var(--lr-panel);
        border-left-color: var(--lr-accent);
    }

    .who {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 2px;
    }

    .name {
        font-size: 14.5px;
        font-weight: 800;
        color: var(--lr-ink);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    .gap {
        font-size: 11.5px;
        color: var(--lr-muted);
    }

    .right {
        display: flex;
        flex-direction: column;
        align-items: flex-end;
        gap: 4px;
        flex: none;
    }

    .km {
        font-size: 13px;
        font-weight: 800;
        color: var(--lr-ink);
    }
</style>
