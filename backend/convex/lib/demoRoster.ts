/**
 * In-code copy of the demo roster.
 *
 * Convex functions cannot read files at runtime, so the seed data from
 * demo-data/people.sample.json is bundled here. Keep this in sync with that
 * file (the enrollment script reads the JSON; the seed mutation reads this).
 *
 * `faceEmbedding` is intentionally null here — the seed mutation attaches either
 * a real enrolled embedding (when provided) or a deterministic mock one.
 */

import type { Person } from "./types.js";

/** Enrollment image paths, kept separate from the stored Person shape. */
export const ENROLLMENT_IMAGE_PATHS: Record<string, string> = {
  person_ava_shah: "demo-data/enrollment/ava.jpg",
  person_miles_chen: "demo-data/enrollment/miles.jpg",
  person_sam_rivera: "demo-data/enrollment/sam.jpg",
  person_nina_park: "demo-data/enrollment/nina.jpg",
  person_omar_wilson: "demo-data/enrollment/omar.jpg",
};

export const DEMO_PEOPLE: Person[] = [
  {
    id: "person_ava_shah",
    name: "Ava Shah",
    role: "Founder",
    company: "VectorKit",
    avatarUrl: "https://example.com/demo/ava.jpg",
    bio: "Building infra for multimodal AI agents.",
    tags: ["AI", "Founder", "Infra", "Seed", "Python"],
    links: {
      github: "https://github.com/ava-demo",
      linkedin: "https://linkedin.com/in/ava-demo",
      x: "https://x.com/ava_demo",
    },
    whyTalk:
      "Ava is useful if you want to discuss AI infra, agent memory, or seed-stage founder problems.",
    openerSeed: "Ask about the hardest latency issue in multimodal agent infra.",
    faceEmbedding: null,
  },
  {
    id: "person_miles_chen",
    name: "Miles Chen",
    role: "Engineer",
    company: "Runloop",
    avatarUrl: "https://example.com/demo/miles.jpg",
    bio: "Systems engineer working on Rust services and developer tooling.",
    tags: ["Rust", "Infra", "DevTools", "Backend"],
    links: {
      github: "https://github.com/miles-demo",
      linkedin: "https://linkedin.com/in/miles-demo",
    },
    whyTalk:
      "Miles is a strong match for low-level infra, Rust, and developer workflow conversations.",
    openerSeed: "Ask what Rust tooling still feels too painful for startup teams.",
    faceEmbedding: null,
  },
  {
    id: "person_sam_rivera",
    name: "Sam Rivera",
    role: "Growth Lead",
    company: "LaunchPad",
    avatarUrl: "https://example.com/demo/sam.jpg",
    bio: "Growth operator helping technical founders find first users.",
    tags: ["Growth", "Founder", "GoToMarket", "Seed"],
    links: {
      github: "https://github.com/sam-demo",
      linkedin: "https://linkedin.com/in/sam-demo",
      x: "https://x.com/sam_demo",
    },
    whyTalk:
      "Sam is the right person for founder-led growth, early user acquisition, and positioning.",
    openerSeed: "Ask what channel is working for technical founders right now.",
    faceEmbedding: null,
  },
  {
    id: "person_nina_park",
    name: "Nina Park",
    role: "Designer",
    company: "Northstar",
    avatarUrl: "https://example.com/demo/nina.jpg",
    bio: "Designs AI-native interfaces for prosumer tools.",
    tags: ["Design", "AI", "Product", "Frontend"],
    links: {
      github: "https://github.com/nina-demo",
      linkedin: "https://linkedin.com/in/nina-demo",
    },
    whyTalk: "Nina can help with interaction design, AI UX, and making demos feel obvious.",
    openerSeed:
      "Ask how she decides when an AI interface should be chat, canvas, or direct manipulation.",
    faceEmbedding: null,
  },
  {
    id: "person_omar_wilson",
    name: "Omar Wilson",
    role: "ML Engineer",
    company: "Searchlight",
    avatarUrl: "https://example.com/demo/omar.jpg",
    bio: "Works on retrieval, ranking, and evaluation pipelines.",
    tags: ["AI", "Search", "ML", "Evaluation", "Python"],
    links: {
      github: "https://github.com/omar-demo",
      linkedin: "https://linkedin.com/in/omar-demo",
    },
    whyTalk: "Omar is useful for RAG, ranking quality, evals, and search infrastructure.",
    openerSeed: "Ask what evaluation signal he trusts most for retrieval quality.",
    faceEmbedding: null,
  },
];
