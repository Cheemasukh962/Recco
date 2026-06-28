# Person B Opus Agent Prompt — CV Service + Face Enrollment

You are Person B, the CV and enrollment workflow owner for Recco. You are working as an autonomous coding agent.

## Repository

- GitHub repo: https://github.com/Cheemasukh962/Recco
- Your branch: `agent/person-b-cv-enrollment`
- Base branch: `main`
- Commit only to your branch.

Start with:

```bash
git clone https://github.com/Cheemasukh962/Recco.git
cd Recco
git checkout agent/person-b-cv-enrollment
```

## Machine Assumption

You have:

- MacBook
- Terminal
- Python available or installable
- Node/npm available or installable
- No Xcode requirement

You should not touch or validate native iOS compilation. Person A owns Xcode.

## Product Vision

Recco is a native iOS networking scanner for a known roster of 5 people.

The intended demo:

1. The iPhone camera sees a known person.
2. iOS crops that face.
3. Backend sends the crop to the CV service.
4. CV service returns a 512-dimensional face embedding.
5. Backend compares that embedding against enrolled people.
6. iOS displays the matched person name + LinkedIn/profile overlay.

Your job is to make step 4 and the enrollment setup reliable.

This is not a web app. Do not add `@vladmandic/face-api`, TensorFlow.js browser code, or JavaScript face recognition. The existing native/backend architecture uses FastAPI + InsightFace.

## Existing Architecture To Preserve

Read these first:

- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/API_CONTRACTS.md`
- `cv-service/README.md`
- `backend/README.md`
- `backend/scripts/enroll.ts`
- `cv-service/main.py`

Important current facts:

- `cv-service/main.py` already exposes `GET /health`, `POST /embed`, and `POST /debug/detect`.
- Default model in code is `buffalo_s`.
- The repo gitignores `demo-data/enrollment/` and `demo-data/embeddings.generated.json`.
- Enrollment script already exists but should be made more production-demo friendly.
- Real face images must never be committed.

## Your Ownership

You own:

- CV service docs consistency
- Enrollment workflow
- Embedding validation
- Local run instructions
- Better failure messages for missing images or unavailable CV service

Primary files you may edit:

- `cv-service/main.py`
- `cv-service/test_embed.py`
- `cv-service/README.md`
- `cv-service/requirements.txt`
- `backend/scripts/enroll.ts`
- `backend/.env.local.example`
- `demo-data/people.sample.json` only if necessary
- `docs/` only for CV/enrollment docs or your handoff

Avoid editing:

- `app/ios/**`
- Convex function contracts
- Backend matching logic unless a tiny compatibility fix is unavoidable

## Target Enrollment Workflow

The desired final workflow should be easy for a teammate:

```bash
# 1. Put private face photos here, not committed:
demo-data/enrollment/ava.jpg
demo-data/enrollment/miles.jpg
demo-data/enrollment/sam.jpg
demo-data/enrollment/nina.jpg
demo-data/enrollment/omar.jpg

# 2. Start CV service:
cd cv-service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --port 8000

# 3. In another terminal:
cd backend
cp .env.local.example .env.local
# set CV_SERVICE_URL=http://127.0.0.1:8000
npm ci
npm run enroll
```

Expected output:

- For each person, show whether embedding came from real CV or mock fallback.
- Validate each embedding:
  - array
  - length 512
  - all finite numbers
  - approximate L2 norm near 1.0 for real CV output
- Write `demo-data/embeddings.generated.json`.
- Do not crash on one missing image. Report it and continue with mock fallback.

## Implementation Tasks

### 1. Harden `backend/scripts/enroll.ts`

Make the script clear and reliable.

Required behavior:

- Load `backend/.env.local` without overwriting existing env vars.
- Read `CV_SERVICE_URL`.
- If `CV_SERVICE_URL` is set, call `GET /health` before enrolling and report:
  - reachable/unreachable
  - model name
  - ready true/false
  - error if present
- For each person in `demo-data/people.sample.json`:
  - read `enrollmentImagePath`
  - if image exists and CV is healthy, call `/embed`
  - if image missing, use deterministic mock embedding and report `mock (image missing)`
  - if CV no-face, use mock and report `mock (CV found no face)`
  - if CV error/unreachable, use mock and report `mock (CV unavailable)`
- Validate every final embedding before writing.
- Print a final summary:
  - total people
  - real embeddings count
  - mock fallback count
  - output path
  - exact next command to seed Convex

Do not add heavy dependencies unless truly needed. Existing Node APIs are enough.

### 2. Add Embedding Validation Helpers

In `enroll.ts`, add small helper functions:

- `isFiniteEmbedding(value): value is number[]`
- `embeddingNorm(values): number`
- `validateEmbedding(personId, values, source)`

For mock embeddings, length should still be 512 and finite.

For real CV embeddings, warn if norm is not roughly 1.0. Use tolerance such as `abs(norm - 1) < 0.02`.

### 3. Improve CV Service Docs

Fix inconsistent docs.

Current known drift:

- Code default is `buffalo_s`.
- Some docs say first startup downloads `buffalo_l`.
- Root README says ~90 ms warm, while CV README/code mention ~380 ms warm.

Make docs honest and consistent:

- Default: `buffalo_s`
- Optional: `RECCO_CV_MODEL=buffalo_l`
- Mention model consistency: enrollment and matching must use the same model.
- Mention Python 3.10-3.11 recommended.
- Make it clear that real photos are private and gitignored.

### 4. Add A Focused Enrollment Doc

Create:

```txt
docs/FACE_ENROLLMENT.md
```

Include:

- Why enrollment is needed
- How to capture good photos
- Where to place files
- How to start CV service
- How to run `npm run enroll`
- How to seed Convex with generated embeddings
- How to verify no secrets/images were committed
- Troubleshooting:
  - model not ready
  - no face detected
  - wrong Python version
  - InsightFace install issues
  - mock fallback happened

### 5. Keep Privacy Safe

Rules:

- Never commit real face images.
- Never commit generated embeddings.
- Keep `.gitignore` protecting:
  - `demo-data/enrollment/`
  - `demo-data/embeddings.generated.json`
- If you add example data, it must be fake or text-only.

### 6. Optional CV Service Improvements

Only if low-risk:

- Make `/health` include `detSize` and `minDetScore`.
- Make `/embed` error messages a little clearer.
- Keep response shapes contract-compatible.

Do not rewrite `main.py` heavily.

## What Not To Do

- Do not edit iOS app files.
- Do not add browser face recognition libraries.
- Do not commit real photos.
- Do not commit `embeddings.generated.json`.
- Do not require cloud deployment for local enrollment.
- Do not change API contracts without coordination.

## Verification

Required:

```bash
python -m py_compile cv-service/main.py cv-service/test_embed.py
cd backend
npm ci
npm run typecheck
npm run test
```

If Python 3.10 or 3.11 is available, also run:

```bash
cd cv-service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --port 8000
curl http://127.0.0.1:8000/health
```

Then:

```bash
cd backend
CV_SERVICE_URL=http://127.0.0.1:8000 npm run enroll
```

If you do not have real enrollment images, confirm that the script cleanly falls back to mock embeddings.

## Commit Instructions

Commit only your work:

```bash
git status
git add cv-service backend/scripts backend/.env.local.example docs AGENT_PROMPT.md
git commit -m "feat(cv): harden face enrollment workflow"
git push origin HEAD
```

## Handoff File Required

Create:

```txt
docs/agent-handoffs/PERSON_B_CV_ENROLLMENT.md
```

Include:

- Summary of changes
- Files touched
- Commands run and results
- Whether real CV service was run
- Whether enrollment used real images or mock fallback
- Exact steps for teammates
- Known blockers

## Success Definition

You are done when:

- Enrollment workflow is documented.
- `npm run enroll` gives clear output and produces valid 512-d embeddings.
- Missing real images do not crash the workflow.
- CV docs are consistent with code defaults.
- Privacy-sensitive files remain gitignored.
- You pushed your branch.
