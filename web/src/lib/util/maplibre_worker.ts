import { setWorkerUrl } from "maplibre-gl";

/**
 * Adres web workera MapLibre.
 *
 * Musi być zgodny z `MAPLIBRE_WORKER_URL` z `vite-plugins/maplibre-worker.js`,
 * bo to ten plugin kładzie tam oba pliki workera. Pilnuje tego test
 * `src/lib/util/maplibre_worker.test.ts`.
 */
export const MAPLIBRE_WORKER_URL = "/maplibre/maplibre-gl-worker.mjs";

/**
 * Wskazuje MapLibre, gdzie leży jego web worker.
 *
 * MapLibre od wersji 6 trzyma worker w osobnym pliku i domyślnie szuka go
 * obok SIEBIE: `new URL('./maplibre-gl-worker.mjs', import.meta.url)`. Po
 * zbudowaniu aplikacji biblioteka siedzi w zahaszowanym kawałku w
 * `_app/immutable/chunks/`, więc ten adres wskazuje na plik, którego tam nie
 * ma — Vite nie rozpoznaje takiego wzorca i nie kopiuje workera ani jego
 * zależności.
 *
 * Skutek jest cichy i całkowity: worker nie wstaje, więc MapLibre nie
 * przetwarza ŻADNYCH danych wektorowych. Mapa zostaje pustym tłem, znaczniki
 * (zwykłe elementy DOM) działają normalnie, a w konsoli jest jedna linijka
 * „maplibre-gl-worker.mjs net::ERR_FAILED".
 *
 * Wywołanie musi nastąpić PRZED utworzeniem pierwszej mapy — pula workerów
 * czyta ten adres przy pierwszym żądaniu kafelka.
 */
export function ensureMapLibreWorker(): void {
    setWorkerUrl(MAPLIBRE_WORKER_URL);
}
