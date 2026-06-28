import { describe, it, expect } from "vitest";
import {
  confidenceFromStatus,
  normalizeLinkedIn,
  nameCompanyKey,
  deriveSources,
  isWorthSaving,
  mergeMemory,
  type ScanMemoryUpsertInput,
} from "../convex/lib/scanMemory.js";
import {
  firstNameOf,
  topicOf,
  buildOutreachOffline,
  sanitizeOutreach,
} from "../convex/lib/outreach.js";
import {
  parseScanMemoryUpsertRequest,
  parseUpdateNotesRequest,
  parseGenerateOutreachRequest,
  HttpError,
} from "../convex/lib/http.js";

function input(partial: Partial<ScanMemoryUpsertInput>): ScanMemoryUpsertInput {
  return { scanId: "trk_1", status: "possible", ...partial };
}

describe("confidenceFromStatus", () => {
  it("maps identity statuses to confidence buckets", () => {
    expect(confidenceFromStatus("verified")).toBe("verified");
    expect(confidenceFromStatus("possible")).toBe("possible");
    expect(confidenceFromStatus("needs_clarification")).toBe("needs_confirmation");
    expect(confidenceFromStatus("not_found")).toBe("unknown");
    expect(confidenceFromStatus("error")).toBe("unknown");
    expect(confidenceFromStatus("anything-else")).toBe("unknown");
  });
});

describe("normalizeLinkedIn", () => {
  it("strips scheme, www, query, fragment, trailing slash; lowercases", () => {
    expect(normalizeLinkedIn("https://www.LinkedIn.com/in/Ava-Shah/")).toBe(
      "linkedin.com/in/ava-shah",
    );
    expect(normalizeLinkedIn("http://linkedin.com/in/ava?utm=x#frag")).toBe(
      "linkedin.com/in/ava",
    );
  });
  it("treats differently-formatted same profile as equal keys", () => {
    expect(normalizeLinkedIn("https://www.linkedin.com/in/ava-shah")).toBe(
      normalizeLinkedIn("linkedin.com/in/ava-shah/"),
    );
  });
  it("returns null for empty/missing", () => {
    expect(normalizeLinkedIn(null)).toBeNull();
    expect(normalizeLinkedIn("")).toBeNull();
    expect(normalizeLinkedIn("   ")).toBeNull();
  });
});

describe("nameCompanyKey", () => {
  it("lowercases and collapses whitespace, joins with company", () => {
    expect(nameCompanyKey("  Ava   Shah ", "Acme  Inc")).toBe("ava shah|acme inc");
  });
  it("uses name only when company is missing", () => {
    expect(nameCompanyKey("Ava Shah", null)).toBe("ava shah");
  });
  it("returns null when name missing", () => {
    expect(nameCompanyKey(null, "Acme")).toBeNull();
    expect(nameCompanyKey("", "Acme")).toBeNull();
  });
});

describe("deriveSources", () => {
  it("includes each present signal", () => {
    const s = deriveSources(
      input({
        badgeText: "Ava Shah",
        candidateCount: 2,
        hadFaceVerification: true,
        transcript: "find info on him",
        personId: "person_ava",
      }),
    );
    expect(s.sort()).toEqual(["badge", "face", "fiber", "roster", "voice"].sort());
  });
  it("omits absent signals", () => {
    expect(deriveSources(input({ candidateCount: 0 }))).toEqual([]);
  });
});

describe("isWorthSaving", () => {
  it("keeps verified/possible regardless of fields", () => {
    expect(isWorthSaving(input({ status: "verified" }))).toBe(true);
    expect(isWorthSaving(input({ status: "possible" }))).toBe(true);
  });
  it("keeps a named or candidate-bearing result", () => {
    expect(isWorthSaving(input({ status: "not_found", name: "Ava" }))).toBe(true);
    expect(isWorthSaving(input({ status: "not_found", candidateCount: 1 }))).toBe(true);
  });
  it("skips an empty error / needs_clarification", () => {
    expect(isWorthSaving(input({ status: "error" }))).toBe(false);
    expect(isWorthSaving(input({ status: "needs_clarification" }))).toBe(false);
  });
});

describe("mergeMemory", () => {
  it("creates a fresh memory with scanCount 1 and dedup keys", () => {
    const m = mergeMemory(
      null,
      input({
        name: "Ava Shah",
        company: "Acme",
        linkedinUrl: "https://www.linkedin.com/in/ava-shah/",
        status: "verified",
        badgeText: "Ava Shah",
        candidateCount: 1,
      }),
      1000,
    );
    expect(m.scanCount).toBe(1);
    expect(m.firstScannedAt).toBe(1000);
    expect(m.lastScannedAt).toBe(1000);
    expect(m.confidence).toBe("verified");
    expect(m.linkedinKey).toBe("linkedin.com/in/ava-shah");
    expect(m.nameCompanyKey).toBe("ava shah|acme");
    expect(m.sources.sort()).toEqual(["badge", "fiber"].sort());
  });

  it("updates an existing memory: bumps count, preserves first scan, unions sources, fills gaps", () => {
    const first = mergeMemory(
      null,
      input({ name: "Ava Shah", company: "Acme", badgeText: "Ava", status: "possible" }),
      1000,
    );
    const second = mergeMemory(
      first,
      input({
        name: "Ava Shah",
        linkedinUrl: "linkedin.com/in/ava-shah",
        status: "verified",
        hadFaceVerification: true,
        candidateCount: 2,
      }),
      2000,
    );
    expect(second.scanCount).toBe(2);
    expect(second.firstScannedAt).toBe(1000);
    expect(second.lastScannedAt).toBe(2000);
    expect(second.company).toBe("Acme"); // preserved from first scan
    expect(second.linkedinUrl).toBe("linkedin.com/in/ava-shah"); // filled by second
    expect(second.confidence).toBe("verified");
    expect(second.sources).toEqual(expect.arrayContaining(["badge", "face", "fiber"]));
  });
});

describe("outreach", () => {
  it("firstNameOf and topicOf pick sensible values", () => {
    expect(firstNameOf("Ava Shah")).toBe("Ava");
    expect(firstNameOf(null)).toBe("there");
    expect(topicOf({ company: "Acme" })).toBe("Acme");
    expect(topicOf({ role: "Infra eng" })).toBe("Infra eng");
    expect(topicOf({})).toBe("what you're building");
  });

  it("builds three variants referencing the person, topic, and event", () => {
    const d = buildOutreachOffline(
      { name: "Ava Shah", company: "Acme", eventName: "Orange Slice", senderName: "Pranav" },
      42,
    );
    expect(d.linkedinDm).toContain("Ava");
    expect(d.linkedinDm).toContain("Orange Slice");
    expect(d.linkedinDm).toContain("Recco");
    expect(d.coldEmailSubject).toContain("Orange Slice");
    expect(d.coldEmail).toContain("Acme");
    expect(d.coldEmail).toContain("Pranav");
    expect(d.inPersonOpener).toContain("Ava");
    expect(d.generatedAt).toBe(42);
  });

  it("omits the sign-off name when sender is empty", () => {
    const d = buildOutreachOffline({ name: "Ava", eventName: "X" }, 1);
    expect(d.coldEmail).not.toContain("undefined");
    expect(d.coldEmail.trimEnd().endsWith("Best")).toBe(true);
  });

  it("sanitizeOutreach fills blanks from the fallback", () => {
    const fallback = buildOutreachOffline({ name: "Ava", eventName: "X" }, 1);
    const merged = sanitizeOutreach({ linkedinDm: "custom dm" }, fallback);
    expect(merged.linkedinDm).toBe("custom dm");
    expect(merged.coldEmail).toBe(fallback.coldEmail);
  });
});

describe("brain http parse helpers", () => {
  it("parseScanMemoryUpsertRequest requires scanId + status", () => {
    expect(() => parseScanMemoryUpsertRequest({})).toThrow(HttpError);
    expect(() => parseScanMemoryUpsertRequest({ scanId: "t" })).toThrow(HttpError);
    const ok = parseScanMemoryUpsertRequest({
      scanId: "t",
      status: "possible",
      name: "Ava",
      candidateCount: 2,
      hadFaceVerification: true,
    });
    expect(ok.scanId).toBe("t");
    expect(ok.name).toBe("Ava");
    expect(ok.candidateCount).toBe(2);
    expect(ok.hadFaceVerification).toBe(true);
  });

  it("parseUpdateNotesRequest validates id and notes type", () => {
    expect(() => parseUpdateNotesRequest({ notes: "x" })).toThrow(HttpError);
    expect(() => parseUpdateNotesRequest({ id: "m1", notes: 5 })).toThrow(HttpError);
    expect(parseUpdateNotesRequest({ id: "m1", notes: null })).toEqual({
      id: "m1",
      notes: null,
    });
  });

  it("parseGenerateOutreachRequest requires id, allows optional context", () => {
    expect(() => parseGenerateOutreachRequest({})).toThrow(HttpError);
    expect(
      parseGenerateOutreachRequest({ id: "m1", eventName: "Orange Slice", senderName: "Pranav" }),
    ).toEqual({ id: "m1", eventName: "Orange Slice", senderName: "Pranav" });
  });
});
