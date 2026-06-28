/**
 * Voice command interpretation + Deepgram token minting.
 *
 *   voice:interpretCommand  (public action) -> FilterCommand
 *   voice:getDeepgramToken  (public action) -> { temporaryToken, expiresAt }
 *
 * interpretCommand uses OpenAI when OPENAI_API_KEY is set and falls back to a
 * deterministic offline parser (the five demo phrases) otherwise or on error.
 * Both paths emit the same FilterCommand JSON shape.
 */

import { action } from "./_generated/server.js";
import { api } from "./_generated/api.js";
import { v } from "convex/values";
import { filterCommandValidator } from "./validators.js";
import type { FilterCommand } from "./lib/types.js";
import { getOpenAiConfig, getDeepgramApiKey } from "./lib/config.js";
import { chatJson } from "./lib/openai.js";
import {
  parseCommandOffline,
  sanitizeFilterCommand,
  resolveTargetPerson,
  type RosterEntry,
} from "./lib/voiceParser.js";
import { TAG_VOCABULARY } from "./lib/tags.js";

const SYSTEM_PROMPT = `You convert a networking app user's spoken command into a strict JSON FilterCommand.

Output ONLY a JSON object with these keys:
- "action": one of "filter" | "rank" | "reset" | "draft"
- "includeTags": string[] from the fixed vocabulary
- "excludeTags": string[] from the fixed vocabulary
- "rankBy": one of "relevance" | "infra" | "growth" | "ai" | "founder" | null
- "targetPersonId": a person id string or null
- "rawText": echo the user's text

Fixed tag vocabulary (use ONLY these, exact casing): ${TAG_VOCABULARY.join(", ")}.

Rules:
- "show me X" / "only X people" -> action "filter".
- "who should I talk to about X" -> action "rank", rankBy reflecting X.
- "reset" / "clear" / "show everyone" -> action "reset", empty tags.
- "draft an opener for NAME" / "write to NAME" -> action "draft"; set targetPersonId if you can match a roster name, else null.
- Map natural language to the vocabulary (e.g. "infrastructure" -> "Infra", "machine learning" -> "ML").
- Never invent tags outside the vocabulary.`;

export const interpretCommand = action({
  args: {
    transcript: v.string(),
    visiblePersonIds: v.optional(v.array(v.string())),
  },
  returns: filterCommandValidator,
  handler: async (ctx, args): Promise<FilterCommand> => {
    const transcript = args.transcript;
    const people = await ctx.runQuery(api.people.list, {});
    const roster: RosterEntry[] = people.map((p) => ({ id: p.id, name: p.name }));
    const rosterIds = new Set(roster.map((r) => r.id));

    const { apiKey, model } = getOpenAiConfig(process.env);

    if (apiKey) {
      try {
        const rosterHint = roster.map((r) => `${r.id} = ${r.name}`).join("; ");
        const obj = await chatJson({
          apiKey,
          model,
          system: SYSTEM_PROMPT,
          user: `Roster: ${rosterHint}\n\nUser said: "${transcript}"`,
        });
        const cmd = sanitizeFilterCommand(obj, transcript);
        return reconcileTarget(cmd, transcript, roster, rosterIds);
      } catch {
        // Fall through to offline parsing.
      }
    }

    return parseCommandOffline(transcript, roster);
  },
});

/** Ensure a draft target id is real; resolve from transcript when needed. */
function reconcileTarget(
  cmd: FilterCommand,
  transcript: string,
  roster: RosterEntry[],
  rosterIds: Set<string>,
): FilterCommand {
  if (cmd.action !== "draft") return cmd;
  if (cmd.targetPersonId && rosterIds.has(cmd.targetPersonId)) return cmd;
  return { ...cmd, targetPersonId: resolveTargetPerson(transcript, roster) };
}

export const getDeepgramToken = action({
  args: {},
  returns: v.object({
    temporaryToken: v.string(),
    expiresAt: v.number(),
  }),
  handler: async (): Promise<{ temporaryToken: string; expiresAt: number }> => {
    const key = getDeepgramApiKey(process.env);
    const ttlSeconds = 60;

    if (!key) {
      return {
        temporaryToken: "stub-deepgram-token-no-key-configured",
        expiresAt: Date.now() + ttlSeconds * 1000,
      };
    }

    try {
      const res = await fetch("https://api.deepgram.com/v1/auth/grant", {
        method: "POST",
        headers: {
          Authorization: `Token ${key}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ ttl_seconds: ttlSeconds }),
      });
      if (!res.ok) throw new Error(`Deepgram grant HTTP ${res.status}`);
      const data = (await res.json()) as { access_token?: string; expires_in?: number };
      if (!data.access_token) throw new Error("Deepgram grant returned no access_token");
      const expiresIn = typeof data.expires_in === "number" ? data.expires_in : ttlSeconds;
      return {
        temporaryToken: data.access_token,
        expiresAt: Date.now() + expiresIn * 1000,
      };
    } catch {
      return {
        temporaryToken: "stub-deepgram-token-grant-failed",
        expiresAt: Date.now() + ttlSeconds * 1000,
      };
    }
  },
});
