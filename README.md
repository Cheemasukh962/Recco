# Recco

Recco is the hackathon build folder for the camera-first Voice Brain demo.

Core demo:

1. A user opens the iOS camera at a small event demo group.
2. The app recognizes 3-5 enrolled participants.
3. Profile overlays show who they are, what they build, and why to talk to them.
4. Voice commands filter/rank the visible people and the broader event roster.
5. The app can draft a short opener or email for a selected person.

This folder contains:

- `open-source/` - cloned reference repos and libraries.
- `docs/FOUR_PERSON_HANDOFF.md` - detailed PM plan for the 4-person split.
- `docs/API_CONTRACTS.md` - shared contracts for CV, Convex, and iOS.
- `demo-data/people.sample.json` - seed shape for the demo roster.

Start here:

1. Read `docs/FOUR_PERSON_HANDOFF.md`.
2. Treat `docs/API_CONTRACTS.md` as frozen after the first team sync.
3. Give each teammate their matching workstream file:
   - `docs/workstreams/01_PERSON_A_CV_SERVICE_INSIGHTFACE.md`
   - `docs/workstreams/02_PERSON_B_BACKEND_MATCHING_CONVEX.md`
   - `docs/workstreams/03_PERSON_C_IOS_CAMERA_OVERLAY.md`
   - `docs/workstreams/04_PERSON_D_IOS_VOICE_BRAIN_DEMO.md`
4. Each person builds their lane against the contracts, then integrates at the checkpoints.
