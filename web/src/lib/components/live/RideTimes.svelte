<script lang="ts">
    import Section from "./Section.svelte";
    import Field from "./Field.svelte";
    import { duration as fmtDuration, type RideTimes } from "$lib/live/live_viewer";

    /**
     * Rozbicie czasu: całość, ruch, postój i pauza z palca.
     *
     * Auto-pauza i pauza ręczna nie są tym samym i widz musi je rozróżnić.
     * „Stoi 4 minuty" to światła albo sklep; „zapauzował 20 minut" to decyzja
     * — i tylko drugie znaczy, że nie ma sensu czekać na ruch na mapie.
     */
    let { times }: { times: RideTimes } = $props();

    const hasBreakdown = $derived(
        times.autoPausedSeconds !== undefined || times.manualPausedSeconds !== undefined,
    );
</script>

{#if hasBreakdown}
    <Section title="Czasy">
        <div class="lr-grid">
            <Field label="Całkowity" value={fmtDuration(times.elapsedSeconds)} />
            <Field label="W ruchu" value={fmtDuration(times.movingSeconds)} />
            <Field
                label="Postoje"
                value={fmtDuration(times.autoPausedSeconds)}
                hint="auto-pauza na światłach"
            />
            <Field
                label="Pauza"
                value={fmtDuration(times.manualPausedSeconds)}
                hint="zatrzymana ręcznie"
            />
        </div>
    </Section>
{/if}
