import { z } from "zod";

const NavigateRequestSchema = z.object({
  shape: z
    .array(
      z.object({
        lat: z.number().min(-90).max(90),
        lon: z.number().min(-180).max(180),
      })
    )
    .min(2, "at_least_two_shape_points")
    .max(500),
  costing: z.enum(["pedestrian", "bicycle"]).default("pedestrian"),
  // Instruction language is a client concern: the Live Ride app sends the
  // rider's locale instead of inheriting a server-wide default.
  language: z.string().min(2).max(16).default("en-US"),
});

type NavigateRequest = z.infer<typeof NavigateRequestSchema>;

type NavigateShapePoint = {
  lat: number;
  lon: number;
};

type NavigateManeuver = {
  instruction: string;
  verbal_post_instruction?: string;
  street_names?: string[];
  length: number;
  time: number;
  begin_shape_index: number;
  end_shape_index: number;
  bearing: number;
  type: number;
  roundabout_exit_count?: number;
};

type NavigateSummary = {
  length: number;
  time: number;
};

type NavigateResponse = {
  maneuvers: NavigateManeuver[];
  shape: [number, number][];
  summary: NavigateSummary;
};

export { NavigateRequestSchema };
export type { NavigateRequest, NavigateShapePoint, NavigateManeuver, NavigateSummary, NavigateResponse };
