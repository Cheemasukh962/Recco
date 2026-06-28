/**
 * Fixed tag vocabulary and natural-language -> tag mapping.
 *
 * The vocabulary is frozen by docs/API_CONTRACTS.md. Anything the offline voice
 * parser or the OpenAI sanitizer produces is clamped to this set.
 */

/** The only tags allowed anywhere in the system. */
export const TAG_VOCABULARY = [
  "AI",
  "Founder",
  "Infra",
  "Rust",
  "Python",
  "Design",
  "Growth",
  "DevTools",
  "ML",
  "Search",
  "Seed",
  "Backend",
  "Frontend",
  "Product",
  "GoToMarket",
  "Evaluation",
] as const;

export type Tag = (typeof TAG_VOCABULARY)[number];

const TAG_SET = new Set<string>(TAG_VOCABULARY);

/** True if `tag` is part of the frozen vocabulary (case-sensitive canonical). */
export function isValidTag(tag: string): tag is Tag {
  return TAG_SET.has(tag);
}

/**
 * Keep only valid, de-duplicated tags in canonical casing. Accepts loose input
 * (any casing) and maps it back to the canonical vocabulary entry.
 */
export function sanitizeTags(tags: unknown): string[] {
  if (!Array.isArray(tags)) return [];
  const out: string[] = [];
  const seen = new Set<string>();
  for (const raw of tags) {
    if (typeof raw !== "string") continue;
    const canonical = canonicalizeTag(raw);
    if (canonical && !seen.has(canonical)) {
      seen.add(canonical);
      out.push(canonical);
    }
  }
  return out;
}

/** Map a loosely-cased tag string to its canonical vocabulary entry, or null. */
export function canonicalizeTag(raw: string): Tag | null {
  const trimmed = raw.trim();
  if (TAG_SET.has(trimmed)) return trimmed as Tag;
  const lower = trimmed.toLowerCase();
  for (const tag of TAG_VOCABULARY) {
    if (tag.toLowerCase() === lower) return tag;
  }
  return null;
}

/**
 * Natural-language phrase fragments -> canonical tag. Used by the offline voice
 * parser to map spoken words into the vocabulary. Order is not significant; all
 * matching synonyms found in a transcript contribute tags.
 */
export const TAG_SYNONYMS: ReadonlyArray<{ pattern: RegExp; tag: Tag }> = [
  { pattern: /\ba\.?i\.?\b|artificial intelligence/, tag: "AI" },
  { pattern: /\bfounders?\b|\bceos?\b|co-?founders?/, tag: "Founder" },
  { pattern: /\binfra(structure)?\b|\bdevops\b|\bplatform\b|\bsystems?\b/, tag: "Infra" },
  { pattern: /\brust\b|\brustaceans?\b/, tag: "Rust" },
  { pattern: /\bpython\b|\bpy\b/, tag: "Python" },
  { pattern: /\bdesign(ers?|ing)?\b|\bux\b|\bui\b/, tag: "Design" },
  { pattern: /\bgrowth\b|\bmarketing\b|\bacquisition\b/, tag: "Growth" },
  { pattern: /\bdev\s?tools?\b|developer tools?|\btooling\b/, tag: "DevTools" },
  { pattern: /\bml\b|machine learning|\bmodels?\b/, tag: "ML" },
  { pattern: /\bsearch\b|\bretrieval\b|\brag\b|\branking\b/, tag: "Search" },
  { pattern: /\bseed\b|\bpre-?seed\b|early stage/, tag: "Seed" },
  { pattern: /\bback\s?end\b|\bservers?\b|\bapis?\b/, tag: "Backend" },
  { pattern: /\bfront\s?end\b|\bweb\b|\bclient\b/, tag: "Frontend" },
  { pattern: /\bproduct\b|\bpm\b/, tag: "Product" },
  { pattern: /go-?to-?market|\bgtm\b|\bsales\b/, tag: "GoToMarket" },
  { pattern: /\beval(uation|s)?\b|\bbenchmarks?\b/, tag: "Evaluation" },
];

/** Extract canonical tags mentioned in free text, de-duplicated, in vocab order. */
export function extractTags(text: string): Tag[] {
  const lower = text.toLowerCase();
  const found = new Set<Tag>();
  for (const { pattern, tag } of TAG_SYNONYMS) {
    if (pattern.test(lower)) found.add(tag);
  }
  // Return in vocabulary order for deterministic output.
  return TAG_VOCABULARY.filter((t) => found.has(t));
}
