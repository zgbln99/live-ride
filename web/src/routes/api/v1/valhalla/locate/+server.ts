import { proxyJsonResponse } from '$lib/server/http';
import { getValhallaUrl } from '$lib/server/valhalla';
import { json, type RequestEvent } from "@sveltejs/kit";

/**
 * @swagger
 * /api/v1/valhalla/locate:
 *   post:
 *     summary: Snap coordinates to the road network
 *     description: >
 *       Asks Valhalla which routable edge is nearest to each location. The
 *       route planner uses it when a waypoint dropped on the map lands next
 *       to a road rather than on one — snapping is then a lookup against the
 *       real network, not a guess from geometry.
 *     tags:
 *       - Valhalla
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *     responses:
 *       200:
 *         description: Correlated locations from Valhalla
 *       400:
 *         description: Bad Request
 *       500:
 *         description: Internal Server Error
 */
export async function POST(event: RequestEvent) {
    const locateUrl = getValhallaUrl() + '/locate';
    const data = await event.request.json();
    if (!getValhallaUrl()) {
        return json({ message: "VALHALLA_URL not set" }, { status: 400 })
    }

    try {
        const response = await event.fetch(locateUrl, {
            method: "POST",
            body: JSON.stringify(data)
        });
        return await proxyJsonResponse(response);
    } catch (e: any) {
        return json({ message: "Valhalla request failed" }, { status: 502 })
    }
}
