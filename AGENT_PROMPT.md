# Person C Opus Agent Prompt — Convex Backend Matching + iOS HTTP Bridge

You are Person C, the backend owner for Recco. You are working as an autonomous coding agent.

## Repository

- GitHub repo: https://github.com/Cheemasukh962/Recco
- Your branch: `agent/person-c-backend-matching`
- Base branch: `main`
- Commit only to your branch.

Start with:

```bash
git clone https://github.com/Cheemasukh962/Recco.git
cd Recco
git checkout agent/person-c-backend-matching
```

## Machine Assumption

You are on Windows.

Use:

- PowerShell
- Git Bash
- Node.js/npm

You do not need Xcode. Do not attempt iOS compilation.

## Product Vision

Recco is a native iOS networking scanner for a known roster of 5 people.

The intended live flow:

```txt
iPhone camera
  -> face detection/tracking in Swift
  -> cropped JPEG base64
  -> backend HTTP endpoint
  -> CV service /embed
  -> 512-d embedding
  -> compare against enrolled embeddings in Convex
  -> return matched/tentative/unknown
  -> iOS shows name + LinkedIn only for matched people
```

Your job is to make the backend easy and safe for iOS to call.

This is not a web app. Do not add browser face-recognition packages. The backend already has matching logic.

## Existing Architecture To Preserve

Read these first:

- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/API_CONTRACTS.md`
- `backend/README.md`
- `backend/convex/lib/types.ts`
- `backend/convex/lib/similarity.ts`
- `backend/convex/lib/filter.ts`
- `backend/convex/vision.ts`
- `backend/convex/people.ts`
- `backend/convex/state.ts`
- `backend/convex/voice.ts`
- `backend/convex/drafts.ts`

Important current facts:

- Backend already has public Convex functions.
- Pure helper logic is already unit-tested.
- `npm run typecheck`, `npm run test`, and `npm run smoke` pass on main.
- iOS cannot conveniently call Convex function names directly without a client integration.
- Person A needs ordinary HTTP endpoints.
- Existing contract shapes should not change.

## Your Ownership

You own:

- Convex backend API bridge
- matching safety
- backend endpoint docs
- backend tests
- seed/enrollment compatibility

Primary files you may edit:

- `backend/convex/http.ts`
- `backend/convex/*.ts`
- `backend/convex/lib/*.ts`
- `backend/test/*.ts`
- `backend/scripts/*.ts`
- `backend/README.md`
- `backend/.env.local.example`
- `docs/API_CONTRACTS.md` only if documenting HTTP bridge without changing core DTOs
- `docs/agent-handoffs/PERSON_C_BACKEND.md`

Avoid editing:

- `app/ios/**`
- `cv-service/**` except tiny doc reference if unavoidable

## Required HTTP Endpoints

Implement a Convex HTTP bridge suitable for Person A's native iOS `URLSession` client.

Likely file:

```txt
backend/convex/http.ts
```

Use Convex HTTP actions/routes according to the current Convex version in this repo.

Endpoints to expose:

```txt
GET  /api/people
GET  /api/state
POST /api/state/filter
POST /api/voice/interpret
POST /api/drafts/opener
POST /api/vision/match-face
GET  /api/health
```

### `GET /api/health`

Return:

```json
{
  "ok": true,
  "service": "recco-backend",
  "time": 1782522000000
}
```

Keep this simple. iOS can use it for diagnostics.

### `GET /api/people`

Call existing `people:list` logic or shared helper. Return public people, no embeddings.

Response:

```json
[
  {
    "id": "person_ava_shah",
    "name": "Ava Shah",
    "role": "Founder",
    "company": "VectorKit",
    "avatarUrl": "...",
    "bio": "...",
    "tags": ["AI", "Founder"],
    "links": { "linkedin": "https://linkedin.com/in/ava-demo" },
    "whyTalk": "...",
    "openerSeed": "..."
  }
]
```

### `GET /api/state`

Return `BrainState`.

### `POST /api/state/filter`

Request:

```json
{
  "command": {
    "action": "filter",
    "includeTags": ["AI"],
    "excludeTags": [],
    "rankBy": "relevance",
    "targetPersonId": null,
    "rawText": "show me ai"
  }
}
```

Return `BrainState`.

### `POST /api/voice/interpret`

Request:

```json
{
  "transcript": "show me AI founders",
  "visiblePersonIds": ["person_ava_shah", "person_nina_park"]
}
```

Return `FilterCommand`.

### `POST /api/drafts/opener`

Request:

```json
{
  "personId": "person_ava_shah",
  "userGoal": null
}
```

Return `DraftResult`.

### `POST /api/vision/match-face`

Request:

```json
{
  "imageBase64": "...",
  "imageMimeType": "image/jpeg",
  "trackId": "trk_abc123"
}
```

Return `FaceMatchResult`.

Safety rule:

- If status is `unknown`, `personId` must be null.
- Only `matched` should be used by iOS to show a name.
- Prefer unknown over wrong identity.

## CORS And HTTP Behavior

Add CORS headers so local tools can test easily.

Minimum headers:

```txt
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
Content-Type: application/json
```

Handle `OPTIONS` preflight for each route or globally if Convex supports it cleanly.

All responses should be JSON, including errors.

Error shape:

```json
{
  "ok": false,
  "error": "Readable message"
}
```

HTTP status:

- `200` success
- `400` invalid input
- `405` wrong method if applicable
- `500` unexpected backend error

Do not leak secrets.

## Implementation Guidance

You may wrap existing functions or refactor tiny shared helpers, but do not duplicate lots of logic.

The current backend has Convex functions:

- `people:list`
- `state:get`
- `state:setFilter`
- `vision:matchFace`
- `voice:interpretCommand`
- `drafts:createOpener`

If HTTP routes cannot directly call public actions/mutations the way you expect, use Convex-supported patterns:

- internal queries/mutations/actions
- shared pure functions in `convex/lib`
- thin wrappers

Keep `npm run typecheck` clean.

## Matching Requirements

Review:

- `backend/convex/lib/similarity.ts`
- `backend/convex/lib/cv.ts`
- `backend/convex/vision.ts`

Confirm:

- Embedding dimension remains 512.
- Cosine matching is defensive.
- Thresholds are configurable:
  - `FACE_STRONG_MATCH_SCORE`
  - `FACE_TENTATIVE_MATCH_SCORE`
- Unknown results drop `personId`.
- No face returns `status: "no_face"`.
- CV service unavailable falls back to deterministic mock path for demo reliability.

Add tests if you find gaps.

## Enrollment Compatibility

Person B owns enrollment, but make sure backend seed supports real embeddings:

- `seed:run` should accept `embeddings`.
- `people:list` should never return embeddings.
- `listEnrolled` should only return valid vectors.
- Invalid vectors should not break matching.

If needed, add validation to avoid bad embeddings poisoning the matcher.

## Windows Notes

Use Git Bash for JSON-heavy commands if PowerShell quoting is painful.

Recommended:

```bash
cd backend
npm ci
npm run typecheck
npm run test
npm run smoke
```

For Convex local dev:

```bash
cd backend
npx convex dev
```

or anonymous/local mode if supported:

```bash
CONVEX_AGENT_MODE=anonymous npx convex dev
```

On PowerShell:

```powershell
$env:CONVEX_AGENT_MODE="anonymous"
npx convex dev
```

## Documentation Tasks

Update `backend/README.md` with:

- HTTP endpoint list
- how to deploy/run Convex
- how iOS should set its base URL
- example curl requests
- Windows quoting notes

Fix known broken link:

```txt
../docs/workstreams/02_PERSON_B_BACKEND_MATCHING_CONVEX.md
```

The planning docs moved under:

```txt
../docs/planning/workstreams/
```

## What Not To Do

- Do not edit iOS app implementation.
- Do not add web face-recognition libraries.
- Do not change DTO shapes unless absolutely necessary.
- Do not return embeddings from public people endpoints.
- Do not commit secrets.
- Do not remove mock fallback behavior.
- Do not make the backend require OpenAI, Deepgram, or CV service for basic smoke tests.

## Verification

Required:

```bash
cd backend
npm ci
npm run typecheck
npm run test
npm run smoke
```

If you can run Convex locally, also verify HTTP endpoints manually.

Example shape:

```bash
curl http://127.0.0.1:3210/api/health
curl http://127.0.0.1:3210/api/people
```

The exact local URL may differ. Document the actual URL you used.

If Convex HTTP deployment cannot be manually run on your machine, still implement/typecheck/test and clearly state what remains unverified.

## Commit Instructions

Commit only your work:

```bash
git status
git add backend docs AGENT_PROMPT.md
git commit -m "feat(backend): add iOS HTTP bridge for matching"
git push origin HEAD
```

## Handoff File Required

Create:

```txt
docs/agent-handoffs/PERSON_C_BACKEND.md
```

Include:

- Summary of changes
- Files touched
- Commands run and results
- Exact HTTP endpoints added
- Expected iOS base URL format
- Whether endpoints were manually run
- Any deployment steps
- Known blockers

## Success Definition

You are done when:

- HTTP endpoints exist and typecheck.
- Existing backend tests still pass.
- Smoke script still passes.
- Public people endpoint does not leak embeddings.
- `vision` matching remains fail-safe.
- Backend README tells Person A exactly what URL and endpoints to call.
- You pushed your branch.
