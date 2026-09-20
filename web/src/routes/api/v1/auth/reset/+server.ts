import { handleError } from "$lib/util/api_util";
import { json, type RequestEvent } from "@sveltejs/kit";
import { z } from "zod";

/**
 * @swagger
 * /api/v1/auth/reset:
 *   post:
 *     summary: Request password reset
 *     description: Sends a password reset email
 *     tags:
 *       - Authentication
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - email
 *             properties:
 *               email:
 *                 type: string
 *                 format: email
 *     responses:
 *       200:
 *         description: Password reset email sent
 *       400:
 *         description: Bad Request
 *       500:
 *         description: Internal Server Error
 */
/**
 * Ta trasa odpowiada tak samo na adres, który istnieje, i na taki, którego
 * nie ma.
 *
 * Formularz resetu hasła jest otwarty dla każdego, więc różnica w odpowiedzi
 * („nie znaleziono" kontra „wysłano") zamienia go w sprawdzarkę kont: mając
 * listę adresów, da się nią odsiać te, które są u nas zarejestrowane. To samo
 * dotyczy błędów po stronie poczty — awaria SMTP nie ma prawa powiedzieć
 * pytającemu, że pod tym adresem ktoś jest.
 *
 * Dlatego jedyny 400, jaki stąd wychodzi, dotyczy pola, które nie jest
 * adresem e-mail: to informacja o treści żądania, nie o zawartości bazy.
 */
export async function POST(event: RequestEvent) {
    let email: string;
    try {
        const data = await event.request.json()
        email = z.object({
            email: z.string().email()
        }).parse(data).email
    } catch (e: any) {
        return handleError(e);
    }

    try {
        await event.locals.pb.collection('users').requestPasswordReset(email);
    } catch (e: any) {
        // Celowo połknięte. Log zostaje po naszej stronie, odpowiedź nie.
        console.warn('password reset request failed', e?.status ?? e);
    }

    return json({ success: true });
}
