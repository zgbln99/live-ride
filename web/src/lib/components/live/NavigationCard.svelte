<script lang="ts">
    import {
        clock,
        distance as fmtDistance,
        durationCoarse,
        maneuverArrow,
        maneuverDistance,
        type RiderNav,
    } from "$lib/live/live_viewer";

    let {
        nav,
        etaAt = null,
    }: { nav: RiderNav; etaAt?: Date | null } = $props();

    const offRoute = $derived(nav.off_route === true);
    const arrow = $derived(maneuverArrow(nav.maneuver_type));
    const when = $derived(maneuverDistance(nav.distance_m));
    const instruction = $derived(nav.instruction?.trim() ?? "");
</script>

<section class="lr-section navigation">
    <header class="lr-section-head">
        <h2 class="lr-section-title">Nawigacja</h2>
        {#if nav.remaining_m !== undefined}
            <span class="aside">do mety {fmtDistance(nav.remaining_m)}</span>
        {/if}
    </header>

    {#if offRoute}
        <div class="maneuver off">
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
        <div class="maneuver">
            <span class="arrow">{arrow}</span>
            <div class="text">
                {#if when}<span class="when">{when}</span>{/if}
                <span class="instruction">{instruction}</span>
                {#if nav.street}<span class="street">{nav.street}</span>{/if}
            </div>
        </div>
    {/if}

    {#if nav.eta_seconds !== undefined || etaAt}
        <div class="eta">
            {#if nav.eta_seconds !== undefined}
                <span>{durationCoarse(nav.eta_seconds)} według trasy</span>
            {/if}
            {#if etaAt}
                <span>meta ok. {clock(etaAt.toISOString())}</span>
            {/if}
        </div>
    {/if}
</section>

<style>
    .navigation {
        gap: 8px;
    }

    .aside {
        font-size: 11px;
        font-weight: 600;
        color: var(--lr-muted);
    }

    .maneuver {
        display: grid;
        grid-template-columns: 48px minmax(0, 1fr);
        align-items: center;
        gap: 12px;
        padding: 13px 0;
        border-top: 1px solid var(--lr-line);
        border-bottom: 1px solid var(--lr-line);
    }

    .arrow {
        font-size: 36px;
        line-height: 1;
        font-weight: 620;
        color: var(--lr-accent-deep);
        text-align: center;
    }

    .off .arrow,
    .off .instruction {
        color: var(--lr-alert);
    }

    .text {
        display: flex;
        flex-direction: column;
        gap: 3px;
        min-width: 0;
    }

    .when {
        font-size: 11px;
        font-weight: 640;
        color: var(--lr-muted);
    }

    .instruction {
        font-size: 18px;
        font-weight: 710;
        letter-spacing: -0.025em;
        line-height: 1.2;
        color: var(--lr-ink);
    }

    .street {
        font-size: 12.5px;
        font-weight: 500;
        color: var(--lr-ink-soft);
    }

    .eta {
        display: flex;
        flex-wrap: wrap;
        gap: 5px 14px;
        font-size: 11.5px;
        color: var(--lr-muted);
    }
</style>
