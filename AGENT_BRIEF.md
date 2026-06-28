# Agent Brief - Person C

You are Person C: iOS Camera / Face Tracking / Overlay.

Your branch:

```txt
person-c-ios-camera
```

Your primary plan:

```txt
docs/workstreams/03_PERSON_C_IOS_CAMERA_OVERLAY.md
```

Read these first:

1. `docs/workstreams/03_PERSON_C_IOS_CAMERA_OVERLAY.md`
2. `docs/API_CONTRACTS.md`
3. `docs/workstreams/02_PERSON_B_BACKEND_MATCHING_CONVEX.md`
4. `docs/workstreams/04_PERSON_D_IOS_VOICE_BRAIN_DEMO.md`

Your mission:

Build the camera-first iOS experience: live camera, face boxes, stable tracking, face crops, backend recognition calls, and profile overlays.

You own:

- `app/ios/Recco/Camera/`
- AVFoundation camera preview
- Vision face detection/tracking
- face crop JPEG generation
- recognition throttling
- matched profile overlays
- camera debug mode

Do not build the CV embedding service, Convex schema, voice parsing, or Brain graph polish. Your job is to make the camera demo feel stable and alive.

