import type { Climb } from "./live_viewer";

/** Trasa wydana pod publicznym linkiem. */
export type PublicRoute = {
    name: string;
    description?: string;
    author?: string;
    tags?: string[];
    distance_m?: number;
    ascent_m?: number;
    descent_m?: number;
    polyline: string;
    /** Trasy Live Ride kodują polilinię w precyzji 6. */
    precision?: number;
    waypoints?: unknown;
    preferences?: Record<string, unknown> | null;
    elevation_profile?: { d: number; e: number }[] | null;
    climbs?: Climb[] | null;
    /** Nawierzchnie, jeśli aplikacja je policzyła: udział w całej trasie. */
    surfaces?: { kind: string; share: number }[] | null;
    privacy?: "public" | "link" | "private";
    copy_count?: number;
    share_token?: string;
};

/** Kategoria podjazdu po polsku, bez udawania kategorii UCI, której nie ma. */
export function climbCategory(climb: Climb): string {
    const category = (climb.category ?? "").toString().toUpperCase();
    if (!category) return "podjazd";
    if (category === "HC") return "HC";
    return `kat. ${category}`;
}

/** Polskie nazwy nawierzchni. */
const SURFACE_LABELS: Record<string, string> = {
    paved: "asfalt",
    asphalt: "asfalt",
    gravel: "szuter",
    unpaved: "droga gruntowa",
    ground: "droga gruntowa",
    cobblestone: "bruk",
    sand: "piasek",
    unknown: "nieznana",
};

export function surfaceLabel(kind: string): string {
    return SURFACE_LABELS[kind?.toLowerCase?.() ?? ""] ?? kind;
}

/**
 * Kształt trasy z samej geometrii.
 *
 * Pętla, tam i z powrotem albo z punktu do punktu — to jedna z pierwszych
 * rzeczy, o które pyta ktoś, komu podsyłamy trasę.
 */
export function routeShape(coordinates: [number, number][]): string | null {
    if (coordinates.length < 4) return null;
    const start = coordinates[0];
    const finish = coordinates[coordinates.length - 1];
    const gapDegrees = Math.hypot(finish[0] - start[0], finish[1] - start[1]);
    // ~300 m w Europie Środkowej. Dokładność nie ma tu znaczenia: chodzi o
    // słowo na karcie, nie o pomiar.
    if (gapDegrees < 0.004) {
        const middle = coordinates[Math.floor(coordinates.length / 2)];
        const spread = Math.hypot(middle[0] - start[0], middle[1] - start[1]);
        return spread < 0.004 ? "Tam i z powrotem" : "Pętla";
    }
    return "Z punktu do punktu";
}
