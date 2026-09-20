import { describe, expect, it, vi } from "vitest";
import { POST } from "./+server";

/**
 * Formularz resetu hasła nie ma prawa powiedzieć, kto ma u nas konto.
 *
 * Jest otwarty dla każdego, więc gdyby odpowiadał inaczej na adres znany
 * i nieznany, stałby się sprawdzarką kont: mając listę adresów, da się nią
 * odsiać te zarejestrowane. Dlatego odpowiedź na jedno i drugie musi być
 * bit w bit ta sama — łącznie z awarią poczty.
 */

function eventWith(body: unknown, reset: () => Promise<unknown>) {
    return {
        request: { json: async () => body },
        locals: { pb: { collection: () => ({ requestPasswordReset: reset }) } },
    } as never;
}

describe("POST /api/v1/auth/reset", () => {
    it("odpowiada tak samo na adres znany i nieznany", async () => {
        const known = await POST(
            eventWith({ email: "ada@example.com" }, async () => true),
        );
        const unknown = await POST(
            eventWith({ email: "nikt@example.com" }, async () => {
                throw Object.assign(new Error("Not found."), { status: 404 });
            }),
        );

        expect(known.status).toBe(unknown.status);
        expect(await known.json()).toEqual(await unknown.json());
    });

    it("awaria poczty też nie zdradza, że konto istnieje", async () => {
        vi.spyOn(console, "warn").mockImplementation(() => {});
        const response = await POST(
            eventWith({ email: "ada@example.com" }, async () => {
                throw Object.assign(new Error("SMTP down"), { status: 500 });
            }),
        );

        expect(response.status).toBe(200);
        expect(await response.text()).not.toContain("SMTP");
    });

    it("prosi o poprawny adres, bo to informacja o żądaniu, nie o bazie", async () => {
        const response = await POST(
            eventWith({ email: "to nie jest adres" }, async () => true),
        );
        expect(response.status).toBe(400);
    });

    it("pyta PocketBase dokładnie o podany adres", async () => {
        const reset = vi.fn(async () => true);
        await POST(eventWith({ email: "Ada@Example.com" }, reset));
        expect(reset).toHaveBeenCalledWith("Ada@Example.com");
    });
});
