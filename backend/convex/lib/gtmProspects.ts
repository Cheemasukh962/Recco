/**
 * Scout-mode prospect helpers — pure, framework-free, deterministic.
 *
 * Scores Fiber/mock prospects against a GTM intent (reusing the mission lead
 * scorer), drafts initial outreach (reusing the offline outreach builder), and
 * generates deterministic mock prospects so Scout Mode is demoable with no Fiber
 * key. Scout prospects are NEVER scan memories — they live in their own tables.
 */

import { scoreLead, type LeadPriority } from "./leadScoring.js";
import { buildOutreachOffline, type OutreachDraft } from "./outreach.js";
import type { GTMIntent } from "./gtmIntent.js";
import type { MissionProfile } from "./mission.js";
import type { IdentityCandidate } from "./types.js";

/** A prospect before scoring/persistence (Fiber- or mock-sourced). */
export type ProspectInput = {
  prospectId: string;
  name: string;
  headline: string | null;
  role: string | null;
  company: string | null;
  location: string | null;
  linkedinUrl: string | null;
  email: string | null;
  profilePhotoUrl: string | null;
  source: "fiber" | "mock" | "manual";
  matchScore: number;
};

export type ProspectScore = {
  priority: LeadPriority;
  score: number;
  reasons: string[];
  missingInfo: string[];
};

function slug(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 32);
}

/** Bridge a GTM intent into the MissionProfile the lead scorer consumes. */
function intentAsMission(intent: GTMIntent, now: number): MissionProfile {
  return {
    rawText: intent.rawText,
    goalType: intent.goalType, // GTM goal ⊂ mission GoalType
    targetRoles: intent.targetRoles,
    targetKeywords: intent.targetKeywords,
    targetCompanies: intent.targetCompanies,
    targetIndustries: intent.targetIndustries,
    preferredAction: intent.preferredAction,
    userContext: null,
    tone: "warm, concise",
    createdAt: now,
    updatedAt: now,
  };
}

/** Score one prospect against the intent (deterministic, reuses scoreLead). */
export function scoreProspect(p: ProspectInput, intent: GTMIntent, now: number): ProspectScore {
  const mission = intentAsMission(intent, now);
  const ls = scoreLead(
    {
      name: p.name,
      headline: p.headline,
      role: p.role,
      company: p.company,
      school: null,
      linkedinUrl: p.linkedinUrl,
      email: p.email,
      confidence: "possible", // Fiber/mock found — never face-verified
      notes: null,
      badgeText: null,
      transcript: null,
      scanCount: 1,
      sources: [p.source],
    },
    mission,
    now,
  );
  // Friendlier scout wording.
  const reasons = ls.reasons.map((r) =>
    r.replace("Matches target role:", "Matches requested role:").replace("Possible identity", "Found via search"),
  );
  return { priority: ls.priority, score: ls.score, reasons, missingInfo: ls.missingInfo };
}

/** Initial offline outreach for a prospect (mission-aware, deterministic). */
export function prospectOutreach(p: ProspectInput, intent: GTMIntent, now: number): OutreachDraft {
  return buildOutreachOffline(
    {
      name: p.name,
      role: p.role,
      company: p.company,
      headline: p.headline,
      eventName: null,
      senderName: null,
      goalType: intent.goalType,
    },
    now,
  );
}

/** Map a Fiber candidate into a prospect. */
export function fiberToProspect(c: IdentityCandidate): ProspectInput {
  return {
    prospectId: `gp_${slug(c.fullName)}_${slug(c.candidateId)}`.slice(0, 60),
    name: c.fullName,
    headline: c.headline ?? null,
    role: c.role ?? null,
    company: c.company ?? null,
    location: c.location ?? null,
    linkedinUrl: c.linkedinUrl ?? null,
    email: c.email ?? null,
    profilePhotoUrl: c.profilePhotoUrl ?? null,
    source: "fiber",
    matchScore: c.matchScore ?? 0,
  };
}

// --- Mock prospects (offline / no-Fiber fallback) ---------------------------

const NAME_POOL = [
  "Ava Shah", "Miles Carter", "Sam Rivera", "Priya Patel", "Diego Santos",
  "Lena Fischer", "Noah Kim", "Zoe Bennett", "Omar Haddad", "Grace Liu",
  "Ethan Brooks", "Maya Singh",
];
const COMPANY_POOL = [
  "Northwind", "Vela Labs", "Brightseed", "Orbital", "Lumen AI", "Foundry",
  "Atlas", "Kestrel", "Harbor", "Meridian", "Drift", "Cobalt",
];
const LOCATION_POOL = ["SF", "NYC", "London", "Berlin", "Toronto", "Austin"];

function titleCase(s: string): string {
  return s.replace(/\b[a-z]/g, (c) => c.toUpperCase());
}

/** A default role per goal when the request didn't name one. */
function goalDefaultRole(goal: GTMIntent["goalType"]): string {
  switch (goal) {
    case "hiring": return "engineer";
    case "fundraising": return "investor";
    case "customers": return "head of product";
    case "sponsors": return "head of partnerships";
    case "founders": return "founder";
    default: return "operator";
  }
}

/**
 * Deterministic mock prospects shaped by the intent. Contact richness is varied
 * by index so scoring yields a real hot/warm/cold/needs-info spread.
 */
export function mockProspects(intent: GTMIntent, count: number, now: number): ProspectInput[] {
  const roles = intent.targetRoles.length ? intent.targetRoles : [goalDefaultRole(intent.goalType)];
  const out: ProspectInput[] = [];
  for (let i = 0; i < count; i++) {
    const name = NAME_POOL[i % NAME_POOL.length];
    const role = titleCase(roles[i % roles.length]);
    const company = COMPANY_POOL[i % COMPANY_POOL.length];
    const hasLinkedIn = i % 4 !== 3; // ~75%
    const hasEmail = i % 5 < 2; // ~40%
    const linkedinUrl = hasLinkedIn
      ? `https://www.linkedin.com/in/${slug(name)}-${i}`
      : null;
    const email = hasEmail
      ? `${name.split(" ")[0]?.toLowerCase()}@${company.toLowerCase().replace(/[^a-z]/g, "")}.com`
      : null;
    out.push({
      prospectId: `gp_mock_${i}_${slug(name)}`,
      name,
      headline: `${role} at ${company}`,
      role,
      company,
      location: LOCATION_POOL[i % LOCATION_POOL.length],
      linkedinUrl,
      email,
      profilePhotoUrl: null,
      source: "mock",
      matchScore: Math.max(0.4, 0.95 - i * 0.05),
    });
  }
  return out;
}
