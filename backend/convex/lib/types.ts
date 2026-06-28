/**
 * Canonical TypeScript types for the Recco backend.
 *
 * These mirror docs/API_CONTRACTS.md exactly and are the single source of
 * truth used by both the Convex functions and the framework-free helpers in
 * this folder (so the helpers can be unit-tested with plain Node/Vitest, no
 * live Convex deployment required).
 *
 * DO NOT change these shapes without updating docs/API_CONTRACTS.md and telling
 * Persons A/C/D — the contract is frozen.
 */

/** Links block on a Person. All fields optional. */
export type PersonLinks = {
  github?: string;
  linkedin?: string;
  x?: string;
  site?: string;
};

/** A demo roster participant. `faceEmbedding` is server-side only. */
export type Person = {
  id: string;
  name: string;
  role: string;
  company: string;
  avatarUrl?: string;
  bio: string;
  tags: string[];
  links: PersonLinks;
  whyTalk: string;
  openerSeed?: string;
  faceEmbedding?: number[] | null;
};

/** Public-facing person (no embedding). What iOS receives from people:list. */
export type PublicPerson = Omit<Person, "faceEmbedding">;

/** The parsed intent from a voice/typed command. */
export type FilterCommand = {
  action: "filter" | "rank" | "reset" | "draft";
  includeTags: string[];
  excludeTags: string[];
  rankBy?: "relevance" | "infra" | "growth" | "ai" | "founder" | null;
  targetPersonId?: string | null;
  rawText?: string | null;
};

/** Basic quality data attached to a face match. */
export type FaceQuality = {
  faceDetected: boolean;
  detectionScore?: number | null;
  cropWidth?: number | null;
  cropHeight?: number | null;
  model?: string | null;
};

/** Result of attempting to match a face crop to an enrolled person. */
export type FaceMatchResult = {
  trackId: string;
  status: "matched" | "tentative" | "unknown" | "no_face" | "error";
  personId?: string | null;
  score?: number | null;
  quality?: FaceQuality | null;
  message?: string | null;
  latencyMs?: number | null;
};

/** The single reactive app state iOS subscribes to via state:get. */
export type BrainState = {
  activeFilter: FilterCommand;
  highlightedPersonId?: string | null;
  selectedPersonId?: string | null;
  visiblePersonIds: string[];
  dimmedPersonIds: string[];
  lastTranscript?: string | null;
  lastMatch?: FaceMatchResult | null;
  isThinking: boolean;
  updatedAt: number;
};

/** Result of drafting an opener for a person. */
export type DraftResult = {
  personId: string;
  subject?: string | null;
  opener: string;
  email?: string | null;
  generatedAt: number;
};

/** Output of voice:getDeepgramToken. */
export type DeepgramToken = {
  temporaryToken: string;
  expiresAt: number;
};

/** Shape returned by Person A's CV service POST /embed. */
export type EmbedResponse = {
  requestId?: string;
  faceDetected: boolean;
  embedding: number[] | null;
  quality?: FaceQuality | null;
  latencyMs?: number | null;
  error?: string | null;
};
