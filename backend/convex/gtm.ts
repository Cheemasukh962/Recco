/**
 * Lazy GTM / Scout Mode.
 *
 *   gtm:run               (action)    -> { run, prospects }   ({ clientId, transcript, count? })
 *   gtm:listRuns          (query)     -> GTMRun[]             ({ clientId })
 *   gtm:listProspects     (query)     -> GTMProspect[]        ({ clientId, runId? })
 *   gtm:generateOutreach  (action)    -> OutreachDraft        (regenerate for one prospect)
 *   gtm:updateProspectStatus (mutation) -> GTMProspect | null (channel/status/edited/sentAt)
 *
 * A voice/text request is parsed into a structured GTM intent (OpenAI w/ a
 * deterministic fallback), Fiber finds ~N prospects (deterministic mock fallback
 * when Fiber is unavailable), each is scored + drafted, and the run + prospects
 * are persisted. Scout prospects are NEVER scan memories — separate tables.
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
import type { Doc } from "./_generated/dataModel.js";
import {
  gtmIntentValidator,
  gtmProspectValidator,
  gtmRunValidator,
  outreachDraftValidator,
} from "./validators.js";
import {
  parseGTMIntentFallback,
  sanitizeGTMIntent,
  clampCount,
  type GTMIntent,
} from "./lib/gtmIntent.js";
import {
  fiberToProspect,
  mockProspects,
  prospectOutreach,
  scoreProspect,
  type ProspectInput,
} from "./lib/gtmProspects.js";
import { searchProspects } from "./lib/fiber.js";
import {
  buildOutreachOffline,
  sanitizeOutreach,
  type OutreachDraft,
} from "./lib/outreach.js";
import { getOpenAiConfig, getFiberConfig } from "./lib/config.js";
import { chatJson } from "./lib/openai.js";

type RunDoc = Doc<"gtmRuns">;
type ProspectDoc = Doc<"gtmProspects">;

type PublicRun = {
  id: string;
  clientId: string;
  rawText: string;
  parsedIntent: GTMIntent | null;
  goalType: string;
  query: string;
  count: number;
  status: string;
  errorMessage: string | null;
  createdAt: number;
  updatedAt: number;
};

function toPublicRun(doc: RunDoc): PublicRun {
  return {
    id: doc._id as string,
    clientId: doc.clientId,
    rawText: doc.rawText,
    parsedIntent: (doc.parsedIntent ?? null) as GTMIntent | null,
    goalType: doc.goalType,
    query: doc.query,
    count: doc.count,
    status: doc.status,
    errorMessage: doc.errorMessage ?? null,
    createdAt: doc.createdAt,
    updatedAt: doc.updatedAt,
  };
}

function toPublicProspect(doc: ProspectDoc) {
  return {
    id: doc._id as string,
    runId: doc.runId,
    clientId: doc.clientId,
    prospectId: doc.prospectId,
    name: doc.name,
    headline: doc.headline ?? null,
    role: doc.role ?? null,
    company: doc.company ?? null,
    location: doc.location ?? null,
    linkedinUrl: doc.linkedinUrl ?? null,
    email: doc.email ?? null,
    profilePhotoUrl: doc.profilePhotoUrl ?? null,
    source: doc.source,
    matchScore: doc.matchScore,
    priority: doc.priority,
    reasons: doc.reasons,
    missingInfo: doc.missingInfo,
    outreach: doc.outreach ?? null,
    selectedChannel: doc.selectedChannel ?? null,
    status: doc.status,
    sentAt: doc.sentAt ?? null,
    createdAt: doc.createdAt,
    updatedAt: doc.updatedAt,
  };
}

const GTM_SYSTEM = `You convert a networking "scout" request into a structured GTM search intent JSON.

Output ONLY a JSON object:
{
  "goalType": "hiring" | "fundraising" | "customers" | "sponsors" | "founders" | "networking" | "other",
  "searchQuery": string,           // a concise natural-language people search
  "targetRoles": string[],         // specific roles to find, e.g. ["swift engineer"]
  "targetKeywords": string[],
  "targetCompanies": string[],
  "targetIndustries": string[],
  "count": number,                 // how many people to find (default 8)
  "preferredAction": "linkedin_dm" | "cold_email" | "in_person" | "reminder"
}

Rules:
- "hire a Swift engineer" -> hiring, roles ["swift engineer"].
- "find investors for my AI infra startup" -> fundraising, industries ["ai","infra"].
- "find startup founders" -> founders. "sponsorships" -> sponsors.
- Keep arrays tight and lowercase. Never invent companies that weren't mentioned.`;

const OUTREACH_SYSTEM = `You write concise, natural, non-salesy outreach to a prospect found for a networking goal.

Output ONLY a JSON object: { "linkedinDm": string, "coldEmailSubject": string, "coldEmail": string, "inPersonOpener": string }.

Rules:
- Reference the person's actual role/company. Never invent facts.
- Tailor lightly to the sender's goal (hiring, fundraising, sponsors, customers, founders).
- "linkedinDm": 1-2 sentences. "coldEmail": 3-5 short lines + warm sign-off. "inPersonOpener": one friendly sentence.`;

// --- Run (action) -----------------------------------------------------------

export const run = action({
  args: {
    clientId: v.string(),
    transcript: v.string(),
    count: v.optional(v.union(v.number(), v.null())),
  },
  returns: v.object({ run: gtmRunValidator, prospects: v.array(gtmProspectValidator) }),
  handler: async (ctx, args): Promise<{ run: PublicRun; prospects: ReturnType<typeof toPublicProspect>[] }> => {
    const now = Date.now();
    const requestedCount = clampCount(args.count ?? undefined);

    // 1. Parse intent (OpenAI w/ deterministic fallback).
    let intent: GTMIntent = parseGTMIntentFallback(args.transcript, requestedCount, now);
    const { apiKey, model } = getOpenAiConfig(process.env);
    if (apiKey && args.transcript.trim()) {
      try {
        const obj = await chatJson({
          apiKey,
          model,
          system: GTM_SYSTEM,
          user: `Request: "${args.transcript}"\nDesired count: ${requestedCount}\nReturn the intent JSON now.`,
          temperature: 0.2,
        });
        intent = sanitizeGTMIntent(obj, args.transcript, requestedCount, now);
      } catch {
        // Keep the deterministic fallback.
      }
    }

    // 2. Find prospects (Fiber, else deterministic mock).
    let inputs: ProspectInput[] = [];
    let errorMessage: string | null = null;
    const fiber = getFiberConfig(process.env);
    if (fiber.apiKey) {
      try {
        const candidates = await searchProspects(intent.searchQuery, intent.count, { config: fiber });
        inputs = candidates.map(fiberToProspect);
      } catch (err) {
        errorMessage = err instanceof Error ? err.message : String(err);
      }
    }
    if (inputs.length === 0) {
      inputs = mockProspects(intent, intent.count, now);
    }
    inputs = inputs.slice(0, intent.count);

    // 3. Score + draft + rank (hot first).
    const scored = inputs.map((p) => {
      const sc = scoreProspect(p, intent, now);
      return { input: p, sc, outreach: prospectOutreach(p, intent, now) };
    });
    scored.sort((a, b) => b.sc.score - a.sc.score);

    // 4. Persist run + prospects atomically.
    return ctx.runMutation(internal.gtm.commitRun, {
      clientId: args.clientId,
      rawText: args.transcript,
      intent,
      errorMessage,
      prospects: scored.map(({ input, sc, outreach }) => ({
        prospectId: input.prospectId,
        name: input.name,
        headline: input.headline,
        role: input.role,
        company: input.company,
        location: input.location,
        linkedinUrl: input.linkedinUrl,
        email: input.email,
        profilePhotoUrl: input.profilePhotoUrl,
        source: input.source,
        matchScore: input.matchScore,
        priority: sc.priority,
        reasons: sc.reasons,
        missingInfo: sc.missingInfo,
        outreach,
      })),
    });
  },
});

const prospectSeedValidator = v.object({
  prospectId: v.string(),
  name: v.string(),
  headline: v.union(v.string(), v.null()),
  role: v.union(v.string(), v.null()),
  company: v.union(v.string(), v.null()),
  location: v.union(v.string(), v.null()),
  linkedinUrl: v.union(v.string(), v.null()),
  email: v.union(v.string(), v.null()),
  profilePhotoUrl: v.union(v.string(), v.null()),
  source: v.string(),
  matchScore: v.number(),
  priority: v.string(),
  reasons: v.array(v.string()),
  missingInfo: v.array(v.string()),
  outreach: v.union(outreachDraftValidator, v.null()),
});

export const commitRun = internalMutation({
  args: {
    clientId: v.string(),
    rawText: v.string(),
    intent: gtmIntentValidator,
    errorMessage: v.optional(v.union(v.string(), v.null())),
    prospects: v.array(prospectSeedValidator),
  },
  returns: v.object({ run: gtmRunValidator, prospects: v.array(gtmProspectValidator) }),
  handler: async (ctx, args): Promise<{ run: PublicRun; prospects: ReturnType<typeof toPublicProspect>[] }> => {
    const now = Date.now();
    const runId = await ctx.db.insert("gtmRuns", {
      clientId: args.clientId,
      rawText: args.rawText,
      parsedIntent: args.intent,
      goalType: args.intent.goalType,
      query: args.intent.searchQuery,
      count: args.intent.count,
      status: "ready",
      errorMessage: args.errorMessage ?? null,
      createdAt: now,
      updatedAt: now,
    });
    const runIdStr = runId as string;

    const prospects: ReturnType<typeof toPublicProspect>[] = [];
    for (const p of args.prospects) {
      const pid = await ctx.db.insert("gtmProspects", {
        runId: runIdStr,
        clientId: args.clientId,
        prospectId: p.prospectId,
        name: p.name,
        headline: p.headline,
        role: p.role,
        company: p.company,
        location: p.location,
        linkedinUrl: p.linkedinUrl,
        email: p.email,
        profilePhotoUrl: p.profilePhotoUrl,
        source: p.source,
        matchScore: p.matchScore,
        priority: p.priority,
        reasons: p.reasons,
        missingInfo: p.missingInfo,
        outreach: p.outreach,
        selectedChannel: null,
        status: p.outreach ? "drafted" : "new",
        sentAt: null,
        createdAt: now,
        updatedAt: now,
      });
      prospects.push(toPublicProspect((await ctx.db.get(pid))!));
    }
    return { run: toPublicRun((await ctx.db.get(runId))!), prospects };
  },
});

// --- Queries ----------------------------------------------------------------

export const listRuns = query({
  args: { clientId: v.string() },
  returns: v.array(gtmRunValidator),
  handler: async (ctx, args) => {
    const docs = await ctx.db
      .query("gtmRuns")
      .withIndex("by_clientId_createdAt", (q) => q.eq("clientId", args.clientId))
      .order("desc")
      .collect();
    return docs.map(toPublicRun);
  },
});

export const listProspects = query({
  args: { clientId: v.string(), runId: v.optional(v.union(v.string(), v.null())) },
  returns: v.array(gtmProspectValidator),
  handler: async (ctx, args) => {
    if (args.runId) {
      const docs = await ctx.db
        .query("gtmProspects")
        .withIndex("by_runId", (q) => q.eq("runId", args.runId!))
        .collect();
      return docs
        .filter((d) => d.clientId === args.clientId)
        .sort((a, b) => b.matchScore - a.matchScore)
        .map(toPublicProspect);
    }
    const docs = await ctx.db
      .query("gtmProspects")
      .withIndex("by_clientId_createdAt", (q) => q.eq("clientId", args.clientId))
      .order("desc")
      .collect();
    return docs.map(toPublicProspect);
  },
});

// --- Outreach (action) ------------------------------------------------------

export const getProspectInternal = internalQuery({
  args: { id: v.string() },
  returns: v.union(gtmProspectValidator, v.null()),
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("gtmProspects", args.id);
    if (!id) return null;
    const doc = await ctx.db.get(id);
    return doc ? toPublicProspect(doc) : null;
  },
});

export const getRunGoalInternal = internalQuery({
  args: { id: v.string() },
  returns: v.union(v.string(), v.null()),
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("gtmRuns", args.id);
    if (!id) return null;
    const doc = await ctx.db.get(id);
    return doc ? doc.goalType : null;
  },
});

export const saveProspectOutreach = internalMutation({
  args: { id: v.string(), outreach: outreachDraftValidator },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const id = ctx.db.normalizeId("gtmProspects", args.id);
    if (id) await ctx.db.patch(id, { outreach: args.outreach, status: "drafted", updatedAt: Date.now() });
    return null;
  },
});

export const generateOutreach = action({
  args: {
    id: v.string(),
    eventName: v.optional(v.union(v.string(), v.null())),
    senderName: v.optional(v.union(v.string(), v.null())),
  },
  returns: outreachDraftValidator,
  handler: async (ctx, args): Promise<OutreachDraft> => {
    const now = Date.now();
    const prospect = await ctx.runQuery(internal.gtm.getProspectInternal, { id: args.id });
    if (!prospect) {
      // Nothing to draft against — return a neutral draft.
      return buildOutreachOffline({ eventName: args.eventName ?? null, senderName: args.senderName ?? null }, now);
    }
    const goalType = await ctx.runQuery(internal.gtm.getRunGoalInternal, { id: prospect.runId });

    const input = {
      name: prospect.name,
      role: prospect.role,
      company: prospect.company,
      headline: prospect.headline,
      eventName: args.eventName ?? null,
      senderName: args.senderName ?? null,
      goalType: goalType ?? null,
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
            `Person: ${input.name}${input.role ? `, ${input.role}` : ""}${input.company ? ` at ${input.company}` : ""}.\n` +
            (input.headline ? `Headline: ${input.headline}\n` : "") +
            (goalType ? `My goal: ${goalType}\n` : "") +
            `Why they matter: ${prospect.reasons.join("; ")}\n` +
            `My name: ${input.senderName ?? "(omit sign-off name)"}\n` +
            `Write the outreach now.`,
          temperature: 0.6,
        });
        draft = sanitizeOutreach(obj, draft);
      } catch {
        // Keep deterministic draft.
      }
    }

    await ctx.runMutation(internal.gtm.saveProspectOutreach, { id: args.id, outreach: draft }).catch(() => {});
    return draft;
  },
});

// --- Status (mutation) ------------------------------------------------------

const PROSPECT_STATUSES = new Set(["new", "drafted", "sent", "archived"]);
const PROSPECT_CHANNELS = new Set(["linkedin_dm", "cold_email", "in_person"]);

export const updateProspectStatus = mutation({
  args: {
    id: v.string(),
    status: v.string(),
    channel: v.optional(v.union(v.string(), v.null())),
    editedOutreach: v.optional(v.union(outreachDraftValidator, v.null())),
    sentAt: v.optional(v.union(v.number(), v.null())),
  },
  returns: v.union(gtmProspectValidator, v.null()),
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("gtmProspects", args.id);
    if (!id) return null;
    const doc = await ctx.db.get(id);
    if (!doc) return null;

    const status = PROSPECT_STATUSES.has(args.status) ? args.status : "new";
    const patch: Partial<ProspectDoc> = { status, updatedAt: Date.now() };
    if (args.channel !== undefined) {
      patch.selectedChannel = args.channel && PROSPECT_CHANNELS.has(args.channel) ? args.channel : null;
    }
    if (args.editedOutreach !== undefined && args.editedOutreach !== null) {
      patch.outreach = args.editedOutreach;
    }
    if (status === "sent") patch.sentAt = args.sentAt ?? Date.now();
    else if (args.sentAt !== undefined) patch.sentAt = args.sentAt;

    await ctx.db.patch(id, patch);
    return toPublicProspect((await ctx.db.get(id))!);
  },
});
