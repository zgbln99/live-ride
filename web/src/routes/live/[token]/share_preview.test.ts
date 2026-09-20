import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * Podgląd linku.
 *
 * To jedyny fragment strony, który widzi każdy, komu link zostanie
 * przekazany dalej — także ci, dla których nie był przeznaczony. Dlatego
 * obrazek jest stały i nie pokazuje pozycji, a opis nigdy nie niesie miejsca,
 * tylko liczby.
 */

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, "+page.server.ts"), "utf8");

describe("metadane podglądu", () => {
    it("obrazek jest stały i nie zależy od pozycji", () => {
        expect(source).toContain("og-live.png");
        // Żadnego statycznego obrazka mapy z współrzędnymi zawodnika.
        expect(source).not.toMatch(/staticmap|latitude=|\{lat\}/i);
    });

    it("link „z linku” dostaje zakaz indeksowania", () => {
        expect(source).toContain('visibility === "public"');
        expect(source).toContain("noindex, nofollow");
    });

    it("opis i tytuł biorą się z nazwy zawodnika, nie z kodu", () => {
        // „Marek" wpisany na sztywno byłby kłamstwem u każdego innego.
        expect(source).not.toMatch(/"Marek"|'Marek'/);
        expect(source).toContain("riderName");
        expect(source).toContain("Live Ride · ${who}");
    });

    it("po zakończeniu opis niesie liczby, a bez nich milknie", () => {
        expect(source).toContain("summaryShape");
        expect(source).toContain("m ↑");
        // Brak podsumowania ma dać zdanie ogólne, nie wymyślone kilometry.
        expect(source).toContain("Zobacz podsumowanie przejazdu");
    });

    it("wygasły link nie zdradza, czyj był", () => {
        const expired = source.slice(source.indexOf('case "expired"'), source.indexOf('case "disabled"'));
        expect(expired).not.toContain("who");
        expect(expired).not.toContain("riderName");
    });
});
