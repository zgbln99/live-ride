import { createRequire } from "node:module";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { MAPLIBRE_WORKER_URL } from "./maplibre_worker";

/**
 * Web worker MapLibre musi być tam, gdzie kod go szuka.
 *
 * Gdy go nie ma, nic nie wybucha: mapa po prostu zostaje pustym tłem, bo bez
 * workera MapLibre nie przetwarza żadnych danych wektorowych. Znaczniki, jako
 * elementy DOM, działają dalej — więc usterka wygląda jak „mapa się wolno
 * ładuje" i przechodzi przez każdy test, który nie patrzy na piksele.
 */

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, "../../..");
const require = createRequire(import.meta.url);

/** Wszystkie pliki pod katalogiem, rekurencyjnie. */
function* walk(directory: string): Generator<string> {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
        const full = join(directory, entry.name);
        if (entry.isDirectory()) yield* walk(full);
        else yield full;
    }
}

describe("worker MapLibre", () => {
    it("adres w kodzie i w pluginie budowania to ten sam adres", () => {
        const plugin = readFileSync(
            join(webRoot, "vite-plugins", "maplibre-worker.js"),
            "utf8",
        );
        const declared = plugin.match(/MAPLIBRE_WORKER_URL = "([^"]+)"/);
        expect(declared).not.toBeNull();
        expect(declared![1]).toBe(MAPLIBRE_WORKER_URL);
    });

    it("plugin kopiuje worker i plik, który ten worker importuje", () => {
        const plugin = readFileSync(
            join(webRoot, "vite-plugins", "maplibre-worker.js"),
            "utf8",
        );
        for (const file of ["maplibre-gl-worker.mjs", "maplibre-gl-shared.mjs"]) {
            expect(plugin, file).toContain(file);
        }
    });

    it("worker nadal importuje towarzysza po ścieżce względnej", () => {
        // Gdyby MapLibre przestał to robić albo zmienił nazwę pliku, kopiowanie
        // dwóch plików obok siebie przestałoby wystarczać — i chcemy się o tym
        // dowiedzieć z testu, a nie z pustej mapy na produkcji.
        const worker = readFileSync(
            require.resolve("maplibre-gl/dist/maplibre-gl-worker.mjs"),
            "utf8",
        );
        expect(worker).toContain("./maplibre-gl-shared.mjs");
    });

    it("każda mapa w aplikacji ustawia adres workera przed startem", () => {
        // Lista plików celowo nie jest wpisana na sztywno: mapa przeniesiona
        // do nowego komponentu wypadłaby ze sztywnej listy razem z ochroną.
        // Szukamy więc każdego miejsca, które buduje mapę, i pytamy o nie.
        const sources = [...walk(join(webRoot, "src"))].filter(
            (file) => file.endsWith(".svelte") || file.endsWith(".ts"),
        );
        const builders = sources.filter((file) =>
            /new M\.Map\(/.test(readFileSync(file, "utf8")),
        );
        expect(builders.length, "nie znaleziono ani jednej mapy").toBeGreaterThan(0);

        for (const file of builders) {
            const source = readFileSync(file, "utf8");
            const page = file.slice(webRoot.length + 1);
            expect(source, page).toContain("ensureMapLibreWorker");
            // Wywołanie musi poprzedzać konstruktor mapy: pula workerów czyta
            // adres przy pierwszym żądaniu kafelka.
            const call = source.indexOf("ensureMapLibreWorker()");
            const construction = source.search(/new M\.Map\(/);
            expect(call, page).toBeGreaterThan(-1);
            expect(call, page).toBeLessThan(construction);
        }
    });

    it("publiczne strony LIVE i trasy nadal mają mapę", () => {
        // Ten test broni poprzedniego: gdyby mapa zniknęła z publicznych
        // stron, tamten przeszedłby na pustej liście.
        for (const page of [
            "src/routes/live/[token]/+page.svelte",
            "src/routes/route/[token]/+page.svelte",
        ]) {
            const source = readFileSync(join(webRoot, page), "utf8");
            expect(source, page).toMatch(/LiveMap|new M\.Map\(/);
        }
    });
});
