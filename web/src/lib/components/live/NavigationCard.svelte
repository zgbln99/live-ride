<script lang="ts">
    import {
        clock,
        distance as fmtDistance,
        durationCoarse,
        maneuverArrow,
        maneuverDistance,
        type RiderNav,
    } from "$lib/live/live_viewer";

    /**
     * Manewr, który zawodnik ma przed sobą — ten sam, który widzi on sam.
     *
     * Instrukcja przychodzi po polsku z telefonu i nie jest tu tłumaczona ani
     * składana od nowa: dwie warstwy nawigacji rozjechałyby się na pierwszym
     * rondzie, a widz nie ma jak sprawdzić, która kłamie.
     *
     * Zjechanie z trasy przykrywa manewr, bo manewr policzony na trasie,
     * z której ktoś zjechał, dotyczy skrzyżowania, którego ten ktoś nie widzi.
     */
    let {
        nav,
        etaAt = null,
    }: { nav: RiderNav; etaAt?: Date | null } = $props();

    const offRoute = $derived(nav.off_route === true);
    const arrow = $derived(maneuverArrow(nav.maneuver_type));
    const when = $derived(maneuverDistance(nav.distance_m));
    const instruction = $derived(nav.instruction?.trim() ?? "");
</script>

<section class="lr-section">
    <header class="lr-section-head">
        <h2 class="lr-section-title">Nawigacja</h2>
        {#if nav.remaining_m !== undefined}
            <span class="aside">do mety {fmtDistance(nav.remaining_m)}</span>
        {/if}
    </header>

    {#if offRoute}
        <div class="lr-panel card off">
            <span class="arrow">!</span>
            <div class="text">
                <span class="instruction">Poza trasą</span>
                {#if nav.off_route_m !== undefined && nav.off_route_m > 0}
                    <span class="street">
                        {fmtDistance(nav.off_route_m)} od wyznaczonej trasy
                    </span>
                {/if}
            </div>
        </div>
    {:else if instruction}
        <div class="lr-panel card">
            <span class="arrow">{arrow}</span>
            <div class="text">
                {#if when}<span class="when">{when}</span>{/if}
                <span class="instruction">{instruction}</span>
                {#if nav.street}<span class="street">{nav.street}</span>{/if}
            </div>
        </div>
    {/if}

    {#if nav.eta_seconds !== undefined || etaAt}
        <p class="eta">
            {#if nav.eta_seconds !== undefined}
                Pozostały czas według trasy: {durationCoarse(nav.eta_seconds)}
            {/if}
            {#if etaAt}
                <span class="at">na mecie ok. {clock(etaAt.toISOString())}</span>
            {/if}
        </p>
    {/if}
</section>

<style>
    .aside {
        font-size: 11.5px;
        font-weight: 700;
        color: var(--lr-muted);
    }

    .card {
        display: flex;
        align-items: center;
        gap: 14px;
        padding: 14px;
    }

    .arrow {
        font-size: 34px;
        line-height: 1;
        font-weight: 700;
        color: var(--lr-accent-deep);
        min-width: 40px;
        text-align: center;
    }

    .off .arrow {
        color: var(--lr-alert);
    }

    .text {
        display: flex;
        flex-direction: column;
        gap: 2px;
        min-width: 0;
    }

    .when {
        font-size: 12px;
        font-weight: 800;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--lr-muted);
    }

    .instruction {
        font-size: 17px;
        font-weight: 800;
        line-height: 1.25;
        color: var(--lr-ink);
    }

    .street {
        font-size: 13px;
        font-weight: 600;
        color: var(--lr-ink-soft);
    }

    .eta {
        margin: 8px 0 0;
        font-size: 12px;
        color: var(--lr-muted);
    }

    .at {
        margin-left: 6px;
    }
</style>
