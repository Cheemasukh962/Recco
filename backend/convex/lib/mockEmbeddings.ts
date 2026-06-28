/**
 * Deterministic mock face embeddings.
 *
 * Used in two places when the real CV service is unreachable:
 *   1. Seeding: every enrolled person gets a stable, person-specific 512-d
 *      embedding so cosine matching still works end-to-end offline.
 *   2. vision:matchFace mock path: a "demo image" can deterministically resolve
 *      to exactly one person via an embedded marker (see decodeMatchMarker).
 *
 * Random unit vectors in 512-d are near-orthogonal, so a person's own embedding
 * scores ~1.0 against itself and ~0 against everyone else — clean matching.
 *
 * Framework-free: relies only on globals available in both Node and the Convex
 * runtime (atob/btoa, Math).
 */

import { EMBEDDING_DIM, l2normalize } from "./similarity.js";

/** FNV-1a 32-bit hash of a string -> unsigned int seed. */
function hashString(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/** mulberry32 PRNG: deterministic, fast, good enough for fixtures. */
function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Standard-normal sample via Box-Muller from a uniform RNG. */
function gaussian(rng: () => number): number {
  let u = 0;
  let v = 0;
  while (u === 0) u = rng();
  while (v === 0) v = rng();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

/**
 * Deterministic L2-normalized embedding for a seed string (e.g. a person id).
 * Same seed -> identical vector across runs and machines.
 */
export function deterministicEmbedding(seed: string, dim: number = EMBEDDING_DIM): number[] {
  const rng = mulberry32(hashString(seed));
  const v: number[] = new Array(dim);
  for (let i = 0; i < dim; i++) v[i] = gaussian(rng);
  return l2normalize(v);
}

const MARKER_PREFIX = "recco-match:";
const MARKER_RE = /recco-match:(person_[a-zA-Z0-9_]+)/;

/**
 * Build a base64 "demo image" that the mock CV path resolves to `personId`.
 * Lets the smoke script / iOS demo mode trigger a deterministic match without a
 * real photo or the CV service.
 */
export function makeMockImageBase64(personId: string): string {
  return btoa(`${MARKER_PREFIX}${personId}`);
}

/**
 * Inspect a base64 image for an embedded demo marker. Returns the person id if
 * present, else null (a real JPEG/PNG will not contain the marker).
 */
export function decodeMatchMarker(imageBase64: string): string | null {
  try {
    const cleaned = imageBase64.replace(/^data:[^;]+;base64,/, "");
    const bin = atob(cleaned);
    const m = bin.match(MARKER_RE);
    return m ? m[1] : null;
  } catch {
    return null;
  }
}

/**
 * Produce a mock 512-d embedding for an input image. If the image carries a
 * demo marker, returns the marked person's embedding (-> strong match); else a
 * stable embedding seeded by the image bytes (-> typically "unknown").
 */
export function mockEmbeddingForImage(imageBase64: string): {
  embedding: number[];
  markerPersonId: string | null;
} {
  const markerPersonId = decodeMatchMarker(imageBase64);
  const seed = markerPersonId ?? `image:${hashString(imageBase64)}`;
  return { embedding: deterministicEmbedding(seed), markerPersonId };
}
