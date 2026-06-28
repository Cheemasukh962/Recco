/**
 * Reactive app state.
 *
 *   state:get      (public query)    -> BrainState   (main iOS subscription)
 *   state:setFilter(public mutation) -> BrainState   (recompute visible/dimmed)
 *   internal helpers used by vision actions to record match results.
 */

import { query, mutation, internalMutation } from "./_generated/server.js";
import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel.js";
import { brainStateValidator, faceMatchResultValidator, filterCommandValidator } from "./validators.js";
import type { BrainState, FilterCommand, FaceMatchResult, Person } from "./lib/types.js";
import { applyFilter, emptyBrainState } from "./lib/filter.js";

const SINGLETON_KEY = "singleton";

/** Strip Convex bookkeeping fields, returning a clean BrainState. */
export function toBrainState(doc: Doc<"appState">): BrainState {
  const { _id, _creationTime, key, ...rest } = doc;
  void _id;
  void _creationTime;
  void key;
  return rest;
}

/** Map a people doc to the full Person shape (for visibility recompute). */
function toPerson(d: Doc<"people">): Person {
  return {
    id: d.personId,
    name: d.name,
    role: d.role,
    company: d.company,
    avatarUrl: d.avatarUrl,
    bio: d.bio,
    tags: d.tags,
    links: d.links,
    whyTalk: d.whyTalk,
    openerSeed: d.openerSeed,
    faceEmbedding: d.faceEmbedding ?? null,
  };
}

/** state:get — the single reactive BrainState. Returns a default if unseeded. */
export const get = query({
  args: {},
  returns: brainStateValidator,
  handler: async (ctx): Promise<BrainState> => {
    const doc = await ctx.db
      .query("appState")
      .withIndex("by_key", (q) => q.eq("key", SINGLETON_KEY))
      .unique();
    if (doc) return toBrainState(doc);
    // Unseeded fallback: everyone visible. updatedAt 0 keeps queries deterministic.
    const people = await ctx.db.query("people").collect();
    return emptyBrainState(people.map((p) => ({ id: p.personId })), 0);
  },
});

/**
 * state:setFilter — apply a FilterCommand, recompute visible/dimmed, persist,
 * and return the new BrainState. Creates the singleton if it does not exist.
 */
export const setFilter = mutation({
  args: { command: filterCommandValidator },
  returns: brainStateValidator,
  handler: async (ctx, args): Promise<BrainState> => {
    const command = args.command as FilterCommand;
    const peopleDocs = await ctx.db.query("people").collect();
    const people = peopleDocs.map(toPerson);
    const now = Date.now();

    const existing = await ctx.db
      .query("appState")
      .withIndex("by_key", (q) => q.eq("key", SINGLETON_KEY))
      .unique();

    const prev: BrainState = existing
      ? toBrainState(existing)
      : emptyBrainState(people, now);

    const next = applyFilter(prev, command, people, now);

    if (existing) {
      await ctx.db.patch(existing._id, { ...next, key: SINGLETON_KEY });
    } else {
      await ctx.db.insert("appState", { ...next, key: SINGLETON_KEY });
    }
    return next;
  },
});

/**
 * Internal: record a face match into BrainState. Sets lastMatch always and
 * highlightedPersonId only for strong ("matched") results. Also appends to the
 * faceMatches log. Used by vision:matchFace.
 */
export const recordMatch = internalMutation({
  args: { result: faceMatchResultValidator, source: v.optional(v.string()) },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const result = args.result as FaceMatchResult;
    const now = Date.now();

    const existing = await ctx.db
      .query("appState")
      .withIndex("by_key", (q) => q.eq("key", SINGLETON_KEY))
      .unique();

    const people = await ctx.db.query("people").collect();
    const base: BrainState = existing
      ? toBrainState(existing)
      : emptyBrainState(people.map((p) => ({ id: p.personId })), now);

    const next: BrainState = {
      ...base,
      lastMatch: result,
      updatedAt: now,
    };
    // Only a strong match changes the highlight; tentative/unknown leave it be.
    if (result.status === "matched" && result.personId) {
      next.highlightedPersonId = result.personId;
    }

    if (existing) {
      await ctx.db.patch(existing._id, { ...next, key: SINGLETON_KEY });
    } else {
      await ctx.db.insert("appState", { ...next, key: SINGLETON_KEY });
    }

    await ctx.db.insert("faceMatches", {
      trackId: result.trackId,
      result,
      source: args.source,
      createdAt: now,
    });
    return null;
  },
});

/** Internal: ensure a singleton appState row exists (used by seeding). */
export const ensure = internalMutation({
  args: {},
  returns: v.null(),
  handler: async (ctx): Promise<null> => {
    const existing = await ctx.db
      .query("appState")
      .withIndex("by_key", (q) => q.eq("key", SINGLETON_KEY))
      .unique();
    if (existing) return null;
    const people = await ctx.db.query("people").collect();
    const state = emptyBrainState(people.map((p) => ({ id: p.personId })), Date.now());
    await ctx.db.insert("appState", { ...state, key: SINGLETON_KEY });
    return null;
  },
});
