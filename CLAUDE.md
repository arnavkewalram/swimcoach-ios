# SwimCoach

iOS app + ML pipeline for AI swimming technique analysis. The SwimTCN model
(temporal CNN over pose keypoints) is the ONLY detection path on both
platforms — there is no rule-based fallback anywhere.

## Layout

- `iOS/` — SwiftUI app (iOS 17+, XcodeGen project). Pipeline:
  `PoseAnalyzer` (Vision) → `FeatureExtractor` (windowing + y-flip) →
  `SwimTCNRunner` (CoreML) → `FeedbackEngine` (decode) → SwiftData history.
- `ml/` — Python pipeline: MediaPipe extraction → windowed SwimTCN →
  report. Also: synthetic datagen, training, CoreML conversion.
- `backend/` — FastAPI Cloud Run service wrapping ml/ (same gate + windowed
  detector as the CLI). Build from REPO ROOT: `docker build -f
  backend/Dockerfile .`; deploy with `./backend/deploy.sh`. Not covered by
  CI (no gcloud/docker on runners); smoke-test imports locally before merge.

This monorepo is canonical for the entire product. The old separate repos
(swim-analyzer, swim-analyzer-backend, SwimCoach Flutter app) are archived.

## Commands

```bash
# Python tests (fast — needs only numpy/scipy/pytest)
cd ml && .venv/bin/python -m pytest tests/ -q

# CLI on a video (full deps: pip install -r requirements.txt into ml/.venv)
cd ml && .venv/bin/python main.py <video.mp4> --output-dir out

# Retrain → convert → verify (after datagen/model changes)
cd ml && .venv/bin/python -m ml.train --n 12000 --epochs 100
cd ml && .venv/bin/python coreml_convert.py   # writes into iOS/SwimCoach/Resources/

# iOS: regenerate project after ANY project.yml change, then test
cd iOS && xcodegen generate
cd iOS && xcodebuild test -project SwimCoach.xcodeproj -scheme SwimCoach \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Contracts that must stay in sync (breakage is silent)

- Model input is `(1, 39, 90)`: 13 joints × (x, y, conf), 90 frames @ 30 fps.
  Channel = joint*3 + coord. Both platforms slide 3-second windows and
  average probabilities — never resample a whole clip to 90 frames.
- Coordinates are MediaPipe convention (y DOWN). Vision reports y up, so
  `FeatureExtractor.swift` flips (`1 - y`). Do not remove that flip.
- `ml/ml/model.py` `ISSUE_LABELS` order == `FeedbackEngine.catalog` order.
- `SwimTCN.forward()` returns raw logits clamped ±1.9; sigmoid is applied
  by callers (Python) and baked into the CoreML export (`SwimTCNWithSigmoid`).
- `iOS/SwimCoachTests/RealFootageParityTests.swift` pins app-vs-Python
  agreement on real footage. After retraining, regenerate
  `RealFootageFixtures.swift` (expected values change with weights).

## Gotchas

- `ml/.venv` was moved from another path: `.venv/bin/pip` is broken — always
  use `.venv/bin/python -m pip`.
- mediapipe must stay `<0.10.30` (legacy `mp.solutions` API removed after).
- Vision pose extraction DOES NOT WORK in the iOS simulator (error 9 every
  frame; no workaround). Camera-path testing needs a physical device.
  Simulator testing uses DEBUG launch args and the unit/parity tests.
  Launch args: `-demoResults` (unsaved demo Results), `-demoResultsSaved`
  (seeds the store, opens a saved session — label/compare/NEW BEST rows),
  `-demoCompare`, `-demoReport`, `-demoReview` (post-recording clip review,
  otherwise only reachable by recording), `-openHistory`, `-openDrills [issue]`,
  `-openAbout`, `-openTakes` (unfinished-takes recovery screen),
  `-seedUnfinishedTakes` (replaces the waiting takes with two back-dated
  clips), `-seedTrainingLog` (deterministic 3-week fixture; wipes
  the store), `-analyzeDocs <file>` (file from the app's Documents dir).
- `iOS/SwimCoach/Resources/swim_test.mp4` is a synthetic cartoon — it
  validates plumbing, not model accuracy.
- The CLI gate (`ml/analysis/gating.py`) mirrors iOS `PoseAnalyzer` filters;
  keep thresholds in sync when touching either.
- Signing: personal team `4VH58A4KM6` lives in `project.yml`. Device installs
  need `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`.

## Workflow

Never commit to `main` directly — branch, open a PR, and let CI
(python-tests + ios-tests) go green before merging. Model-weight changes
belong in their own PR with training metrics in the description.

## Release cycle (applies to every feature)

Features ship as releases, not loose merges:
1. Feature branch → PR (must include a CHANGELOG.md entry under the target
   version) → CI green → squash-merge.
2. When a version's scope is complete: bump MARKETING_VERSION /
   CURRENT_PROJECT_VERSION in `iOS/project.yml` (+ `xcodegen generate`),
   finalize the CHANGELOG section with the date.
3. Tag `vX.Y.Z` on the release commit and create a GitHub release whose
   notes are that CHANGELOG section.
4. Deploy = install the tagged build on the device/simulator and verify the
   headline feature works before calling it shipped.
Semver: features bump minor, fixes bump patch, model-contract or data-format
breaks bump major.
