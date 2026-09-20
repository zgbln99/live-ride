<script lang="ts">
    import { clock } from "$lib/live/live_viewer";

    /**
     * Potwierdzony alert bezpieczeństwa.
     *
     * Świadomie zawiera wyłącznie fakt i godzinę. Żadnego numeru telefonu,
     * żadnych kontaktów alarmowych, żadnych danych medycznych — publiczny link
     * trafia dalej niż ktokolwiek zakłada, a te informacje są niebezpieczne
     * dokładnie w rękach osób, które nie powinny ich dostać.
     *
     * Kto ma zadzwonić, wie do kogo. Reszcie wystarczy wiedzieć, że coś się
     * stało i gdzie zawodnik był.
     */
    let { at }: { at: string } = $props();
</script>

<div class="alert" role="alert">
    <span class="mark">!</span>
    <div>
        <p class="headline">Alert bezpieczeństwa</p>
        <p class="detail">
            Aplikacja zgłosiła zdarzenie o {clock(at)}. Ostatnia znana pozycja jest
            na mapie.
        </p>
    </div>
</div>

<style>
    .alert {
        display: flex;
        gap: 12px;
        align-items: flex-start;
        padding: 12px 14px;
        border: 1px solid var(--lr-alert);
        border-radius: var(--lr-radius);
        background: rgba(224, 43, 32, 0.08);
    }

    .mark {
        font-size: 20px;
        font-weight: 900;
        line-height: 1.1;
        color: var(--lr-alert);
    }

    .headline {
        margin: 0;
        font-size: 14px;
        font-weight: 900;
        letter-spacing: 0.4px;
        color: var(--lr-alert);
        text-transform: uppercase;
    }

    .detail {
        margin: 3px 0 0;
        font-size: 12.5px;
        line-height: 1.45;
        color: var(--lr-ink-soft);
    }
</style>
