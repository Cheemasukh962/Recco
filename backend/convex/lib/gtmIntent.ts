/**
 * "Lazy GTM / Scout Mode" intent parsing — pure, deterministic.
 *
 * Turns a spoken/typed request ("find me investors for my AI infra startup")
 * into a structured `GTMIntent` the Fiber search + lead scorer can use. Builds on
 * the mission parser (`lib/mission.ts`) for goal/keyword/industry detection and
 * adds role extraction, a natural-language search query, and a prospect count.
 * The Convex action tries OpenAI first and always falls back here.
 */

import {
  parseMissionFallback,
  detectIndustries,
  type GoalType,
  type PreferredAction,
} from "./mission.js";

/** GTM goal subset (the user is searching for *other* people). */
export type GTMGoalType =
  | "hiring"
  | "fundraising"
  | "customers"
  | "sponsors"
  | "founders"
  | "networking"
  | "other";

export type GTMIntent = {
  rawText: string;
  goalType: GTMGoalType;
  searchQuery: string;
  targetRoles: string[];
  targetKeywords: string[];
  targetCompanies: string[];
  targetIndustries: string[];
  count: number;
  preferredAction: PreferredAction;
};

export const DEFAULT_GTM_COUNT = 8;
const MIN_COUNT = 3;
const MAX_COUNT = 12;

const GTM_GOALS: ReadonlySet<string> = new Set([
  "hiring",
  "fundraising",
  "customers",
  "sponsors",
  "founders",
  "networking",
  "other",
]);

const ACTIONS: ReadonlySet<string> = new Set([
  "linkedin_dm",
  "cold_email",
  "in_person",
  "reminder",
]);

/** Clamp a requested prospect count into a sane range. */
export function clampCount(value: unknown, fallback = DEFAULT_GTM_COUNT): number {
  const n = typeof value === "number" && Number.isFinite(value) ? Math.round(value) : fallback;
  return Math.max(MIN_COUNT, Math.min(MAX_COUNT, n));
}

/** Pull an explicit number out of the text ("find 8 people") if present. */
export function countFromText(text: string): number | null {
  const m = text.match(/\b(\d{1,2})\b/);
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isFinite(n) ? n : null;
}

/** Map the broader mission goal onto the GTM goal subset. */
function mapGoal(goal: GoalType): GTMGoalType {
  switch (goal) {
    case "fundraising":
      return "fundraising";
    case "hiring":
    case "get_hired":
      return "hiring";
    case "customers":
      return "customers";
    case "sponsors":
      return "sponsors";
    case "cofounder":
    case "founders":
      return "founders";
    case "networking":
      return "networking";
    default:
      return "other";
  }
}

const ROLE_RE =
  /\b((?:senior|staff|lead|principal|junior|swift|ios|android|backend|front[\s-]?end|full[\s-]?stack|ml|ai|infra|infrastructure|growth|product|platform|data|devrel|startup|technical|early[\s-]?stage)\s+)?(engineers?|developers?|designers?|founders?|recruiters?|investors?|partners?|marketers?|managers?|operators?|scientists?|researchers?|ctos?|ceos?|pms?|advisors?)\b/gi;

/** Extract role phrases ("swift engineer", "investors") and singularize them. */
export function extractRoles(text: string): string[] {
  const out: string[] = [];
  for (const m of text.matchAll(ROLE_RE)) {
    const phrase = `${m[1] ?? ""}${m[2] ?? ""}`.replace(/\s+/g, " ").trim().toLowerCase();
    if (phrase) out.push(phrase.replace(/s$/, "")); // crude singular
  }
  return Array.from(new Set(out));
}

function uniq(items: string[]): string[] {
  return Array.from(new Set(items.filter((s) => s && s.trim()).map((s) => s.trim().toLowerCase())));
}

/** Build a concise natural-language query for Fiber's nlp-search. */
export function buildSearchQuery(intent: Omit<GTMIntent, "searchQuery">): string {
  const roles = intent.targetRoles.slice(0, 3);
  const industries = intent.targetIndustries.slice(0, 2);
  if (roles.length) {
    let q = `Find ${roles.join(" / ")}`;
    if (industries.length) q += ` in ${industries.join(" / ")}`;
    return q;
  }
  if (industries.length) return `Find people in ${industries.join(" / ")}`;
  const raw = intent.rawText.trim();
  return raw ? raw : "Find relevant people to connect with at the event";
}

/** Deterministic fallback parser (never throws). */
export function parseGTMIntentFallback(
  rawText: string,
  count: number | undefined,
  now: number,
): GTMIntent {
  const text = (rawText ?? "").trim();
  const mission = parseMissionFallback(text, now);
  const goalType = mapGoal(mission.goalType);
  const extracted = extractRoles(text);
  const targetRoles = extracted.length ? extracted : uniq(mission.targetRoles);
  const industries = detectIndustries(text.toLowerCase());
  const resolvedCount = clampCount(count ?? countFromText(text) ?? DEFAULT_GTM_COUNT);

  const base: Omit<GTMIntent, "searchQuery"> = {
    rawText: text || "Find relevant people",
    goalType,
    targetRoles,
    targetKeywords: uniq([...mission.targetKeywords, ...industries]),
    targetCompanies: [],
    targetIndustries: industries,
    count: resolvedCount,
    preferredAction: mission.preferredAction,
  };
  return { ...base, searchQuery: buildSearchQuery(base) };
}

function strArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return uniq(value.filter((x): x is string => typeof x === "string"));
}

/** Validate/normalize an LLM intent object, filling gaps from the fallback. */
export function sanitizeGTMIntent(
  input: unknown,
  rawText: string,
  count: number | undefined,
  now: number,
): GTMIntent {
  const fallback = parseGTMIntentFallback(rawText, count, now);
  if (!input || typeof input !== "object") return fallback;
  const obj = input as Record<string, unknown>;

  const goalType =
    typeof obj.goalType === "string" && GTM_GOALS.has(obj.goalType)
      ? (obj.goalType as GTMGoalType)
      : fallback.goalType;
  const preferredAction =
    typeof obj.preferredAction === "string" && ACTIONS.has(obj.preferredAction)
      ? (obj.preferredAction as PreferredAction)
      : fallback.preferredAction;

  const roles = strArray(obj.targetRoles);
  const resolved: Omit<GTMIntent, "searchQuery"> = {
    rawText: (typeof obj.rawText === "string" && obj.rawText.trim()) || fallback.rawText,
    goalType,
    targetRoles: roles.length ? roles : fallback.targetRoles,
    targetKeywords: strArray(obj.targetKeywords).length ? strArray(obj.targetKeywords) : fallback.targetKeywords,
    targetCompanies: strArray(obj.targetCompanies),
    targetIndustries: strArray(obj.targetIndustries).length ? strArray(obj.targetIndustries) : fallback.targetIndustries,
    count: clampCount(typeof obj.count === "number" ? obj.count : count ?? fallback.count),
    preferredAction,
  };
  const searchQuery =
    typeof obj.searchQuery === "string" && obj.searchQuery.trim()
      ? obj.searchQuery.trim()
      : buildSearchQuery(resolved);
  return { ...resolved, searchQuery };
}

/** Short human label ("Hiring · swift engineer"). */
export function gtmLabel(intent: Pick<GTMIntent, "goalType" | "targetRoles" | "rawText">): string {
  const goal = intent.goalType.charAt(0).toUpperCase() + intent.goalType.slice(1);
  const role = intent.targetRoles[0];
  if (role) return `${goal} · ${role}`;
  return goal === "Other" ? intent.rawText.slice(0, 28) : goal;
}
