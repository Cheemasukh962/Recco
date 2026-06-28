/**
 * Offline, templated opener generation (the no-API fallback for
 * drafts:createOpener). Produces a short, human, person-specific opener using
 * only the data we already store — no fake claims, no external calls.
 *
 * Framework-free; the real OpenAI path lives in the Convex action and falls
 * back here whenever a key is missing or the call fails.
 */

import type { DraftResult, Person } from "./types.js";

function firstName(name: string): string {
  return name.split(/\s+/)[0] || name;
}

/** Lowercase the first letter and strip a trailing period from a sentence. */
function asClause(sentence: string): string {
  const trimmed = sentence.trim().replace(/[.!]+$/, "");
  if (!trimmed) return "";
  return trimmed.charAt(0).toLowerCase() + trimmed.slice(1);
}

/** Turn an "Ask about X" seed into a first-person curiosity line. */
function seedToQuestion(openerSeed: string | undefined): string | null {
  if (!openerSeed) return null;
  const seed = openerSeed.trim();
  const m = seed.match(/^ask\s+(.*)$/i);
  const body = m ? m[1] : seed;
  const clause = body.replace(/[.!]+$/, "");
  if (!clause) return null;
  return `I'm curious ${clause}.`;
}

/** A short topic noun phrase for the subject line, derived from tags/bio. */
export function topicForPerson(person: Person): string {
  const tags = new Set(person.tags);
  if (tags.has("Infra") && tags.has("AI")) return "AI infra";
  if (tags.has("Infra")) return "infra";
  if (tags.has("Search") || tags.has("Evaluation")) return "retrieval & evals";
  if (tags.has("Growth") || tags.has("GoToMarket")) return "early growth";
  if (tags.has("Design")) return "AI product design";
  if (tags.has("Rust")) return "Rust tooling";
  if (tags.has("AI") || tags.has("ML")) return "your AI work";
  if (tags.has("Founder")) return "what you're building";
  return person.company ? `${person.company}` : "your work";
}

/**
 * Build a templated DraftResult for a person. `now` is injected for
 * deterministic testing; `userGoal` optionally personalizes the ask.
 */
export function buildOpenerOffline(
  person: Person,
  userGoal: string | null,
  now: number,
): DraftResult {
  const fn = firstName(person.name);
  const topic = topicForPerson(person);
  const bioClause = asClause(person.bio);

  const question =
    seedToQuestion(person.openerSeed) ??
    `I'd love to hear what's been the most interesting part of working on ${topic}.`;

  const goalClause = userGoal && userGoal.trim()
    ? ` I'm currently focused on ${asClause(userGoal)}, so your perspective would be especially helpful.`
    : "";

  // "Building infra..." reads as "you're building infra..."; a noun-led bio
  // ("Systems engineer...") reads better introduced directly.
  const bioStartsGerund = /^[a-z]+ing\b/.test(bioClause);
  const lead = !bioClause
    ? `I saw your work at ${person.company}.`
    : bioStartsGerund
      ? `I saw you're ${bioClause}.`
      : `I saw your work — ${person.bio.trim()}`;

  const opener = `Hey ${fn}, ${lead} ${question}${goalClause}`.replace(/\s+/g, " ").trim();

  const email =
    `Hey ${fn},\n\n` +
    `${lead} ${question}${goalClause}\n\n` +
    `Would love to compare notes for a minute at the hackathon.`;

  return {
    personId: person.id,
    subject: `Quick question on ${topic}`,
    opener,
    email,
    generatedAt: now,
  };
}

/** Validate/normalize an LLM draft object into a DraftResult (no fake fields). */
export function sanitizeDraft(
  input: unknown,
  person: Person,
  now: number,
): DraftResult | null {
  if (!input || typeof input !== "object") return null;
  const obj = input as Record<string, unknown>;
  const opener = typeof obj.opener === "string" ? obj.opener.trim() : "";
  if (!opener) return null;
  const subject = typeof obj.subject === "string" && obj.subject.trim() ? obj.subject.trim() : null;
  const email = typeof obj.email === "string" && obj.email.trim() ? obj.email.trim() : null;
  return {
    personId: person.id,
    subject,
    opener,
    email,
    generatedAt: now,
  };
}
