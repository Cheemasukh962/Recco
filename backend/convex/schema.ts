/**
 * Convex schema for the Recco backend.
 *
 *   people         - the enrolled demo roster (+ server-side face embeddings)
 *   appState       - the single reactive BrainState the iOS app subscribes to
 *   faceMatches    - append-only log of match attempts (debugging / analytics)
 *   drafts         - generated openers (history; latest wins on read)
 *   identityLookups- append-only debug log of "find info on him" resolutions
 *                    (extracted text + scores only; NEVER raw images)
 */

import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import {
  brainStateValidator,
  faceMatchResultValidator,
  filterCommandValidator,
  gtmIntentValidator,
  missionCoreValidator,
  missionSnapshotValidator,
  outreachDraftValidator,
  personLinksValidator,
} from "./validators.js";

export default defineSchema({
  people: defineTable({
    // Stable contract id (e.g. "person_ava_shah"). Distinct from Convex _id.
    personId: v.string(),
    name: v.string(),
    role: v.string(),
    company: v.string(),
    avatarUrl: v.optional(v.string()),
    bio: v.string(),
    tags: v.array(v.string()),
    links: personLinksValidator,
    whyTalk: v.string(),
    openerSeed: v.optional(v.string()),
    // Server-side only; never returned to iOS.
    faceEmbedding: v.optional(v.union(v.array(v.number()), v.null())),
  }).index("by_personId", ["personId"]),

  // Singleton document; `key` is always "singleton".
  appState: defineTable({
    key: v.string(),
    ...brainStateValidator.fields,
  }).index("by_key", ["key"]),

  faceMatches: defineTable({
    trackId: v.string(),
    result: faceMatchResultValidator,
    source: v.optional(v.string()),
    createdAt: v.number(),
  }).index("by_trackId", ["trackId"]),

  drafts: defineTable({
    personId: v.string(),
    subject: v.optional(v.union(v.string(), v.null())),
    opener: v.string(),
    email: v.optional(v.union(v.string(), v.null())),
    source: v.optional(v.string()),
    generatedAt: v.number(),
  }).index("by_personId", ["personId"]),

  // Debug log for identity resolution. Stores only extracted text + scores so
  // a demo can be inspected after the fact; raw face/badge images are NEVER
  // persisted.
  identityLookups: defineTable({
    trackId: v.string(),
    status: v.string(),
    transcript: v.optional(v.union(v.string(), v.null())),
    clueName: v.optional(v.union(v.string(), v.null())),
    clueCompany: v.optional(v.union(v.string(), v.null())),
    ocrConfidence: v.optional(v.union(v.number(), v.null())),
    candidateCount: v.number(),
    selectedCandidateId: v.optional(v.union(v.string(), v.null())),
    selectedName: v.optional(v.union(v.string(), v.null())),
    selectedLinkedin: v.optional(v.union(v.string(), v.null())),
    verificationScore: v.optional(v.union(v.number(), v.null())),
    verified: v.optional(v.union(v.boolean(), v.null())),
    latencyMs: v.optional(v.union(v.number(), v.null())),
    createdAt: v.number(),
  }).index("by_trackId", ["trackId"]),

  // Durable "event memory": one row per resolved person, deduped by LinkedIn
  // (then normalized name+company). Stores extracted metadata, links, scores,
  // notes, and generated outreach — NEVER raw face/badge images.
  scanMemories: defineTable({
    scanId: v.string(),
    personId: v.optional(v.union(v.string(), v.null())),
    name: v.optional(v.union(v.string(), v.null())),
    headline: v.optional(v.union(v.string(), v.null())),
    role: v.optional(v.union(v.string(), v.null())),
    company: v.optional(v.union(v.string(), v.null())),
    school: v.optional(v.union(v.string(), v.null())),
    linkedinUrl: v.optional(v.union(v.string(), v.null())),
    email: v.optional(v.union(v.string(), v.null())),
    confidence: v.string(),
    confidenceScore: v.optional(v.union(v.number(), v.null())),
    sources: v.array(v.string()),
    notes: v.optional(v.union(v.string(), v.null())),
    badgeText: v.optional(v.union(v.string(), v.null())),
    outreach: v.optional(v.union(outreachDraftValidator, v.null())),
    // Normalized dedup keys (server-side only; never returned to iOS).
    linkedinKey: v.optional(v.union(v.string(), v.null())),
    nameCompanyKey: v.optional(v.union(v.string(), v.null())),
    firstScannedAt: v.number(),
    lastScannedAt: v.number(),
    scanCount: v.number(),
    // Mission-driven lead scoring + follow-up. All optional so existing rows
    // (written before this feature) keep validating.
    clientId: v.optional(v.union(v.string(), v.null())),
    leadPriority: v.optional(v.union(v.string(), v.null())),
    leadScore: v.optional(v.union(v.number(), v.null())),
    leadReasons: v.optional(v.array(v.string())),
    nextAction: v.optional(v.union(v.string(), v.null())),
    followUpStatus: v.optional(v.union(v.string(), v.null())),
    followUpChannel: v.optional(v.union(v.string(), v.null())),
    sentAt: v.optional(v.union(v.number(), v.null())),
    editedOutreach: v.optional(v.union(outreachDraftValidator, v.null())),
    missionSnapshot: v.optional(v.union(missionSnapshotValidator, v.null())),
  })
    .index("by_linkedinKey", ["linkedinKey"])
    .index("by_nameCompanyKey", ["nameCompanyKey"])
    .index("by_lastScannedAt", ["lastScannedAt"])
    .index("by_clientId_lastScannedAt", ["clientId", "lastScannedAt"])
    .index("by_clientId_priority", ["clientId", "leadPriority"]),

  // One stored mission ("Today's Goal") per anonymous clientId. Text only.
  missionProfiles: defineTable({
    clientId: v.string(),
    ...missionCoreValidator.fields,
  }).index("by_clientId", ["clientId"]),

  // Lazy GTM / Scout Mode: a voice/text request -> a search run + AI-found
  // prospects. Kept separate from scanMemories (real people the user met).
  gtmRuns: defineTable({
    clientId: v.string(),
    rawText: v.string(),
    parsedIntent: v.optional(v.union(gtmIntentValidator, v.null())),
    goalType: v.string(),
    query: v.string(),
    count: v.number(),
    status: v.string(), // "running" | "ready" | "error"
    errorMessage: v.optional(v.union(v.string(), v.null())),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_clientId_createdAt", ["clientId", "createdAt"]),

  gtmProspects: defineTable({
    runId: v.string(),
    clientId: v.string(),
    prospectId: v.string(),
    name: v.string(),
    headline: v.optional(v.union(v.string(), v.null())),
    role: v.optional(v.union(v.string(), v.null())),
    company: v.optional(v.union(v.string(), v.null())),
    location: v.optional(v.union(v.string(), v.null())),
    linkedinUrl: v.optional(v.union(v.string(), v.null())),
    email: v.optional(v.union(v.string(), v.null())),
    profilePhotoUrl: v.optional(v.union(v.string(), v.null())),
    source: v.string(),
    matchScore: v.number(),
    priority: v.string(),
    reasons: v.array(v.string()),
    missingInfo: v.array(v.string()),
    outreach: v.optional(v.union(outreachDraftValidator, v.null())),
    selectedChannel: v.optional(v.union(v.string(), v.null())),
    status: v.string(), // "new" | "drafted" | "sent" | "archived"
    sentAt: v.optional(v.union(v.number(), v.null())),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_runId", ["runId"])
    .index("by_clientId_createdAt", ["clientId", "createdAt"]),
});

// Re-export so callers can build args that match the stored filter shape.
export { filterCommandValidator };
