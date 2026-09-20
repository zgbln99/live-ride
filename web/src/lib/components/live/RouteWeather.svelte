<script lang="ts">
    import Section from "./Section.svelte";
    import { clock, durationCoarse, num } from "$lib/live/live_viewer";
    import {
        weatherLabel,
        type SunsetInfo,
        type WeatherAlert,
        type WeatherForecast,
    } from "$lib/live/weather";

    /**
     * Pogoda tam, gdzie zawodnik dopiero wjedzie.
     *
     * Wiatr pokazujemy wyłącznie jako to, co rowerzysta poczuje — czołowy,
     * tylny, boczny. „Wiatr z zachodu 18 km/h" jest informacją dla żeglarza;
     * rowerzysta pyta, czy będzie musiał w to wjechać.
     */
    let {
        forecasts,
        alert,
        sunset,
    }: {
        forecasts: WeatherForecast[];
        alert: WeatherAlert | null;
        sunset: SunsetInfo | null;
    } = $props();

    function when(entry: WeatherForecast): string {
        if (entry.label === "now") return "TERAZ";
        if (entry.label === "finish") return `META · ${clock(entry.at.toISOString())}`;
        // Pełne kilometry: punkty prognozy i tak stoją co dwadzieścia, więc
        // „za 20,3 km" udawałoby dokładność, której nie ma.
        return `ZA ${Math.round(entry.aheadMeters / 1000)} KM`;
    }
</script>

<Section title="Pogoda na trasie">
    {#if alert}
        <div class="alert">
            <strong>{alert.title}</strong>
            <span>{alert.detail}</span>
        </div>
    {/if}

    <ul class="lr-panel list">
        {#each forecasts as entry (entry.label + entry.aheadMeters)}
            <li>
                <div class="head">
                    <span class="when">{when(entry)}</span>
                    {#if entry.label !== "now"}
                        <span class="at">{clock(entry.at.toISOString())}</span>
                    {/if}
                </div>
                <div class="body">
                    <span class="temp">
                        {num(entry.hour.temp_c, 0)}<em>°</em>
                    </span>
                    <div class="detail">
                        {#if weatherLabel(entry.hour.code)}
                            <span class="sky">{weatherLabel(entry.hour.code)}</span>
                        {/if}
                        {#if entry.hour.precip_probability !== undefined}
                            <span class="rain">
                                {Math.round(entry.hour.precip_probability)}% deszczu
                            </span>
                        {/if}
                    </div>
                    {#if entry.wind}
                        <div class="wind">
                            <span class="lr-label">{entry.wind.label}</span>
                            <span class="wind-value">
                                {num(
                                    entry.wind.kind === "cross"
                                        ? entry.wind.crossKmh
                                        : Math.abs(entry.wind.alongKmh),
                                    0,
                                )}
                                <em>km/h</em>
                            </span>
                        </div>
                    {:else if entry.hour.wind_kmh !== undefined}
                        <div class="wind">
                            <span class="lr-label">Wiatr</span>
                            <span class="wind-value">
                                {num(entry.hour.wind_kmh, 0)}<em>km/h</em>
                            </span>
                        </div>
                    {/if}
                </div>
            </li>
        {/each}
    </ul>

    {#if sunset}
        <div class="lr-panel sunset">
            <div>
                <span class="lr-label">Zachód słońca</span>
                <p>{clock(sunset.at.toISOString())}</p>
            </div>
            {#if sunset.secondsAway > 0}
                <div class="right">
                    <span class="lr-label">Do zachodu</span>
                    <p>{durationCoarse(sunset.secondsAway)}</p>
                </div>
            {/if}
        </div>
        {#if sunset.arrivesAfterSunset}
            <p class="after-dark">Przewidywany przyjazd po zachodzie słońca.</p>
        {/if}
    {/if}
</Section>

<style>
    .alert {
        border: 1px solid rgba(0, 144, 168, 0.45);
        background: rgba(0, 191, 216, 0.1);
        border-radius: var(--lr-radius);
        padding: 10px 12px;
        display: flex;
        flex-direction: column;
        gap: 3px;
    }

    .alert strong {
        font-size: 11px;
        font-weight: 900;
        letter-spacing: 1px;
        color: var(--lr-accent-deep);
    }

    .alert span {
        font-size: 12.5px;
        color: var(--lr-ink-soft);
    }

    .list {
        list-style: none;
        margin: 0;
        padding: 0;
    }

    li {
        padding: 11px 14px;
    }

    li + li {
        border-top: 1px solid var(--lr-line);
    }

    .head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 10px;
    }

    .when {
        font-size: 10.5px;
        font-weight: 900;
        letter-spacing: 1px;
        color: var(--lr-ink-soft);
    }

    .at {
        font-size: 11.5px;
        color: var(--lr-muted);
    }

    .body {
        margin-top: 7px;
        display: flex;
        align-items: center;
        gap: 14px;
    }

    .temp {
        font-size: 26px;
        font-weight: 800;
        letter-spacing: -0.03em;
        color: var(--lr-ink);
        line-height: 1;
    }

    .temp em {
        font-style: normal;
        font-size: 16px;
        color: var(--lr-ink-soft);
    }

    .detail {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 2px;
        font-size: 12.5px;
        color: var(--lr-ink-soft);
    }

    .sky {
        font-weight: 700;
        color: var(--lr-ink);
    }

    .wind {
        text-align: right;
        display: flex;
        flex-direction: column;
        gap: 4px;
        flex: none;
    }

    .wind-value {
        font-size: 16px;
        font-weight: 800;
        color: var(--lr-ink);
        line-height: 1;
    }

    .wind-value em {
        font-style: normal;
        font-size: 11px;
        font-weight: 700;
        color: var(--lr-ink-soft);
        margin-left: 3px;
    }

    .sunset {
        display: flex;
        justify-content: space-between;
        gap: 12px;
        padding: 11px 14px;
    }

    .sunset p {
        margin: 6px 0 0;
        font-size: 18px;
        font-weight: 800;
        color: var(--lr-ink);
        line-height: 1;
    }

    .right {
        text-align: right;
    }

    .after-dark {
        margin: 0;
        font-size: 12.5px;
        color: var(--lr-ink-soft);
        padding: 0 2px;
    }
</style>
