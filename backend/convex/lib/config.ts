/**
 * Environment-driven configuration helpers.
 *
 * Takes an explicit env bag (defaults to process.env) so it stays testable and
 * works identically in the Convex runtime and Node scripts.
 */

import {
  DEFAULT_STRONG_MATCH_SCORE,
  DEFAULT_TENTATIVE_MATCH_SCORE,
  type Thresholds,
} from "./similarity.js";

export type EnvBag = Record<string, string | undefined>;

function num(value: string | undefined, fallback: number): number {
  if (value === undefined) return fallback;
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

/** Face-match thresholds from FACE_STRONG/TENTATIVE_MATCH_SCORE env vars. */
export function getThresholds(env: EnvBag = process.env): Thresholds {
  return {
    strong: num(env.FACE_STRONG_MATCH_SCORE, DEFAULT_STRONG_MATCH_SCORE),
    tentative: num(env.FACE_TENTATIVE_MATCH_SCORE, DEFAULT_TENTATIVE_MATCH_SCORE),
  };
}

export function getCvServiceUrl(env: EnvBag = process.env): string {
  return (env.CV_SERVICE_URL ?? "").trim();
}

export function getOpenAiConfig(env: EnvBag = process.env): {
  apiKey: string;
  model: string;
} {
  return {
    apiKey: (env.OPENAI_API_KEY ?? "").trim(),
    model: (env.OPENAI_MODEL ?? "gpt-4o-mini").trim() || "gpt-4o-mini",
  };
}

export function getDeepgramApiKey(env: EnvBag = process.env): string {
  return (env.DEEPGRAM_API_KEY ?? "").trim();
}
