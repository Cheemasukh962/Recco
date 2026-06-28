/**
 * Pure helpers for the Brain scan-memory layer.
 *
 * Framework-free (no Convex imports) so they can be unit-tested with plain
 * Node/Vitest. The Convex `scanMemories.ts` functions wire these to the db; the
 * HTTP bridge validates input and calls those functions.
 *
 * A "scan memory" is durable metadata about a person the user resolved from the
 * camera. We persist extracted text + links + scores only — NEVER raw face or
 * badge images (mirroring the `identityLookups` privacy stance).
 */

/** User-facing confidence buckets for a saved scan. */
export type ScanConfidence =
  | "verified"
  | "possible"
  | "needs_confirmation"
  | "unknown";

/** What the iOS app posts after an identity resolve (text/links/scores only). */
export type ScanMemoryUpsertInput = {
  scanId: string;
  /** Raw IdentityResolveStatus: verified | possible | not_found | needs_clarification | error. */
  status: string;
  name?: string | null;
  headline?: string | null;
  role?: string | null;
  company?: string | null;
  school?: string | null;
  linkedinUrl?: string | null;
  email?: string | null;
  confidenceScore?: number | null;
  personId?: string | null;
  transcript?: string | null;
  badgeText?: string | null;
  hadFaceVerification?: boolean;
  candidateCount?: number;
};

/** The stored, persisted fields (minus Convex `_id`, `notes`, `outreach`). */
export type ScanMemoryFields = {
  scanId: string;
  personId: string | null;
  name: string | null;
  headline: string | null;
  role: string | null;
  company: string | null;
  school: string | null;
  linkedinUrl: string | null;
  email: string | null;
  confidence: ScanConfidence;
  confidenceScore: number | null;
  sources: string[];
  badgeText: string | null;
  linkedinKey: string | null;
  nameCompanyKey: string | null;
  firstScannedAt: number;
  lastScannedAt: number;
  scanCount: number;
};

/** Map a raw identity status to a saved confidence bucket. */
export function confidenceFromStatus(status: string): ScanConfidence {
  switch (status) {
    case "verified":
      return "verified";
    case "possible":
      return "possible";
    case "needs_clarification":
      return "needs_confirmation";
    default:
      // not_found / error / anything unexpected
      return "unknown";
  }
}

/**
 * Normalize a LinkedIn URL to a stable dedup key: drop scheme, `www.`, query,
 * fragment and trailing slashes; lowercase. `linkedin.com/in/ava-shah` is the
 * resulting shape. Returns null for empty/garbage input.
 */
export function normalizeLinkedIn(url?: string | null): string | null {
  if (!url) return null;
  let s = url.trim().toLowerCase();
  if (!s) return null;
  s = s.replace(/^https?:\/\//, "").replace(/^www\./, "");
  s = s.split(/[?#]/)[0] ?? s;
  s = s.replace(/\/+$/, "");
  return s.length > 0 ? s : null;
}

/** A normalized lowercase `name|company` (or just `name`) dedup key. */
export function nameCompanyKey(
  name?: string | null,
  company?: string | null,
): string | null {
  const n = (name ?? "").trim().toLowerCase().replace(/\s+/g, " ");
  if (!n) return null;
  const c = (company ?? "").trim().toLowerCase().replace(/\s+/g, " ");
  return c ? `${n}|${c}` : n;
}

/** Derive the contributing source tags from a resolve payload. */
export function deriveSources(input: ScanMemoryUpsertInput): string[] {
  const out: string[] = [];
  if (input.badgeText && input.badgeText.trim()) out.push("badge");
  if (input.candidateCount && input.candidateCount > 0) out.push("fiber");
  if (input.hadFaceVerification) out.push("face");
  if (input.transcript && input.transcript.trim()) out.push("voice");
  if (input.personId) out.push("roster");
  return out;
}

/**
 * Whether a resolve carries enough signal to be worth saving. We keep verified
 * and possible results, anything with a candidate, and anything where we at
 * least read a name — and skip pure errors / empty `needs_clarification` so the
 * Brain doesn't fill with noise.
 */
export function isWorthSaving(input: ScanMemoryUpsertInput): boolean {
  const hasName = !!(input.name && input.name.trim());
  const hasCandidate = (input.candidateCount ?? 0) > 0;
  if (input.status === "verified" || input.status === "possible") return true;
  return hasName || hasCandidate;
}

/** Trim a string to null when empty/whitespace. */
function clean(s?: string | null): string | null {
  if (s == null) return null;
  const t = s.trim();
  return t.length > 0 ? t : null;
}

/** Prefer a fresh non-empty value, otherwise keep the existing one. */
function prefer(next: string | null, existing: string | null | undefined): string | null {
  return next ?? existing ?? null;
}

/**
 * Merge an upsert input with an existing memory (or null for a new one) into the
 * full stored field set. Existing non-empty values are preserved when the new
 * scan omits them; sources accumulate; scanCount/lastScannedAt advance.
 */
export function mergeMemory(
  existing: ScanMemoryFields | null,
  input: ScanMemoryUpsertInput,
  now: number,
): ScanMemoryFields {
  const name = clean(input.name);
  const company = clean(input.company);
  const linkedinUrl = clean(input.linkedinUrl);

  const mergedName = prefer(name, existing?.name);
  const mergedCompany = prefer(company, existing?.company);
  const mergedLinkedin = prefer(linkedinUrl, existing?.linkedinUrl);

  const sources = Array.from(
    new Set([...(existing?.sources ?? []), ...deriveSources(input)]),
  );

  return {
    scanId: input.scanId,
    personId: prefer(clean(input.personId), existing?.personId),
    name: mergedName,
    headline: prefer(clean(input.headline), existing?.headline),
    role: prefer(clean(input.role), existing?.role),
    company: mergedCompany,
    school: prefer(clean(input.school), existing?.school),
    linkedinUrl: mergedLinkedin,
    email: prefer(clean(input.email), existing?.email),
    confidence: confidenceFromStatus(input.status),
    confidenceScore:
      typeof input.confidenceScore === "number"
        ? input.confidenceScore
        : existing?.confidenceScore ?? null,
    sources,
    badgeText: prefer(clean(input.badgeText), existing?.badgeText),
    linkedinKey: normalizeLinkedIn(mergedLinkedin),
    nameCompanyKey: nameCompanyKey(mergedName, mergedCompany),
    firstScannedAt: existing?.firstScannedAt ?? now,
    lastScannedAt: now,
    scanCount: (existing?.scanCount ?? 0) + 1,
  };
}
