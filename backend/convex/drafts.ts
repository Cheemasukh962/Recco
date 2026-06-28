/**
 * Opener drafting.
 *
 *   drafts:createOpener (public action) -> DraftResult
 *   internal: record (mutation) to persist generated drafts.
 *
 * Uses OpenAI when OPENAI_API_KEY is set, otherwise a deterministic templated
 * generator. Both return the same DraftResult shape. Never throws.
 */

import { action, internalMutation } from "./_generated/server.js";
import { internal } from "./_generated/api.js";
import { v } from "convex/values";
import { draftResultValidator } from "./validators.js";
import type { DraftResult, Person, PublicPerson } from "./lib/types.js";
import { getOpenAiConfig } from "./lib/config.js";
import { chatJson } from "./lib/openai.js";
import { buildOpenerOffline, sanitizeDraft, topicForPerson } from "./lib/opener.js";

const SYSTEM_PROMPT = `You write a short, warm, specific networking opener from one hackathon attendee to another.

Output ONLY a JSON object: { "subject": string, "opener": string, "email": string }.

Rules:
- 1-2 sentences for "opener". Human, not salesy.
- Reference the person's actual work/tags. Never invent facts.
- "subject" is a short email subject. "email" is a 2-3 line version of the opener with a friendly sign-off.`;

/** A PublicPerson is enough for drafting; widen to Person for the helpers. */
function asPerson(p: PublicPerson): Person {
  return { ...p, faceEmbedding: null };
}

export const createOpener = action({
  args: {
    personId: v.string(),
    userGoal: v.optional(v.union(v.string(), v.null())),
  },
  returns: draftResultValidator,
  handler: async (ctx, args): Promise<DraftResult> => {
    const now = Date.now();
    const userGoal = args.userGoal ?? null;

    const publicPerson = await ctx.runQuery(internal.people.getPublicByPersonId, {
      personId: args.personId,
    });

    if (!publicPerson) {
      // Honest, non-throwing fallback for an unknown id.
      return {
        personId: args.personId,
        subject: null,
        opener: `I couldn't find "${args.personId}" in the roster yet — double-check the person id.`,
        email: null,
        generatedAt: now,
      };
    }

    const person = asPerson(publicPerson);
    let draft = buildOpenerOffline(person, userGoal, now);
    let source = "template";

    const { apiKey, model } = getOpenAiConfig(process.env);
    if (apiKey) {
      try {
        const topic = topicForPerson(person);
        const obj = await chatJson({
          apiKey,
          model,
          system: SYSTEM_PROMPT,
          user:
            `Person: ${person.name}, ${person.role} at ${person.company}.\n` +
            `Bio: ${person.bio}\n` +
            `Tags: ${person.tags.join(", ")}\n` +
            `Why talk: ${person.whyTalk}\n` +
            `Seed idea: ${person.openerSeed ?? topic}\n` +
            (userGoal ? `My goal: ${userGoal}\n` : "") +
            `Write the opener now.`,
          temperature: 0.6,
        });
        const sanitized = sanitizeDraft(obj, person, now);
        if (sanitized) {
          draft = sanitized;
          source = "openai";
        }
      } catch {
        // Keep the templated draft.
      }
    }

    await ctx.runMutation(internal.drafts.record, { draft, source }).catch(() => {});
    return draft;
  },
});

/** Internal: persist a generated draft (history; latest wins on read). */
export const record = internalMutation({
  args: { draft: draftResultValidator, source: v.optional(v.string()) },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const d = args.draft;
    await ctx.db.insert("drafts", {
      personId: d.personId,
      subject: d.subject,
      opener: d.opener,
      email: d.email,
      source: args.source,
      generatedAt: d.generatedAt,
    });
    return null;
  },
});
