<script lang="ts">
    import { initials } from "$lib/live/live_viewer";

    /**
     * Inicjały, nie zdjęcie.
     *
     * Publiczny link jest otwarty dla każdego, kto go dostanie, a awatar
     * z konta wyszedłby dalej niż sama jazda. Aplikacja rysuje uczestników
     * dokładnie tak samo.
     */
    let {
        name,
        size = 40,
        colour = "var(--lr-ink)",
    }: { name: string; size?: number; colour?: string } = $props();
</script>

<span
    class="avatar"
    style="--size: {size}px; --colour: {colour}"
    aria-hidden="true">{initials(name)}</span
>

<style>
    .avatar {
        width: var(--size);
        height: var(--size);
        border-radius: var(--lr-radius);
        background: var(--lr-panel);
        border: 1px solid var(--lr-line);
        border-left: 3px solid var(--colour);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        font-size: calc(var(--size) * 0.36);
        font-weight: 900;
        letter-spacing: 0.5px;
        color: var(--lr-ink);
        flex: none;
    }
</style>
