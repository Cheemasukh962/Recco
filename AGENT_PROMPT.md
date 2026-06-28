# Person A Opus Agent Prompt — iOS Live Backend + Face Overlay

You are Person A, the iOS owner for Recco. You are working as an autonomous coding agent on the native SwiftUI iOS app.

## Repository

- GitHub repo: https://github.com/Cheemasukh962/Recco
- Your branch: `agent/person-a-ios-live-overlay`
- Base branch: `main`
- Commit only to your branch.

Start with:

```bash
git clone https://github.com/Cheemasukh962/Recco.git
cd Recco
git checkout agent/person-a-ios-live-overlay
```

## Machine Assumption

You are the only person with:

- MacBook
- Xcode
- iOS Simulator
- Optional physical iPhone

Because you have Xcode, you own anything that must compile in the iOS app. Other agents should not be trusted to validate Swift compilation.

## Product Vision

Recco is a native iOS networking scanner.

The intended demo:

1. Open the iPhone app.
2. Camera starts.
3. The app sees up to 5 known/enrolled people in front of the camera.
4. Each recognized person gets a face-anchored overlay.
5. The overlay shows their name and useful profile info, especially LinkedIn.
6. Tapping the overlay opens the full profile sheet.
7. Unknown people should not get a wrong name. Prefer `unknown` over misidentification.

This is not a web app. Do not add `@vladmandic/face-api`, TensorFlow.js, React, Next.js, or browser face-recognition dependencies.

## Existing Architecture To Preserve

Read these first:

- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/API_CONTRACTS.md`
- `app/ios/Recco/README.md`
- `app/ios/Recco/Camera/README.md`

Important current facts:

- `mockAll` already works offline.
- `CameraView` already uses AVFoundation/Vision or Simulator fallback.
- The camera path already crops real faces.
- `ConvexBackend.swift` is currently a placeholder that delegates to `MockBackend`.
- `ProfileSheetView` already displays links.
- `FaceOverlayCard` exists in `CameraPlaceholderView.swift` and is reused by the real camera.
- The backend agent will expose simple HTTP endpoints for iOS.

Do not break `mockAll`. This is the safety mode for demo recovery.

## Your Ownership

You own:

- iOS live backend client
- iOS environment configuration
- camera overlay polish
- iOS filter behavior alignment
- Xcode build verification

Primary files you may edit:

- `app/ios/Recco/Recco/State/Backend/ConvexBackend.swift`
- `app/ios/Recco/Recco/State/Backend/ReccoBackend.swift`
- `app/ios/Recco/Recco/State/AppModel.swift`
- `app/ios/Recco/Recco/ReccoApp.swift`
- `app/ios/Recco/Recco/Camera/*`
- `app/ios/Recco/Recco/Views/CameraPlaceholderView.swift`
- `app/ios/Recco/Recco/Views/ProfileSheetView.swift`
- `app/ios/Recco/Recco/Views/RootView.swift`
- `app/ios/Recco/Recco/Views/Components.swift`
- `app/ios/Recco/Recco/Models/*`
- `app/ios/Recco/README.md`

Avoid editing backend, CV service, and global docs unless you need a tiny note for your handoff.

## Expected Backend HTTP Contract

Person C should expose these endpoints. Implement your client against this contract, and keep the code tolerant of backend errors.

Base URL:

- Prefer env var `RECCO_API_BASE_URL`
- Fall back to existing `CONVEX_URL`
- If no URL exists, live/mockCV should degrade gracefully to local fallback with a visible status message.

Endpoints:

```txt
GET  /api/people
GET  /api/state
POST /api/state/filter
POST /api/voice/interpret
POST /api/drafts/opener
POST /api/vision/match-face
```

Expected JSON:

### `GET /api/people`

Returns `[PersonDTO]` shape matching `docs/API_CONTRACTS.md`, without face embeddings.

### `GET /api/state`

Returns `BrainStateDTO`.

### `POST /api/state/filter`

Request:

```json
{ "command": { "action": "filter", "includeTags": ["AI"], "excludeTags": [], "rankBy": "relevance", "targetPersonId": null, "rawText": "show me ai" } }
```

Response: `BrainStateDTO`.

### `POST /api/voice/interpret`

Request:

```json
{ "transcript": "show me AI founders", "visiblePersonIds": ["person_ava_shah"] }
```

Response: `FilterCommandDTO`.

### `POST /api/drafts/opener`

Request:

```json
{ "personId": "person_ava_shah", "userGoal": null }
```

Response: `DraftResultDTO`.

### `POST /api/vision/match-face`

Request:

```json
{ "imageBase64": "...", "imageMimeType": "image/jpeg", "trackId": "trk_abc123" }
```

Response: `FaceMatchResultDTO`.

Only show an overlay for `status == "matched"`.

## Implementation Tasks

### 1. Implement A Small HTTP Client

In `ConvexBackend.swift`, replace placeholder bodies with real HTTP calls using `URLSession`.

Requirements:

- No third-party Swift networking package.
- Encode/decode with `JSONEncoder` and `JSONDecoder`.
- Add useful errors via `BackendError` or a new local error type.
- Add request timeout if feasible.
- Handle non-2xx with a readable message.
- If backend URL is missing, use the existing `MockBackend` fallback.
- If backend call fails during demo, fall back where safe and set a user-visible `statusMessage` from `AppModel` if needed.

Suggested internal helpers:

```swift
private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T
private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body, as type: T.Type) async throws -> T
```

Use endpoint paths exactly as above. Make path joining robust so both `https://foo` and `https://foo/` work.

### 2. Wire Demo Modes Correctly

Expected behavior:

- `mockAll`: no network, no backend, no CV. Must always work.
- `mockCV`: backend may be real for people/voice/drafts/state; face recognition may remain deterministic/fallback if live CV is not ready.
- `live`: send real face crop to backend `/api/vision/match-face`.

Current `CameraViewModel` already only crops real pixels when not `mockAll`. Keep this.

If Simulator has no pixels and is using simulated source:

- `mockAll`: should still show deterministic overlays.
- `live`: no real face image exists, so it can return `no_face` or fallback with an explanatory status. Do not make Simulator live mode look broken.

### 3. Align iOS Filter Semantics With Backend

Backend uses OR semantics for `includeTags`.

Update `FilterEngine.partition` so:

- A person is visible if they have any included tag.
- Excluded tags still remove people.
- Empty include means everyone unless excluded.
- `rank` can still order visible people by match count/relevance.

This fixes current drift where iOS uses AND semantics and backend uses OR.

### 4. Improve Face Overlay For The Real Product

The face overlay should clearly show:

- Name
- Role/company
- LinkedIn if present
- Maybe one or two tags

Add a direct LinkedIn affordance if possible.

Options:

- A compact LinkedIn icon/button inside `FaceOverlayCard`
- A text pill saying `LinkedIn`
- A small link icon if SF Symbols lacks a brand icon

Do not make the overlay huge. Multiple faces may be on screen. Keep it readable, compact, and tappable.

Important:

- Tapping the card should still open `ProfileSheetView`.
- If tapping the LinkedIn button is nested inside the card, avoid gesture conflicts if possible.
- If direct link handling gets messy, show LinkedIn visibly on overlay and keep full opening in the profile sheet. But try to make direct LinkedIn available.

### 5. Keep Unknown Safe

Rules:

- Only `matched` results show person overlays.
- `tentative`, `unknown`, `no_face`, `error` should not show a named card.
- Debug HUD may show status, but not a wrong profile.

### 6. Add Clear User-Facing Status

When live backend URL is absent or failing, avoid silent confusion:

- Show a short status message in the existing transcript/status area if possible.
- Do not spam alerts.
- Keep the app usable in mock modes.

### 7. Update iOS README

Update `app/ios/Recco/README.md` with:

- `RECCO_API_BASE_URL`
- `DEMO_MODE`
- How to run `mockAll`
- How to run `live`
- What URL to use once Person C backend bridge is deployed

## What Not To Do

- Do not add web face-recognition libraries.
- Do not change shared DTO shapes without a strong reason.
- Do not remove mock mode.
- Do not commit secrets.
- Do not commit local Xcode user data.
- Do not make backend schema changes.
- Do not depend on a physical iPhone for build success.

## Verification

Required:

```bash
xcodebuild -project app/ios/Recco/Recco.xcodeproj \
  -scheme Recco \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO
```

Also run the app in Simulator if possible:

- Confirm `mockAll` opens.
- Confirm simulated camera overlays appear.
- Confirm tapping a face opens profile.
- Confirm LinkedIn appears in overlay or profile.
- Confirm changing demo mode does not crash.

If you have a physical iPhone:

- Run `mockAll` on device.
- Confirm camera permission flow works.
- Confirm real camera face boxes appear.
- Do not require live backend to pass if Person C is not done yet.

## Commit Instructions

Commit only your work:

```bash
git status
git add app/ios/Recco AGENT_PROMPT.md docs/agent-handoffs/PERSON_A_IOS.md
git commit -m "feat(ios): wire live backend and LinkedIn overlays"
git push origin HEAD
```

If your implementation requires a different commit message, keep it short and imperative.

## Handoff File Required

Create:

```txt
docs/agent-handoffs/PERSON_A_IOS.md
```

Include:

- Summary of changes
- Files touched
- Exact build command result
- Whether Simulator was manually run
- Whether physical iPhone was tested
- Required env vars
- Known blockers
- Any assumptions about Person C endpoints

## Success Definition

You are done when:

- iOS builds with Xcode.
- `mockAll` still works.
- `ConvexBackend` has real HTTP implementation, not TODO placeholders.
- `live` can call backend endpoints when `RECCO_API_BASE_URL` is set.
- Face overlay visibly supports the name + LinkedIn/profile experience.
- You pushed your branch.
