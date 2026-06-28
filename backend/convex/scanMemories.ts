/**
 * Brain scan memory — durable "event memory".
 *
 *   scanMemories:list                     (query)    -> ScanMemory[]
 *   scanMemories:get                      (query)    -> ScanMemory | null
 *   scanMemories:upsertFromIdentityResult (mutation) -> ScanMemory
 *   scanMemories:updateNotes              (mutation) -> ScanMemory | null
 *   scanMemories:generateOutreach         (action)   -> OutreachDraft
 *
 * Dedup: a scan updates an existing memory when its normalized LinkedIn matches,
 * else when its normalized name+company matches; otherwise it inserts a new row.
 * Only extracted text/links/scores are stored — never raw images.
 */

import {
  action,
  mutation,
  query,
  internalMutation,
  internalQuery,
} from "./_generated/server.js";
import { internal } from "./_generated/api.js";
import { v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel.js";
import { outreachDraftValidator, scanMemoryValidator } from "./validators.js";
import {
  mergeMemory,
  normalizeLinkedIn,
  nameCompanyKey,
  type ScanMemoryFields,
  type ScanMemoryUpsertInput,
} from "./lib/scanMemory.js";
import {
  buildOutreachOffline,
  sanitizeOutreach,
  type OutreachDraft,
} from "./lib/outreach.js";
import { getOpenAiConfig } from "./lib/config.js";
import { chatJson } from "./lib/openai.js";

type ScanMemoryDoc = Doc<"scanMemories">;

/** Public projection: drop server-only dedup keys, expose `_id` as `id`. */
function toPublic(doc: ScanMemoryDoc) {
  return {
    id: doc._id as string,
    scanId: doc.scanId,
    personId: doc.personId ?? null,
    name: doc.name ?? null,
    headline: doc.headline ?? null,
    role: doc.role ?? null,
    company: doc.company ?? null,
    school: doc.school ?? null,
    linkedinUrl: doc.linkedinUrl ?? null,
    email: doc.email ?? null,
    confidence: doc.confidence,
    confidenceScore: doc.confidenceScore ?? null,
    sources: doc.sources,
    notes: doc.notes ?? null,
    badgeText: doc.badgeText ?? null,
    outreach: doc.outreach ?? null,
    firstScannedAt: doc.firstScannedAt,
    lastScannedAt: doc.lastScannedAt,
    scanCount: doc.scanCount,
  };
}

/** Extract just the mergeable stored fields from an existing doc. */
function fieldsOf(doc: ScanMemoryDoc): ScanMemoryFields {
  return {
    scanId: doc.scanId,
    personId: doc.personId ?? null,
    name: doc.name ?? null,
    headline: doc.headline ?? null,
    role: doc.role ?? null,
    company: doc.company ?? null,
    school: doc.school ?? null,
    linkedinUrl: doc.linkedinUrl ?? null,
    email: doc.email ?? null,
    confidence: doc.confidence as ScanMemoryFields["confidence"],
    confidenceScore: doc.confidenceScore ?? null,
    sources: doc.sources,
    badgeText: doc.badgeText ?? null,
    linkedinKey: doc.linkedinKey ?? null,
    nameCompanyKey: doc.nameCompanyKey ?? null,
    firstScannedAt: doc.firstScannedAt,
    lastScannedAt: doc.lastScannedAt,
    scanCount: doc.scanCount,
  };
}

// --- Queries ----------------------------------------------------------------

export const list = query({
  args: {},
  returns: v.array(scanMemoryValidator),
  handler: async (ctx) => {
    const docs = await ctx.db
      .query("scanMemories")
      .withIndex("by_lastScannedAt")
      .order("desc")
      .collect();
    return docs.map(toPublic);
  },
});

export const get = query({
  args: { id: v.string() },
  returns: v.union(scanMemoryValidator, v.null()),
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("scanMemories", args.id);
    if (!id) return null;
    const doc = await ctx.db.get(id);
    return doc ? toPublic(doc) : null;
  },
});

// --- Mutations --------------------------------------------------------------

const upsertArgs = {
  scanId: v.string(),
  status: v.string(),
  name: v.optional(v.union(v.string(), v.null())),
  headline: v.optional(v.union(v.string(), v.null())),
  role: v.optional(v.union(v.string(), v.null())),
  company: v.optional(v.union(v.string(), v.null())),
  school: v.optional(v.union(v.string(), v.null())),
  linkedinUrl: v.optional(v.union(v.string(), v.null())),
  email: v.optional(v.union(v.string(), v.null())),
  confidenceScore: v.optional(v.union(v.number(), v.null())),
  personId: v.optional(v.union(v.string(), v.null())),
  transcript: v.optional(v.union(v.string(), v.null())),
  badgeText: v.optional(v.union(v.string(), v.null())),
  hadFaceVerification: v.optional(v.boolean()),
  candidateCount: v.optional(v.number()),
};

/** Find an existing memory to update: LinkedIn key first, then name+company. */
async function findExisting(
  ctx: { db: { query: (t: "scanMemories") => any } },
  linkedinKey: string | null,
  ncKey: string | null,
): Promise<ScanMemoryDoc | null> {
  if (linkedinKey) {
    const hit = await ctx.db
      .query("scanMemories")
      .withIndex("by_linkedinKey", (q: any) => q.eq("linkedinKey", linkedinKey))
      .first();
    if (hit) return hit;
  }
  if (ncKey) {
    const hit = await ctx.db
      .query("scanMemories")
      .withIndex("by_nameCompanyKey", (q: any) => q.eq("nameCompanyKey", ncKey))
      .first();
    if (hit) return hit;
  }
  return null;
}

export const upsertFromIdentityResult = mutation({
  args: upsertArgs,
  returns: scanMemoryValidator,
  handler: async (ctx, args) => {
    const input: ScanMemoryUpsertInput = args;
    const now = Date.now();

    const linkedinKey = normalizeLinkedIn(input.linkedinUrl);
    const ncKey = nameCompanyKey(input.name, input.company);
    const existing = await findExisting(ctx, linkedinKey, ncKey);

    const fields = mergeMemory(existing ? fieldsOf(existing) : null, input, now);

    if (existing) {
      await ctx.db.patch(existing._id, fields);
      const updated = await ctx.db.get(existing._id);
      return toPublic(updated!);
    }
    const id = await ctx.db.insert("scanMemories", fields);
    const created = await ctx.db.get(id);
    return toPublic(created!);
  },
});

export const updateNotes = mutation({
  args: { id: v.string(), notes: v.union(v.string(), v.null()) },
  returns: v.union(scanMemoryValidator, v.null()),
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("scanMemories", args.id);
    if (!id) return null;
    const doc = await ctx.db.get(id);
    if (!doc) return null;
    const trimmed = args.notes && args.notes.trim() ? args.notes.trim() : null;
    await ctx.db.patch(id, { notes: trimmed });
    const updated = await ctx.db.get(id);
    return updated ? toPublic(updated) : null;
  },
});

// --- Outreach generation (action) -------------------------------------------

const OUTREACH_SYSTEM = `You write concise, natural, non-salesy networking outreach from one event attendee to another.

Output ONLY a JSON object: { "linkedinDm": string, "coldEmailSubject": string, "coldEmail": string, "inPersonOpener": string }.

Rules:
- Reference the person's actual role/company/work. Never invent facts.
- "linkedinDm": 1-2 sentences, friendly, mentions Recco (an AR memory layer for event networking).
- "coldEmail": 3-5 short lines with a warm sign-off; "coldEmailSubject" is a short subject.
- "inPersonOpener": one friendly sentence to restart a conversation at the event.
- Keep it human and specific, not corporate.`;

export const generateOutreach = action({
  args: {
    id: v.string(),
    eventName: v.optional(v.union(v.string(), v.null())),
    senderName: v.optional(v.union(v.string(), v.null())),
  },
  returns: outreachDraftValidator,
  handler: async (ctx, args): Promise<OutreachDraft> => {
    const now = Date.now();
    const memory = await ctx.runQuery(internal.scanMemories.getInternal, {
      id: args.id,
    });

    const input = {
      name: memory?.name ?? null,
      role: memory?.role ?? null,
      company: memory?.company ?? null,
      school: memory?.school ?? null,
      headline: memory?.headline ?? null,
      eventName: args.eventName ?? null,
      senderName: args.senderName ?? null,
    };

    let draft = buildOutreachOffline(input, now);

    const { apiKey, model } = getOpenAiConfig(process.env);
    if (apiKey) {
      try {
        const obj = await chatJson({
          apiKey,
          model,
          system: OUTREACH_SYSTEM,
          user:
            `Person: ${input.name ?? "Unknown"}` +
            `${input.role ? `, ${input.role}` : ""}` +
            `${input.company ? ` at ${input.company}` : ""}.\n` +
            (input.school ? `School: ${input.school}\n` : "") +
            (input.headline ? `Headline: ${input.headline}\n` : "") +
            `Event: ${input.eventName ?? "the event"}\n` +
            `My name: ${input.senderName ?? "(omit sign-off name)"}\n` +
            `Write the outreach now.`,
          temperature: 0.6,
        });
        draft = sanitizeOutreach(obj, draft);
      } catch {
        // Keep the deterministic draft.
      }
    }

    // Best-effort persist so reopening the memory shows the latest outreach.
    if (memory) {
      await ctx
        .runMutation(internal.scanMemories.saveOutreach, {
          id: args.id,
          outreach: draft,
        })
        .catch(() => {});
    }
    return draft;
  },
});

// --- Internal helpers for the action ----------------------------------------

export const getInternal = internalQuery({
  args: { id: v.string() },
  returns: v.union(scanMemoryValidator, v.null()),
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("scanMemories", args.id);
    if (!id) return null;
    const doc = await ctx.db.get(id);
    return doc ? toPublic(doc) : null;
  },
});

export const saveOutreach = internalMutation({
  args: { id: v.string(), outreach: outreachDraftValidator },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const id = ctx.db.normalizeId("scanMemories", args.id);
    if (id) await ctx.db.patch(id, { outreach: args.outreach });
    return null;
  },
});
