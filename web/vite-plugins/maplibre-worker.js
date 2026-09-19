import { createReadStream, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";

/**
 * Udostępnia web worker MapLibre pod stałym adresem `/maplibre/`.
 *
 * MapLibre 6 trzyma worker w osobnym pliku, a ten importuje jeszcze jeden
 * (`./maplibre-gl-shared.mjs`) po ścieżce WZGLĘDNEJ. Żadnego z nich Vite nie
 * potrafi wykryć — `new URL('./plik.mjs', import.meta.url)` liczone w
 * zbundlowanym kawałku wskazuje na plik, którego w wyniku budowania nie ma.
 *
 * Skutek jest cichy i całkowity: worker nie wstaje, MapLibre nie przetwarza
 * żadnych danych wektorowych i mapa zostaje pustym tłem. Znaczniki, jako
 * zwykłe elementy DOM, działają dalej — więc z boku wygląda to na „mapa się
 * nie doczytała", a nie na brakujący plik.
 *
 * Dlatego kopiujemy oba pliki obok siebie, pod nazwami, których worker się
 * spodziewa. Źródłem jest zawsze zainstalowany pakiet, więc aktualizacja
 * MapLibre nie zostawia tu nieaktualnej kopii.
 */
const WORKER_FILES = ["maplibre-gl-worker.mjs", "maplibre-gl-shared.mjs"];

/** Katalog `dist` zainstalowanego pakietu maplibre-gl. */
function maplibreDist() {
    const require = createRequire(import.meta.url);
    return dirname(require.resolve("maplibre-gl/dist/maplibre-gl-worker.mjs"));
}

/** Publiczny adres workera — ten sam w dev i po zbudowaniu. */
export const MAPLIBRE_WORKER_URL = "/maplibre/maplibre-gl-worker.mjs";

export function maplibreWorker() {
    const dist = maplibreDist();

    return {
        name: "live-ride-maplibre-worker",

        // Serwer deweloperski nie przechodzi przez `generateBundle`, więc tam
        // wydajemy pliki wprost z node_modules. Dzięki temu adres workera jest
        // identyczny w dev i w produkcji i nie ma osobnej ścieżki do zepsucia.
        configureServer(server) {
            server.middlewares.use((request, response, next) => {
                const name = WORKER_FILES.find((file) =>
                    request.url?.startsWith(`/maplibre/${file}`),
                );
                if (!name) return next();
                response.setHeader("Content-Type", "text/javascript; charset=utf-8");
                createReadStream(join(dist, name)).pipe(response);
            });
        },

        generateBundle() {
            // Tylko dla budowania przeglądarkowego: w wyniku SSR worker nie ma
            // czego obsługiwać.
            if (this.environment?.name === "ssr") return;
            for (const name of WORKER_FILES) {
                this.emitFile({
                    type: "asset",
                    // Nazwa bez skrótu skrótu jest tu konieczna: worker importuje
                    // swojego towarzysza po nazwie, a nie po adresie z manifestu.
                    fileName: `maplibre/${name}`,
                    source: readFileSync(join(dist, name), "utf8"),
                });
            }
        },
    };
}
