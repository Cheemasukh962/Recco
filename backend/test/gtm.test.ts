import { describe, it, expect } from "vitest";
import {
  parseGTMIntentFallback,
  sanitizeGTMIntent,
  clampCount,
  countFromText,
  extractRoles,
  buildSearchQuery,
  gtmLabel,
} from "../convex/lib/gtmIntent.js";
import {
  scoreProspect,
  prospectOutreach,
  mockProspects,
  fiberToProspect,
  type ProspectInput,
} from "../convex/lib/gtmProspects.js";
import {
  parseGTMRunRequest,
  parseGTMStatusRequest,
  parseGTMOutreachRequest,
  HttpError,
} from "../convex/lib/http.js";

const NOW = 1_000;

function prospect(p: Partial<ProspectInput>): ProspectInput {
  return {
    prospectId: "gp_x",
    name: "Test Person",
    headline: null,
    role: null,
    company: null,
    location: null,
    linkedinUrl: null,
    email: null,
    profilePhotoUrl: null,
    source: "mock",
    matchScore: 0.5,
    ...p,
  };
}

// ---------------------------------------------------------------------------
// Intent parsing
// ---------------------------------------------------------------------------

describe("parseGTMIntentFallback", () => {
  it("'hire a Swift engineer' -> hiring with swift engineer role", () => {
    const i = parseGTMIntentFallback("I want to hire a Swift engineer", undefined, NOW);
    expect(i.goalType).toBe("hiring");
    expect(i.targetRoles).toContain("swift engineer");
    expect(i.count).toBe(8);
    expect(i.searchQuery.toLowerCase()).toContain("swift engineer");
  });

  it("'find investors for my AI infra startup' -> fundraising + ai/infra", () => {
    const i = parseGTMIntentFallback("Find me investors for my AI infra startup", undefined, NOW);
    expect(i.goalType).toBe("fundraising");
    expect(i.targetRoles).toContain("investor");
    expect(i.targetIndustries).toEqual(expect.arrayContaining(["ai", "infra"]));
  });

  it("'find startup founders' -> founders", () => {
    expect(parseGTMIntentFallback("Find startup founders who might need Recco", undefined, NOW).goalType).toBe("founders");
  });

  it("'8 people for sponsorships' -> sponsors, count 8 from text", () => {
    const i = parseGTMIntentFallback("Find 8 people I should talk to for sponsorships", undefined, NOW);
    expect(i.goalType).toBe("sponsors");
    expect(i.count).toBe(8);
  });

  it("clamps count + reads count from text", () => {
    expect(clampCount(99)).toBe(12);
    expect(clampCount(0)).toBe(3);
    expect(clampCount(undefined)).toBe(8);
    expect(countFromText("find 5 founders")).toBe(5);
    expect(countFromText("find founders")).toBeNull();
  });

  it("extractRoles handles modifiers + singularizes", () => {
    expect(extractRoles("hire swift engineers and ml researchers")).toEqual(
      expect.arrayContaining(["swift engineer", "ml researcher"]),
    );
  });

  it("buildSearchQuery + gtmLabel produce readable strings", () => {
    const i = parseGTMIntentFallback("find investors", undefined, NOW);
    expect(buildSearchQuery(i)).toMatch(/Find/i);
    expect(gtmLabel(i)).toContain("Fundraising");
  });

  it("sanitizeGTMIntent fills from fallback on partial/garbage", () => {
    const i = sanitizeGTMIntent({ goalType: "sponsors" }, "find sponsors", 8, NOW);
    expect(i.goalType).toBe("sponsors");
    expect(i.searchQuery.length).toBeGreaterThan(0);
    expect(sanitizeGTMIntent(42, "hire a swift engineer", undefined, NOW).goalType).toBe("hiring");
  });
});

// ---------------------------------------------------------------------------
// Prospect scoring
// ---------------------------------------------------------------------------

describe("scoreProspect", () => {
  it("fundraising: an investor with contact is a hot prospect", () => {
    const intent = parseGTMIntentFallback("find investors", undefined, NOW);
    const s = scoreProspect(
      prospect({
        name: "Ada Vc",
        role: "Investor",
        headline: "Partner at Sequoia",
        company: "Sequoia",
        linkedinUrl: "https://linkedin.com/in/ada",
        email: "ada@sequoia.com",
      }),
      intent,
      NOW,
    );
    expect(s.priority).toBe("hot");
    expect(s.reasons.join(" ")).toContain("investor mission");
  });

  it("hiring: a matching engineer reads as a real reason", () => {
    const intent = parseGTMIntentFallback("hire a swift engineer", undefined, NOW);
    const s = scoreProspect(
      prospect({ name: "Eng One", role: "Swift Engineer", headline: "Swift Engineer at Atlas", company: "Atlas", linkedinUrl: "https://linkedin.com/in/eng" }),
      intent,
      NOW,
    );
    expect(["hot", "warm", "cold"]).toContain(s.priority);
    expect(s.reasons.join(" ")).toContain("Matches requested role: swift engineer");
  });

  it("no contact + no match -> needs_info", () => {
    const intent = parseGTMIntentFallback("find investors", undefined, NOW);
    const s = scoreProspect(prospect({ name: "Nobody", role: "Student" }), intent, NOW);
    expect(s.priority).toBe("needs_info");
    expect(s.missingInfo).toContain("No contact link found");
  });
});

describe("prospectOutreach", () => {
  it("drafts a mission-aware, non-empty outreach", () => {
    const intent = parseGTMIntentFallback("find investors", undefined, NOW);
    const d = prospectOutreach(prospect({ name: "Ada Vc", company: "Sequoia" }), intent, NOW);
    expect(d.linkedinDm).toContain("Ada");
    expect(d.linkedinDm.toLowerCase()).toContain("investor");
    expect(d.coldEmailSubject.length).toBeGreaterThan(0);
  });
});

// ---------------------------------------------------------------------------
// Mock Fiber fallback
// ---------------------------------------------------------------------------

describe("mockProspects (no-Fiber fallback)", () => {
  it("returns the requested count, shaped by the intent", () => {
    const intent = parseGTMIntentFallback("hire a swift engineer", 8, NOW);
    const ps = mockProspects(intent, 8, NOW);
    expect(ps).toHaveLength(8);
    expect(ps[0]?.role?.toLowerCase()).toContain("swift engineer");
    expect(ps.every((p) => p.source === "mock")).toBe(true);
  });

  it("produces a real priority spread when scored", () => {
    const intent = parseGTMIntentFallback("find investors", 8, NOW);
    const priorities = new Set(mockProspects(intent, 8, NOW).map((p) => scoreProspect(p, intent, NOW).priority));
    expect(priorities.size).toBeGreaterThanOrEqual(2);
  });

  it("fiberToProspect maps a candidate cleanly", () => {
    const p = fiberToProspect({
      candidateId: "cand_1",
      fullName: "Grace Liu",
      headline: "Founder at Vela",
      role: "Founder",
      company: "Vela",
      school: null,
      location: "SF",
      linkedinUrl: "https://linkedin.com/in/grace",
      email: null,
      profilePhotoUrl: null,
      source: "fiber:nlp-search",
      matchScore: 0.7,
    });
    expect(p.name).toBe("Grace Liu");
    expect(p.source).toBe("fiber");
    expect(p.linkedinUrl).toContain("linkedin");
    expect(p.prospectId.startsWith("gp_")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// HTTP parse validation + fake-send status payload
// ---------------------------------------------------------------------------

describe("gtm http parsers", () => {
  it("parseGTMRunRequest requires clientId + transcript", () => {
    expect(() => parseGTMRunRequest({ clientId: "c1" })).toThrow(HttpError);
    expect(() => parseGTMRunRequest({ transcript: "find investors" })).toThrow(HttpError);
    const ok = parseGTMRunRequest({ clientId: "c1", transcript: "find investors", count: 6 });
    expect(ok).toEqual({ clientId: "c1", transcript: "find investors", count: 6 });
  });

  it("parseGTMOutreachRequest requires id", () => {
    expect(() => parseGTMOutreachRequest({})).toThrow(HttpError);
    expect(parseGTMOutreachRequest({ id: "p1", senderName: "Pranav" })).toEqual({
      id: "p1",
      senderName: "Pranav",
    });
  });

  it("parseGTMStatusRequest validates status + channel and parses fake-sent payload", () => {
    expect(() => parseGTMStatusRequest({ id: "p1", status: "bogus" })).toThrow(HttpError);
    expect(() => parseGTMStatusRequest({ id: "p1", status: "sent", channel: "pigeon" })).toThrow(HttpError);
    const sent = parseGTMStatusRequest({
      id: "p1",
      status: "sent",
      channel: "cold_email",
      sentAt: 42,
      editedOutreach: {
        linkedinDm: "hi",
        coldEmailSubject: "s",
        coldEmail: "b",
        inPersonOpener: "o",
        generatedAt: 1,
      },
    });
    expect(sent.status).toBe("sent");
    expect(sent.channel).toBe("cold_email");
    expect(sent.sentAt).toBe(42);
    expect(sent.editedOutreach?.coldEmail).toBe("b");
  });
});
