/**
 * People queries.
 *
 *   people:list (public query)  -> PublicPerson[]  (no embeddings; for iOS)
 *   internal helpers used by actions to read enrolled embeddings / one person.
 */

import { query, internalQuery } from "./_generated/server.js";
import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel.js";
import { publicPersonValidator } from "./validators.js";
import type { PublicPerson } from "./lib/types.js";
import { isFiniteVector } from "./lib/similarity.js";

/** Map a stored people doc to the public (iOS-facing) shape. */
export function toPublicPerson(doc: Doc<"people">): PublicPerson {
  const p: PublicPerson = {
    id: doc.personId,
    name: doc.name,
    role: doc.role,
    company: doc.company,
    bio: doc.bio,
    tags: doc.tags,
    links: doc.links,
    whyTalk: doc.whyTalk,
  };
  if (doc.avatarUrl !== undefined) p.avatarUrl = doc.avatarUrl;
  if (doc.openerSeed !== undefined) p.openerSeed = doc.openerSeed;
  return p;
}

/** people:list — the demo roster without server-side embeddings. */
export const list = query({
  args: {},
  returns: v.array(publicPersonValidator),
  handler: async (ctx): Promise<PublicPerson[]> => {
    const docs = await ctx.db.query("people").collect();
    return docs.map(toPublicPerson);
  },
});

/** Internal: enrolled (personId, embedding) pairs for face matching. */
export const listEnrolled = internalQuery({
  args: {},
  returns: v.array(v.object({ personId: v.string(), embedding: v.array(v.number()) })),
  handler: async (ctx): Promise<Array<{ personId: string; embedding: number[] }>> => {
    const docs = await ctx.db.query("people").collect();
    const out: Array<{ personId: string; embedding: number[] }> = [];
    for (const d of docs) {
      if (d.faceEmbedding && isFiniteVector(d.faceEmbedding)) {
        out.push({ personId: d.personId, embedding: d.faceEmbedding });
      }
    }
    return out;
  },
});

/** Internal: one public person by stable id (for opener drafting). */
export const getPublicByPersonId = internalQuery({
  args: { personId: v.string() },
  returns: v.union(publicPersonValidator, v.null()),
  handler: async (ctx, args): Promise<PublicPerson | null> => {
    const doc = await ctx.db
      .query("people")
      .withIndex("by_personId", (q) => q.eq("personId", args.personId))
      .unique();
    return doc ? toPublicPerson(doc) : null;
  },
});
