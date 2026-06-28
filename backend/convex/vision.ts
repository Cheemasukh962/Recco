/**
 * Face matching.
 *
 *   vision:matchFace (public action) -> FaceMatchResult
 *
 * Flow: call the CV service /embed (or deterministic mock), cosine-compare the
 * returned 512-d embedding against enrolled people, classify against thresholds,
 * write lastMatch/highlightedPersonId into BrainState, and return the result.
 *
 * Never throws: no_face / unknown / error are all returned as data.
 */

import { action, type ActionCtx } from "./_generated/server.js";
import { internal } from "./_generated/api.js";
import { v } from "convex/values";
import { faceMatchResultValidator } from "./validators.js";
import type { FaceMatchResult } from "./lib/types.js";
import { getThresholds, getCvServiceUrl } from "./lib/config.js";
import { getEmbedding } from "./lib/cv.js";
import { matchBest, toFaceMatchResult } from "./lib/similarity.js";

export const matchFace = action({
  args: {
    imageBase64: v.string(),
    imageMimeType: v.union(v.literal("image/jpeg"), v.literal("image/png")),
    trackId: v.string(),
  },
  returns: faceMatchResultValidator,
  handler: async (ctx, args): Promise<FaceMatchResult> => {
    const { trackId } = args;
    try {
      const thresholds = getThresholds(process.env);
      const cvServiceUrl = getCvServiceUrl(process.env);

      const outcome = await getEmbedding({
        imageBase64: args.imageBase64,
        imageMimeType: args.imageMimeType,
        requestId: trackId,
        cvServiceUrl,
      });

      // Genuine "no face" from the CV service.
      if (!outcome.faceDetected || !outcome.embedding) {
        const result: FaceMatchResult = {
          trackId,
          status: "no_face",
          personId: null,
          score: null,
          quality: outcome.quality,
          message: outcome.error ?? "No usable face detected",
          latencyMs: outcome.latencyMs,
        };
        await safeRecord(ctx, result, outcome.source);
        return result;
      }

      const enrolled = await ctx.runQuery(internal.people.listEnrolled, {});
      const best = matchBest(outcome.embedding, enrolled, thresholds);

      const message =
        best.status === "matched"
          ? `Matched ${best.personId} (score ${best.score.toFixed(3)})`
          : best.status === "tentative"
            ? `Tentative match ${best.personId} (score ${best.score.toFixed(3)})`
            : "No confident match";

      const result = toFaceMatchResult(trackId, best, {
        quality: outcome.quality,
        latencyMs: outcome.latencyMs,
        message,
      });

      await safeRecord(ctx, result, outcome.source);
      return result;
    } catch (err) {
      // Defensive: never throw out of an action.
      const result: FaceMatchResult = {
        trackId,
        status: "error",
        personId: null,
        score: null,
        message: err instanceof Error ? err.message : String(err),
      };
      await safeRecord(ctx, result, "error").catch(() => {});
      return result;
    }
  },
});

/** Record a match into state without ever letting a write failure surface. */
async function safeRecord(
  ctx: ActionCtx,
  result: FaceMatchResult,
  source?: string,
): Promise<void> {
  try {
    await ctx.runMutation(internal.state.recordMatch, { result, source });
  } catch {
    // Swallow: returning the match to iOS matters more than logging it.
  }
}
