/**
 * Pure filter / visibility recomputation for BrainState.
 *
 * Framework-free so it can be unit-tested without a Convex deployment. The
 * Convex `state:setFilter` mutation is a thin wrapper around `applyFilter`.
 *
 * Visibility semantics (documented assumption — the contract leaves "match the
 * current filter" open):
 *   - includeTags use OR semantics: a person matches if they carry ANY of the
 *     requested tags. This is what the demo expects ("show me AI founders"
 *     should brighten everyone AI-ish, not only people who are literally both
 *     AI *and* Founder). With multiple include tags we still rank people who
 *     match more of them higher.
 *   - excludeTags remove a person if they carry ANY excluded tag.
 *   - action "reset" and "draft" do not tag-filter: everyone stays visible.
 */

import type { BrainState, FilterCommand, Person } from "./types.js";

/** A neutral "show everyone" filter command. */
export function defaultFilterCommand(rawText: string | null = null): FilterCommand {
  return {
    action: "reset",
    includeTags: [],
    excludeTags: [],
    rankBy: null,
    targetPersonId: null,
    rawText,
  };
}

function hasAny(personTags: string[], wanted: string[]): boolean {
  if (wanted.length === 0) return false;
  const set = new Set(personTags);
  return wanted.some((t) => set.has(t));
}

/** True if a person passes the include/exclude tag predicate of a command. */
export function personMatchesFilter(person: Person, command: FilterCommand): boolean {
  if (command.excludeTags.length > 0 && hasAny(person.tags, command.excludeTags)) {
    return false;
  }
  if (command.includeTags.length === 0) return true;
  return hasAny(person.tags, command.includeTags);
}

/** Tags that are "adjacent" to a rankBy dimension; presence breaks ties. */
const RANK_ADJACENCY: Record<string, string[]> = {
  infra: ["Infra", "Backend", "DevTools", "Rust"],
  growth: ["Growth", "GoToMarket", "Founder"],
  ai: ["AI", "ML", "Search", "Evaluation"],
  founder: ["Founder", "Seed"],
};

/**
 * Score used to order people for `action: "rank"` (higher = more relevant).
 *
 * Base score = number of requested include tags the person carries. A fractional
 * adjacency bonus then favors people whose overall tag set is concentrated in
 * the rankBy dimension (e.g. for "infra", a Rust/Backend/DevTools engineer ranks
 * above an AI founder who merely also lists Infra) without overriding an exact
 * include-tag match.
 */
export function rankScore(person: Person, command: FilterCommand): number {
  const tagSet = new Set(person.tags);
  let score = command.includeTags.reduce((acc, t) => acc + (tagSet.has(t) ? 1 : 0), 0);
  const adjacency = command.rankBy ? RANK_ADJACENCY[command.rankBy] : undefined;
  if (adjacency) {
    const hits = adjacency.reduce((acc, t) => acc + (tagSet.has(t) ? 1 : 0), 0);
    score += 0.5 * hits;
  }
  return score;
}

export type Visibility = {
  visiblePersonIds: string[];
  dimmedPersonIds: string[];
};

/**
 * Compute visible vs dimmed person ids for a command. Order of `people` is the
 * stable tie-breaker; for rank actions, visible ids are sorted by rankScore desc.
 */
export function computeVisibility(people: Person[], command: FilterCommand): Visibility {
  const allIds = people.map((p) => p.id);

  if (command.action === "reset" || command.action === "draft") {
    return { visiblePersonIds: allIds, dimmedPersonIds: [] };
  }

  const matching = people.filter((p) => personMatchesFilter(p, command));

  let ordered = matching;
  if (command.action === "rank") {
    ordered = matching
      .map((p, i) => ({ p, i, s: rankScore(p, command) }))
      .sort((a, b) => (b.s - a.s) || (a.i - b.i))
      .map((x) => x.p);
  }

  const visible = ordered.map((p) => p.id);
  const visibleSet = new Set(visible);
  const dimmed = allIds.filter((id) => !visibleSet.has(id));
  return { visiblePersonIds: visible, dimmedPersonIds: dimmed };
}

/** A fresh BrainState with everyone visible and no filter applied. */
export function emptyBrainState(people: ReadonlyArray<{ id: string }>, now: number): BrainState {
  return {
    activeFilter: defaultFilterCommand(),
    highlightedPersonId: null,
    selectedPersonId: null,
    visiblePersonIds: people.map((p) => p.id),
    dimmedPersonIds: [],
    lastTranscript: null,
    lastMatch: null,
    isThinking: false,
    updatedAt: now,
  };
}

/**
 * Apply a FilterCommand to the previous BrainState, returning the next state.
 *
 *   - Recomputes visible/dimmed for every action.
 *   - Clears highlightedPersonId ONLY on reset (per the contract).
 *   - On draft, records targetPersonId as selectedPersonId.
 *   - Always bumps updatedAt.
 */
export function applyFilter(
  prev: BrainState,
  command: FilterCommand,
  people: Person[],
  now: number,
): BrainState {
  const { visiblePersonIds, dimmedPersonIds } = computeVisibility(people, command);

  const next: BrainState = {
    ...prev,
    activeFilter: command,
    visiblePersonIds,
    dimmedPersonIds,
    isThinking: false,
    updatedAt: now,
  };

  if (command.rawText) {
    next.lastTranscript = command.rawText;
  }

  if (command.action === "reset") {
    next.highlightedPersonId = null;
    next.selectedPersonId = null;
  }

  if (command.action === "draft" && command.targetPersonId) {
    next.selectedPersonId = command.targetPersonId;
  }

  return next;
}
