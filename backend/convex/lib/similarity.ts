/**
 * Vector math for face matching. Framework-free and unit-tested.
 *
 * Embeddings from the CV service are already L2-normalized (length 512), but we
 * never trust that blindly: cosine() normalizes internally, and matchBest()
 * re-normalizes defensively so a mis-normalized embedding can't skew scoring.
 */

import type { FaceMatchResult } from "./types.js";

/** Expected embedding dimensionality from the CV service (buffalo_l / ArcFace). */
export const EMBEDDING_DIM = 512;

/** Default thresholds (overridable via env). Matches docs/API_CONTRACTS.md. */
export const DEFAULT_STRONG_MATCH_SCORE = 0.38;
export const DEFAULT_TENTATIVE_MATCH_SCORE = 0.3;

/**
 * Cosine similarity between two equal-length numeric vectors.
 * Returns a value in [-1, 1]; returns 0 for degenerate input (mismatched
 * length, empty, or a zero-magnitude vector) so callers never divide by zero.
 */
export function cosine(a: number[], b: number[]): number {
  if (!a || !b || a.length === 0 || a.length !== b.length) return 0;
  let dot = 0;
  let aa = 0;
  let bb = 0;
  for (let i = 0; i < a.length; i++) {
    const av = a[i];
    const bv = b[i];
    dot += av * bv;
    aa += av * av;
    bb += bv * bv;
  }
  const denom = Math.sqrt(aa) * Math.sqrt(bb);
  if (denom === 0) return 0;
  return dot / denom;
}

/** L2-normalize a vector. Returns a copy; a zero vector is returned unchanged. */
export function l2normalize(v: number[]): number[] {
  let sum = 0;
  for (const x of v) sum += x * x;
  const norm = Math.sqrt(sum);
  if (norm === 0) return v.slice();
  return v.map((x) => x / norm);
}

/** True if every element is a finite number. */
export function isFiniteVector(v: unknown): v is number[] {
  return (
    Array.isArray(v) &&
    v.length > 0 &&
    v.every((x) => typeof x === "number" && Number.isFinite(x))
  );
}

export type Thresholds = {
  strong: number;
  tentative: number;
};

export const DEFAULT_THRESHOLDS: Thresholds = {
  strong: DEFAULT_STRONG_MATCH_SCORE,
  tentative: DEFAULT_TENTATIVE_MATCH_SCORE,
};

/** A face-match status derived purely from a score + thresholds. */
export type MatchStatus = "matched" | "tentative" | "unknown";

/**
 * Classify a similarity score against thresholds.
 *   score >= strong    -> "matched"
 *   score >= tentative -> "tentative"
 *   otherwise          -> "unknown"
 */
export function classifyScore(score: number, t: Thresholds = DEFAULT_THRESHOLDS): MatchStatus {
  if (score >= t.strong) return "matched";
  if (score >= t.tentative) return "tentative";
  return "unknown";
}

export type EnrolledEmbedding = {
  personId: string;
  embedding: number[];
};

export type BestMatch = {
  personId: string | null;
  score: number;
  status: MatchStatus;
};

/**
 * Compare a query embedding against all enrolled embeddings and return the best.
 * Defensively re-normalizes everything. With no candidates or a degenerate
 * query, returns an "unknown" best with score 0 and null personId.
 */
export function matchBest(
  query: number[],
  enrolled: EnrolledEmbedding[],
  thresholds: Thresholds = DEFAULT_THRESHOLDS,
): BestMatch {
  if (!isFiniteVector(query) || enrolled.length === 0) {
    return { personId: null, score: 0, status: "unknown" };
  }
  const q = l2normalize(query);
  let bestId: string | null = null;
  let bestScore = -Infinity;
  for (const cand of enrolled) {
    if (!isFiniteVector(cand.embedding)) continue;
    const score = cosine(q, l2normalize(cand.embedding));
    if (score > bestScore) {
      bestScore = score;
      bestId = cand.personId;
    }
  }
  if (bestId === null) {
    return { personId: null, score: 0, status: "unknown" };
  }
  const status = classifyScore(bestScore, thresholds);
  return { personId: bestId, score: bestScore, status };
}

/**
 * Build the final FaceMatchResult from a best match. For "unknown" we drop the
 * personId so iOS never shows a wrong named overlay for a low-confidence face.
 */
export function toFaceMatchResult(
  trackId: string,
  best: BestMatch,
  extra: Partial<FaceMatchResult> = {},
): FaceMatchResult {
  const status = best.status;
  return {
    trackId,
    status,
    personId: status === "unknown" ? null : best.personId,
    score: best.score,
    ...extra,
  };
}
