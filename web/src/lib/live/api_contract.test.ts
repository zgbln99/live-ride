import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

/**
 * Aplikacja mobilna rozmawia z tym originem, nie z PocketBase.
 *
 * Każda trasa HTTP Live Ride zarejestrowana w Go musi mieć tu swoją
 * bliźniaczkę pod `/api/v1`. Brak jednego pliku `+server.ts` wygląda w
 * telefonie dokładnie tak samo jak brak endpointu w backendzie: 404, mimo że
 * kod serwera jest poprawny i wdrożony. Dokładnie to zdarzyło się trasom
 * synchronizacji i dlatego ten test istnieje.
 */

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../../../..");
const mainGo = join(repoRoot, "db", "main.go");
const apiRoot = join(repoRoot, "web", "src", "routes", "api", "v1");

type Route = { method: string; path: string };

/** Czyta rejestracje tras Live Ride prosto z main.go. */
function goLiveRoutes(): Route[] {
    const source = readFileSync(mainGo, "utf8");
    const pattern = /se\.Router\.(GET|POST|PUT|PATCH|DELETE)\("([^"]+)"/g;
    const routes: Route[] = [];
    for (const match of source.matchAll(pattern)) {
        const [, method, path] = match;
        if (!/^\/(live|live-rides|live-routes|live-segments)(\/|$)/.test(path)) continue;
        routes.push({ method, path });
    }
    return routes;
}

/** Zamienia `{token}` z Go na `[token]` z SvelteKit. */
function sveltePath(path: string): string {
    return path.replace(/\{([^}]+)\}/g, "[$1]");
}

function serverFileFor(path: string): string {
    return join(apiRoot, sveltePath(path).replace(/^\//, ""), "+server.ts");
}

describe("kontrakt /api/v1 dla Live Ride", () => {
    const routes = goLiveRoutes();

    it("znajduje trasy Live Ride w main.go", () => {
        // Gdyby regexp przestał pasować, test poniżej cicho przechodziłby
        // na pustej liście i niczego by nie pilnował.
        expect(routes.length).toBeGreaterThanOrEqual(15);
    });

    it.each(routes.map((route) => [route.method, route.path] as const))(
        "%s %s ma pośrednika pod /api/v1",
        (method, path) => {
            const file = serverFileFor(path);
            expect(existsSync(file), `brak ${file}`).toBe(true);

            const source = readFileSync(file, "utf8");
            expect(
                new RegExp(`export async function ${method}\\b`).test(source),
                `${file} nie eksportuje ${method}`,
            ).toBe(true);
        },
    );

    it("pośrednicy kierują na tę samą ścieżkę co Go", () => {
        for (const route of routes) {
            const source = readFileSync(serverFileFor(route.path), "utf8");
            // Pierwszy segment wystarczy: reszta jest składana z parametrów.
            const prefix = route.path.split("/")[1];
            expect(source, `${route.path}`).toContain(`/${prefix}`);
        }
    });
});

describe("publiczne strony nie wymagają logowania", () => {
    const hooks = readFileSync(join(repoRoot, "web", "src", "hooks.server.ts"), "utf8");

    it("nie są chronione przekierowaniem na logowanie", () => {
        const authorization = readFileSync(
            join(repoRoot, "web", "src", "lib", "util", "authorization_util.ts"),
            "utf8",
        );
        for (const path of ["/live/", "/route/"]) {
            expect(authorization).not.toContain(`"${path}"`);
        }
    });

    it("nie ciągną tokenu wyszukiwarki", () => {
        // Awaria wyszukiwania nie ma prawa położyć podglądu jazdy na żywo.
        expect(hooks).toContain("isPublicViewerRoute");
        for (const path of ["/live/", "/route/", "/api/v1/live/"]) {
            expect(hooks).toContain(`'${path}'`);
        }
    });
});

describe("publiczne strony mają metadane podglądu linku", () => {
    const pages = [
        join(repoRoot, "web", "src", "routes", "live", "[token]", "+page.svelte"),
        join(repoRoot, "web", "src", "routes", "route", "[token]", "+page.svelte"),
    ];

    it.each(pages)("%s deklaruje Open Graph", (page) => {
        const source = readFileSync(page, "utf8");
        for (const tag of [
            'property="og:title"',
            'property="og:description"',
            'property="og:image"',
            'property="og:type"',
            'property="og:url"',
        ]) {
            expect(source, tag).toContain(tag);
        }
    });

    it("obrazek podglądu istnieje i jest statyczny", () => {
        const images = readdirSync(
            join(repoRoot, "web", "static", "imgs", "live-ride"),
        );
        expect(images).toContain("og-live.png");
        expect(images).toContain("og-route.png");
    });

    it("obrazek podglądu nie niesie pozycji zawodnika", () => {
        // Miniatura wędruje dalej niż sam link, więc musi być stała.
        const source = readFileSync(pages[0], "utf8");
        const image = source.match(/property="og:image" content=\{([^}]+)\}/);
        expect(image).not.toBeNull();
        expect(image![1]).toContain("data.meta.image");

        const loader = readFileSync(
            join(repoRoot, "web", "src", "routes", "live", "[token]", "+page.server.ts"),
            "utf8",
        );
        expect(loader).toContain("/imgs/live-ride/og-live.png");
        for (const field of ["latitude", "longitude"]) {
            expect(loader).not.toContain(field);
        }
    });
});
