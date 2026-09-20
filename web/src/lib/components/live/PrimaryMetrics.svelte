<script lang="ts">
    import {
        clock,
        distance as fmtDistance,
        duration as fmtDuration,
        num,
        type RideTimes,
    } from "$lib/live/live_viewer";

    let {
        distanceMeters,
        times,
        speedKmh,
        remainingMeters,
        averageSpeedKmh,
        elevationGainMeters,
        altitudeMeters,
        etaAt,
    }: {
        distanceMeters: number | undefined;
        times: RideTimes;
        speedKmh: number | undefined;
        remainingMeters: number | undefined;
        averageSpeedKmh: number | undefined;
        elevationGainMeters: number | undefined;
        altitudeMeters: number | undefined;
        etaAt: Date | null;
    } = $props();

    const speedText = $derived(num(speedKmh, 1));
    const hasDetails = $derived(
        averageSpeedKmh !== undefined ||
            elevationGainMeters !== undefined ||
            altitudeMeters !== undefined ||
            etaAt !== null ||
            times.pausedSeconds !== undefined,
    );
</script>

<section class="primary" aria-label="Najważniejsze dane przejazdu">
    <div class="speed-block">
        <span class="label">Prędkość</span>
        <div class="speed-reading">
            <strong>{speedText}</strong>
            {#if speedText !== "—"}<span>km/h</span>{/if}
        </div>
    </div>

    <dl class="core">
        <div>
            <dt>Dystans</dt>
            <dd>{fmtDistance(distanceMeters)}</dd>
        </div>
        <div>
            <dt>Czas w ruchu</dt>
            <dd>{fmtDuration(times.movingSeconds)}</dd>
        </div>
        <div>
            <dt>{remainingMeters !== undefined ? "Do mety" : "Czas całkowity"}</dt>
            <dd>
                {remainingMeters !== undefined
                    ? fmtDistance(remainingMeters)
                    : fmtDuration(times.elapsedSeconds)}
            </dd>
        </div>
    </dl>
</section>

{#if hasDetails}
    <dl class="details" aria-label="Pozostałe dane przejazdu">
        {#if averageSpeedKmh !== undefined}
            <div>
                <dt>Średnia</dt>
                <dd>{num(averageSpeedKmh, 1)} <span>km/h</span></dd>
            </div>
        {/if}
        {#if elevationGainMeters !== undefined}
            <div>
                <dt>Przewyższenie</dt>
                <dd>{num(elevationGainMeters, 0)} <span>m</span></dd>
            </div>
        {/if}
        {#if remainingMeters !== undefined}
            <div>
                <dt>Czas całkowity</dt>
                <dd>{fmtDuration(times.elapsedSeconds)}</dd>
            </div>
        {/if}
        {#if altitudeMeters !== undefined}
            <div>
                <dt>Wysokość</dt>
                <dd>{num(altitudeMeters, 0)} <span>m</span></dd>
            </div>
        {/if}
        {#if etaAt}
            <div>
                <dt>Przewidywana meta</dt>
                <dd>{clock(etaAt.toISOString())}</dd>
            </div>
        {/if}
        {#if times.pausedSeconds !== undefined}
            <div>
                <dt>Postoje</dt>
                <dd>{fmtDuration(times.pausedSeconds)}</dd>
            </div>
        {/if}
    </dl>
{/if}

<style>
    .primary {
        display: grid;
        grid-template-columns: minmax(145px, 0.9fr) minmax(0, 1.1fr);
        border-bottom: 1px solid var(--lr-line);
        min-height: 126px;
    }

    .speed-block {
        display: flex;
        flex-direction: column;
        justify-content: space-between;
        padding: 12px 16px 14px 0;
        border-right: 1px solid var(--lr-line);
    }

    .label,
    dt {
        font-size: 10.5px;
        font-weight: 630;
        color: var(--lr-muted);
    }

    .speed-reading {
        display: flex;
        align-items: baseline;
        gap: 6px;
        min-width: 0;
    }

    .speed-reading strong {
        font-size: clamp(42px, 10vw, 58px);
        font-weight: 720;
        letter-spacing: -0.065em;
        line-height: 0.9;
        color: var(--lr-ink);
        font-variant-numeric: tabular-nums;
    }

    .speed-reading span {
        font-size: 11px;
        font-weight: 600;
        color: var(--lr-muted);
    }

    dl {
        margin: 0;
    }

    .core {
        display: grid;
        grid-template-rows: repeat(3, minmax(0, 1fr));
        padding-left: 16px;
    }

    .core > div {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 14px;
        padding: 10px 0;
        border-bottom: 1px solid var(--lr-line);
    }

    .core > div:last-child {
        border-bottom: 0;
    }

    dd {
        margin: 0;
        font-variant-numeric: tabular-nums;
    }

    .core dd {
        font-size: 17px;
        font-weight: 700;
        letter-spacing: -0.025em;
        color: var(--lr-ink);
        text-align: right;
    }

    .details {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        border-bottom: 1px solid var(--lr-line);
    }

    .details > div {
        min-width: 0;
        padding: 10px 10px 11px;
        border-right: 1px solid var(--lr-line);
    }

    .details > div:nth-child(3n) {
        border-right: 0;
    }

    .details dd {
        margin-top: 5px;
        font-size: 13.5px;
        font-weight: 680;
        letter-spacing: -0.015em;
        color: var(--lr-ink);
        overflow-wrap: anywhere;
    }

    .details dd span {
        font-size: 10.5px;
        font-weight: 600;
        color: var(--lr-muted);
    }

    @media (max-width: 380px) {
        .primary {
            grid-template-columns: 1fr;
        }

        .speed-block {
            min-height: 104px;
            padding-right: 0;
            border-right: 0;
            border-bottom: 1px solid var(--lr-line);
        }

        .core {
            padding-left: 0;
        }

        .details {
            grid-template-columns: repeat(2, minmax(0, 1fr));
        }

        .details > div:nth-child(3n) {
            border-right: 1px solid var(--lr-line);
        }

        .details > div:nth-child(2n) {
            border-right: 0;
        }
    }
</style>
