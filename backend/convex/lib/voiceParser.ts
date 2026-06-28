/**
 * Offline, deterministic voice-command parsing + command sanitization.
 *
 * `parseCommandOffline` is the no-API fallback for voice:interpretCommand. It
 * reliably handles the five frozen demo phrases and degrades gracefully on
 * anything else. `sanitizeFilterCommand` clamps an arbitrary object (e.g. the
 * JSON an LLM returned) into a valid FilterCommand.
 *
 * Both are framework-free and unit-tested.
 */

import type { FilterCommand } from "./types.js";
import { extractTags, sanitizeTags } from "./tags.js";

/** Minimal roster info needed to resolve names -> person ids. */
export type RosterEntry = { id: string; name: string };

const RESET_RE = /\b(reset|clear|start over|show everyone|show all|deselect|never\s?mind)\b/i;
const DRAFT_RE = /\b(draft|opener|write|compose|intro(?:duction)?|email|message)\b/i;
const RANK_RE =
  /\bwho\s+(should|do|can|would|to)\b|who'?s worth|recommend|talk to|worth talking|best person|prioriti[sz]e/i;
const EXCLUDE_RE = /\b(?:without|except|excluding|other than|no longer|not)\b\s+([a-z .]+)/i;

/** Resolve a person id from a transcript by matching first or full names. */
export function resolveTargetPerson(transcript: string, roster: RosterEntry[]): string | null {
  const lower = transcript.toLowerCase();
  // Prefer a full-name match, then a first-name match.
  for (const p of roster) {
    if (lower.includes(p.name.toLowerCase())) return p.id;
  }
  for (const p of roster) {
    const first = p.name.split(/\s+/)[0]?.toLowerCase();
    if (first && new RegExp(`\\b${escapeRegex(first)}\\b`).test(lower)) return p.id;
  }
  return null;
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Pick a rankBy value from the include tags / transcript. */
function deriveRankBy(includeTags: string[]): FilterCommand["rankBy"] {
  if (includeTags.includes("Infra")) return "infra";
  if (includeTags.includes("Growth") || includeTags.includes("GoToMarket")) return "growth";
  if (includeTags.includes("AI") || includeTags.includes("ML")) return "ai";
  if (includeTags.includes("Founder")) return "founder";
  return "relevance";
}

/**
 * Parse a transcript into a FilterCommand using only local rules.
 * `roster` is optional but required to resolve a draft target by name.
 */
export function parseCommandOffline(
  transcript: string,
  roster: RosterEntry[] = [],
): FilterCommand {
  const rawText = transcript.trim();

  // 1. Reset wins outright.
  if (RESET_RE.test(rawText)) {
    return {
      action: "reset",
      includeTags: [],
      excludeTags: [],
      rankBy: null,
      targetPersonId: null,
      rawText,
    };
  }

  // 2. Pull include/exclude tags out of the text.
  let excludeTags: string[] = [];
  const excludeMatch = rawText.match(EXCLUDE_RE);
  if (excludeMatch && excludeMatch[1]) {
    excludeTags = extractTags(excludeMatch[1]);
  }
  let includeTags = extractTags(rawText).filter((t) => !excludeTags.includes(t));

  // 3. Draft?
  if (DRAFT_RE.test(rawText)) {
    const targetPersonId = resolveTargetPerson(rawText, roster);
    return {
      action: "draft",
      includeTags,
      excludeTags,
      rankBy: null,
      targetPersonId,
      rawText,
    };
  }

  // 4. Rank ("who should I talk to about ...")?
  if (RANK_RE.test(rawText)) {
    return {
      action: "rank",
      includeTags,
      excludeTags,
      rankBy: deriveRankBy(includeTags),
      targetPersonId: null,
      rawText,
    };
  }

  // 5. Default: filter.
  return {
    action: "filter",
    includeTags,
    excludeTags,
    rankBy: includeTags.length > 0 ? "relevance" : null,
    targetPersonId: null,
    rawText,
  };
}

const VALID_ACTIONS = new Set(["filter", "rank", "reset", "draft"]);
const VALID_RANKBY = new Set(["relevance", "infra", "growth", "ai", "founder"]);

/**
 * Clamp an arbitrary object into a valid FilterCommand. Used to sanitize JSON
 * returned by an LLM so a malformed model response can never break the contract.
 * `fallbackRawText` is used when the object omits rawText.
 */
export function sanitizeFilterCommand(input: unknown, fallbackRawText: string): FilterCommand {
  const obj = (input && typeof input === "object" ? input : {}) as Record<string, unknown>;

  const action = typeof obj.action === "string" && VALID_ACTIONS.has(obj.action)
    ? (obj.action as FilterCommand["action"])
    : "filter";

  const includeTags = sanitizeTags(obj.includeTags);
  const excludeTags = sanitizeTags(obj.excludeTags).filter((t) => !includeTags.includes(t));

  let rankBy: FilterCommand["rankBy"] = null;
  if (typeof obj.rankBy === "string" && VALID_RANKBY.has(obj.rankBy)) {
    rankBy = obj.rankBy as FilterCommand["rankBy"];
  }

  const targetPersonId =
    typeof obj.targetPersonId === "string" && obj.targetPersonId.length > 0
      ? obj.targetPersonId
      : null;

  const rawText =
    typeof obj.rawText === "string" && obj.rawText.length > 0 ? obj.rawText : fallbackRawText;

  return { action, includeTags, excludeTags, rankBy, targetPersonId, rawText };
}
