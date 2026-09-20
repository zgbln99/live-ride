import { describe, expect, it } from "vitest";
import { render } from "svelte/server";

import RiderInsights from "./RiderInsights.svelte";
import type { RiderInsight } from "$lib/live/live_viewer";

/**
 * Zdania licznika na publicznej stronie.
 *
 * Testy pilnują dwóch rzeczy. Po pierwsze: zdanie ma trafić do HTML-u
 * DOKŁADNIE takie, jakie przyszło — strona go nie składa z liczb i nie
 * tłumaczy, bo widz ma przeczytać to samo, co rowerzysta ma przed oczami.
 * Po drugie: pusta lista ma zniknąć razem z nagłówkiem, a nie zostawić
 * sekcji „Licznik mówi" bez treści.
 */

const insight = (over: Partial<RiderInsight> = {}): RiderInsight => ({
    kind: "climb",
    title: "PODJAZD",
    body: "Za 3,2 km podjazd: 4,2 km, 5,4%, +240 m",
    ...over,
});

describe("insighty licznika", () => {
    it("powtarza zdanie co do znaku", () => {
        const { body } = render(RiderInsights, {
            props: { insights: [insight()] },
        });
        expect(body).toContain("Za 3,2 km podjazd: 4,2 km, 5,4%, +240 m");
        expect(body).toContain("PODJAZD");
    });

    it("bez insightów nie ma sekcji", () => {
        const { body } = render(RiderInsights, { props: { insights: [] } });
        expect(body).not.toContain("Licznik mówi");
    });

    it("insight bez treści nie tworzy pustego wiersza", () => {
        const { body } = render(RiderInsights, {
            props: { insights: [insight({ body: "" })] },
        });
        expect(body).not.toContain("Licznik mówi");
    });

    it("pilny insight dostaje własny znacznik, a nie tylko kolor tekstu", () => {
        const { body } = render(RiderInsights, {
            props: {
                insights: [
                    insight({
                        kind: "battery",
                        title: "BATERIA",
                        body: "Telefon 8%.",
                        priority: "urgent",
                    }),
                ],
            },
        });
        expect(body).toContain("urgent");
        expect(body).toContain("Telefon 8%.");
    });

    it("renderuje kilka zdań w kolejności, w jakiej przyszły", () => {
        const { body } = render(RiderInsights, {
            props: {
                insights: [
                    insight({ kind: "climb", body: "Pierwsze zdanie." }),
                    insight({ kind: "weather", title: "POGODA", body: "Drugie zdanie." }),
                ],
            },
        });
        expect(body.indexOf("Pierwsze zdanie.")).toBeLessThan(
            body.indexOf("Drugie zdanie."),
        );
    });
});
