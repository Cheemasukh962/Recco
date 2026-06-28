/**
 * Client for Person A's CV / face-embedding service (POST /embed), with a
 * deterministic mock fallback when the service is unreachable or unset.
 *
 * Framework-free (only `fetch`, available in Convex actions and Node 18+).
 * Never throws: on any network/parse failure it falls back to mock embeddings
 * so vision:matchFace and the enrollment script keep working offline.
 */

import type { EmbedResponse, FaceQuality } from "./types.js";
import { isFiniteVector } from "./similarity.js";
import { mockEmbeddingForImage } from "./mockEmbeddings.js";

export type EmbedSource = "cv" | "mock";

export type EmbedOutcome = {
  /** Where the embedding came from. */
  source: EmbedSource;
  /** Whether a usable face was detected. False only on a real CV "no face". */
  faceDetected: boolean;
  /** L2-normalized 512-d embedding, or null when no face was detected. */
  embedding: number[] | null;
  quality: FaceQuality | null;
  latencyMs: number | null;
  /** Present when source === "mock" and the demo marker resolved a person. */
  markerPersonId: string | null;
  error: string | null;
};

export type EmbedOptions = {
  imageBase64: string;
  imageMimeType: string;
  requestId: string;
  /** Base URL of the CV service, e.g. http://127.0.0.1:8000. Empty -> mock. */
  cvServiceUrl?: string | null;
  /** Request timeout in ms (default 8000). */
  timeoutMs?: number;
  /** Test seam: inject a fetch implementation. Defaults to global fetch. */
  fetchImpl?: typeof fetch;
};

function mockOutcome(imageBase64: string): EmbedOutcome {
  const { embedding, markerPersonId } = mockEmbeddingForImage(imageBase64);
  return {
    source: "mock",
    faceDetected: true,
    embedding,
    quality: {
      faceDetected: true,
      detectionScore: 0.99,
      model: "mock-deterministic",
    },
    latencyMs: 0,
    markerPersonId,
    error: null,
  };
}

/**
 * Get a face embedding for an image. Tries the real CV service first when a URL
 * is provided; otherwise (or on any failure) returns a deterministic mock.
 *
 * Distinguishes a genuine CV "no face detected" (faceDetected=false,
 * embedding=null, source="cv") from a fallback to mock.
 */
export async function getEmbedding(opts: EmbedOptions): Promise<EmbedOutcome> {
  const { imageBase64, imageMimeType, requestId } = opts;
  const url = (opts.cvServiceUrl ?? "").trim();
  const doFetch = opts.fetchImpl ?? (typeof fetch !== "undefined" ? fetch : undefined);

  if (!url || !doFetch) {
    return mockOutcome(imageBase64);
  }

  const start = Date.now();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? 8000);

  try {
    const res = await doFetch(`${url.replace(/\/+$/, "")}/embed`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ imageBase64, imageMimeType, requestId }),
      signal: controller.signal,
    });

    if (!res.ok) {
      // Service responded with an error status -> degrade to mock.
      return mockOutcome(imageBase64);
    }

    const data = (await res.json()) as EmbedResponse;
    const latencyMs = typeof data.latencyMs === "number" ? data.latencyMs : Date.now() - start;

    if (data.faceDetected === false || data.embedding === null || data.embedding === undefined) {
      return {
        source: "cv",
        faceDetected: false,
        embedding: null,
        quality: data.quality ?? { faceDetected: false },
        latencyMs,
        markerPersonId: null,
        error: data.error ?? "No usable face detected",
      };
    }

    if (!isFiniteVector(data.embedding)) {
      // Malformed embedding from CV -> safer to mock than to match on garbage.
      return mockOutcome(imageBase64);
    }

    return {
      source: "cv",
      faceDetected: true,
      embedding: data.embedding,
      quality: data.quality ?? { faceDetected: true, model: "buffalo_l" },
      latencyMs,
      markerPersonId: null,
      error: null,
    };
  } catch {
    // Network error / timeout / abort / bad JSON -> deterministic mock.
    return mockOutcome(imageBase64);
  } finally {
    clearTimeout(timer);
  }
}
