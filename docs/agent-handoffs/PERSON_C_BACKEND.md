# Person C Handoff — Backend iOS HTTP Bridge + Matching Safety

**Branch:** `agent/person-c-backend-matching`
**Owner:** Person C (backend bridge, matching safety, backend docs/tests)

## Summary of changes

Added an **HTTP/JSON bridge** so Person A's native iOS `URLSession` client can
call the backend without a Convex client integration. The bridge is a thin layer
over the existing public Convex functions — **no contract/DTO shapes changed**.

- New `backend/convex/http.ts` — Convex `httpRouter` exposing 7 REST-ish routes,
  each wrapping an existing public function. Permissive CORS, `OPTIONS` preflight
  on every route, JSON-everywhere responses (including errors), and a defensive
  re-assert of the face-match safety rule at the HTTP boundary.
- New `backend/convex/lib/http.ts` — framework-free request validators +
  response builders (`jsonResponse`, `errorResponse`, `optionsResponse`,
  `parse*Request`, `sanitizeMatchResult`, `HttpError`). Pure, so unit-testable.
- New `backend/test/http.test.ts` — 23 unit tests for the helpers (response
  headers/shape, input validation 400s, match-safety stripping of `personId`).
- Docs: new HTTP sections in `backend/README.md` and `docs/API_CONTRACTS.md`;
  fixed the broken Person B spec link in `backend/README.md`.

**Matching review (confirmed, no code change needed):** embedding dim stays
`512` (`EMBEDDING_DIM`); `cosine` is defensive (returns 0 for length-mismatch /
zero vectors); thresholds configurable via `FACE_STRONG_MATCH_SCORE` /
`FACE_TENTATIVE_MATCH_SCORE`; `unknown` drops `personId` (`toFaceMatchResult`);
no face → `status:"no_face"`; CV service unreachable → deterministic mock
fallback (`lib/cv.ts`). Enrollment compatibility holds: `seed:run` accepts
`embeddings`, `people:list` never returns embeddings, `people:listEnrolled`
filters to finite vectors (`isFiniteVector`), and bad-dimension vectors can't
produce a false match (cosine returns 0 on length mismatch). Added the HTTP
`sanitizeMatchResult` net so a wrong identity can never reach iOS.

## Files touched

| File | Change |
|---|---|
| `backend/convex/http.ts` | **new** — HTTP router / 7 endpoints + OPTIONS |
| `backend/convex/lib/http.ts` | **new** — pure validators + response helpers |
| `backend/test/http.test.ts` | **new** — 23 unit tests |
| `backend/README.md` | added "HTTP bridge for iOS" section; fixed broken link |
| `docs/API_CONTRACTS.md` | added "HTTP bridge (iOS ↔ backend)" doc section (no DTO change) |
| `docs/agent-handoffs/PERSON_C_BACKEND.md` | **new** — this file |

No iOS, CV-service, or other agents' files were modified.

## HTTP endpoints added

| Method | Path | Body | Returns |
|---|---|---|---|
| `GET`  | `/api/health` | — | `{ ok, service, time }` |
| `GET`  | `/api/people` | — | `PublicPerson[]` (no embeddings) |
| `GET`  | `/api/state` | — | `BrainState` |
| `POST` | `/api/state/filter` | `{ command: FilterCommand }` | `BrainState` |
| `POST` | `/api/voice/interpret` | `{ transcript, visiblePersonIds? }` | `FilterCommand` |
| `POST` | `/api/drafts/opener` | `{ personId, userGoal? }` | `DraftResult` |
| `POST` | `/api/vision/match-face` | `{ imageBase64, imageMimeType?, trackId? }` | `FaceMatchResult` |

- CORS on every route (`Access-Control-Allow-Origin: *`); `OPTIONS` → `204`.
- Errors are JSON `{ ok:false, error }`. Status: `200` / `400` / `404` / `500`.
- `match-face`: only `matched`/`tentative` carry `personId`;
  `unknown`/`no_face`/`error` → `personId: null`. iOS shows a name only for
  `matched`.

## Expected iOS base URL format

iOS base URL = the Convex **HTTP actions** URL = `CONVEX_SITE_URL` (the
`.convex.site` host), **not** the `.convex.cloud` client URL.

- Local anonymous dev: `http://127.0.0.1:3211`
- Cloud: `https://<deployment>.convex.site`

iOS appends the paths above, e.g. `GET {BASE}/api/people`. (`backend/.env.local`
records both `CONVEX_URL` = :3210 client and `CONVEX_SITE_URL` = :3211 HTTP.)

## Commands run and results

```text
npm ci             -> ok
npm run typecheck  -> clean (0 errors)
npm run test       -> 72 passed (5 files); was 49, +23 new HTTP tests
npm run smoke      -> "SMOKE TEST COMPLETE — all functions produced contract-shaped output"
```

Live local deployment (`CONVEX_AGENT_MODE=anonymous npx convex dev`):

```text
npx convex dev     -> deployed; API :3210, HTTP actions :3211
npx convex run seed:run -> { peopleInserted: 5, usedRealEmbeddings: false }
```

Manual endpoint checks (against `http://127.0.0.1:3211`):

```text
GET  /api/health                 -> 200 {"ok":true,"service":"recco-backend","time":...} + CORS headers
GET  /api/people                 -> 200 PublicPerson[]; grep "faceEmbedding" => NONE (no leak)
GET  /api/state                  -> 200 BrainState
POST /api/state/filter           -> 200 BrainState (AI filter dims miles+sam)
POST /api/voice/interpret        -> 200 {"action":"rank","includeTags":["Infra"],"rankBy":"infra",...}
POST /api/drafts/opener          -> 200 DraftResult for person_ava_shah
POST /api/vision/match-face (marker)  -> 200 {"status":"matched","personId":"person_ava_shah","score":1}
POST /api/vision/match-face (random)  -> 200 {"status":"unknown","personId":null,...}   <-- safety OK
OPTIONS /api/state/filter        -> 204 + CORS headers
POST bad JSON / bad action / no imageBase64 -> 400 {"ok":false,"error":...}
GET  /api/nope                   -> 404 (Convex default)
```

## Whether endpoints were manually run

**Yes.** Verified against a live local anonymous Convex deployment (HTTP actions
on `http://127.0.0.1:3211`) with the roster seeded. All 7 routes, CORS preflight,
error paths, and the no-embedding-leak / unknown-drops-personId invariants
behaved as specified.

## Deployment steps

- **Local (no account):** `cd backend && CONVEX_AGENT_MODE=anonymous npx convex dev`
  then `npx convex run seed:run`. HTTP base = `http://127.0.0.1:3211`.
  (PowerShell: `$env:CONVEX_AGENT_MODE="anonymous"; npx convex dev`.)
- **Cloud:** `npx convex deploy` (or logged-in `npx convex dev`), set env with
  `npx convex env set ...`, and give iOS the printed `.convex.site` URL.

## Known blockers / notes

- None blocking. All required checks pass; endpoints manually verified.
- `convex/_generated/api.*` was regenerated by `convex dev` and now includes the
  `http` module — committed so the project typechecks out of the box.
- The Convex CLI prints a harmless `Assertion failed: ... async.c` libuv message
  on process exit on Windows; it does not affect results.
- Real face recognition still needs Person A's CV service at `CV_SERVICE_URL`;
  without it, matching uses the deterministic mock path (by design).
