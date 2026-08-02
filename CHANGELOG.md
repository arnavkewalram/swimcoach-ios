# Changelog

All notable changes to SwimCoach. Format follows Keep a Changelog; versions
follow semver (MARKETING_VERSION in `iOS/project.yml` is the source of truth).

## [1.14.0] — 2026-08-01 — "Ready"

### Added
- **Privacy manifest** (`PrivacyInfo.xcprivacy`), required for App Store
  submission: no tracking, no data collection; declares UserDefaults
  (CA92.1) and file-timestamp (C617.1) API use. Bundling is test-enforced.
- **Haptics**: a light tap on record start/stop, and a success tap when an
  analysis finishes and when a session sets a new personal best.

## [1.13.1] — 2026-08-01

### Fixed
- Accessibility-size audit (largest supported Dynamic Type): the Results
  SESSION VIDEO header no longer breaks mid-word — it stacks above its
  controls when the row can't fit; the History score trend no longer
  invents negative session numbers (x-axis pinned to real indices) and
  the average now reads in the caption instead of colliding with axis
  labels in-plot.

## [1.13.0] — 2026-08-01 — "Card"

### Changed
- **Report card shows progress**: the shareable card now carries a
  PROGRESS sparkline of your recent sessions (ending with this one) and a
  NEW BEST chip when the session sets a personal best — shares tell the
  story of improvement, not just one number.

## [1.12.0] — 2026-08-01 — "Journal"

### Added
- **Session notes**: every saved session can carry a free-text training
  note alongside its name. History's rename sheet is now Edit Session
  (name + notes); rows show a one-line note snippet; Results shows a quiet
  NAME THIS SESSION affordance for saved sessions that opens the same
  sheet. Existing stores migrate losslessly (new field defaults empty).

## [1.11.0] — 2026-08-01 — "Level"

### Added
- **Camera level indicator**: a live horizon line under the top bar while
  framing — white with a signed degree readout when tilted, green LEVEL
  within ±2°. A level camera keeps the pose pipeline honest (body-sag
  detection assumes a level horizon). Hidden while recording and on
  devices without motion data.

## [1.10.0] — 2026-08-01 — "Best"

### Added
- **New Best**: when a session beats every previously saved score, the
  Results score panel shows a pine-green NEW BEST chip (and VoiceOver says
  so). Ties and first-ever sessions don't count — there was nothing to beat.
- **About screen** (footer of Home): what the app is, the on-device privacy
  stance, live version/build from the bundle, and the Space Grotesk SIL OFL
  license text — which the license obliges us to ship (test-enforced).

## [1.9.0] — 2026-08-01 — "Goal"

### Added
- **Weekly session goal**: set a target from the training log panel (tap
  SET A WEEKLY GOAL, or the tick row once set) via an editorial stepper
  sheet. The panel shows progress ticks, an overflow count when you swim
  past the goal, and a pine-green GOAL MET chip on completion.

## [1.8.0] — 2026-08-01 — "Drills"

### Added
- **Drill library**: ten authored freestyle drills (goal, numbered steps,
  suggested dose) grouped by focus area — Arms & catch, Body line, Kick &
  timing — as editorial index cards. Every fault the model can detect maps
  to at least one drill (test-enforced).
- Entry points: a Drill library row on Home, and a DRILLS link inside each
  expanded issue on Results that opens the library scrolled to the drills
  fixing that issue, outlined in lane blue.
- DEBUG `-openDrills [issue]` launch argument for screenshot automation.

## [1.7.0] — 2026-08-01 — "Trend"

### Added
- **Training log on Home**: a hairline score sparkline over your recent
  sessions plus a this-week summary (session count, average score) and a
  week-over-week delta chip — progress at a glance, in the editorial
  register. Appears once two or more sessions are saved.
- DEBUG `-seedTrainingLog` launch argument seeds a deterministic three-week
  fixture for simulator screenshots.

## [1.6.1] — 2026-08-01

### Fixed
- The app bundle now carries the real version: XcodeGen's generated
  Info.plist hardcoded 1.0 (1), so every install to date reported 1.0
  regardless of `project.yml`. `CFBundleShortVersionString` /
  `CFBundleVersion` are now mapped to MARKETING_VERSION /
  CURRENT_PROJECT_VERSION.

## [1.6.0] — 2026-08-01 — "Proof"

### Added
- **Skeleton video export**: EXPORT in the Results video header burns the
  detected skeleton into the session video (frame-accurate, lane-blue limbs
  with white joint dots) and hands the file to the system share sheet —
  shareable proof of what the analysis saw. Progress shown inline; export
  cancels automatically if you leave the screen.
- Demo results now include a synthetic skeleton track, so the overlay and
  export are demo-able without a real analysis.

### Fixed
- Export pipeline uses the canonical `requestMediaDataWhenReady` writer pump —
  an 8s clip exports in under a second (a readiness-polling loop took ~10
  minutes; caught by the new end-to-end export test).

## [1.5.0] — 2026-08-02 — "Refine"

### Changed
- Results: bare metrics strip (varied surface hierarchy), quieter quality
  notes (left-bar treatment instead of alarm boxes), tighter rhythm.
- History: summary strip matches the bare editorial treatment.
- Navigation titles across Results/History/Compare set in Space Grotesk —
  the brand typeface now carries through the nav bar.

## [1.4.0] — 2026-08-02 — "Polish"

### Changed
- Home recomposed: stronger masthead with date, hero last-session panel with
  an editorial score gauge, bare record strip (varied surface levels), and
  bottom-anchored actions — the screen now composes across its full height.
- Launch screen matches the paper background (no more white flash).
- Device deployments use Release configuration — no DEV TOOLS in daily use.

## [1.3.0] — 2026-08-02 — "Share"

### Added
- **Report-card export**: every Results screen renders a shareable 1080×1350
  report card in the editorial style (score, grade, metrics, issues) —
  share icon in the toolbar sends it anywhere via the system sheet.

## [1.2.0] — 2026-08-02 — "Progress"

### Added
- **Session comparison**: pick any two sessions from History (Compare mode)
  for a head-to-head view — score and metric deltas plus a per-issue verdict
  (NEW / RESOLVED / IMPROVED / WORSE / SAME) ordered by what needs attention.

## [1.1.0] — 2026-08-02 — "See It"

### Added
- **Issue timeline** ("When it happened"): per-issue intensity bands under the
  session video showing when each fault flared during the swim; tap a band to
  seek the video there.
- **"See it in your video"** on each issue: jumps playback to the 3-second
  window where that issue's model probability peaked, with the skeleton
  overlay running.
- Per-window model probabilities are now stored with each session
  (`issueWindows`), enabling the above; older sessions decode unchanged.

### Fixed
- Kick-rate metric now computes over real elapsed time from observation
  timestamps instead of observation count — no more "0 kicks/min" on sparse
  detections or inflated rates on gappy footage.

## [1.0.0] — 2026-08-02 — Baseline

Everything shipped through PR #9:
- On-device analysis pipeline: Vision pose extraction → input-quality gating →
  time-faithful windowed SwimTCN (CoreML) → scored issues, drills, AI tips.
- Session video playback with time-synced pose-skeleton overlay.
- Editorial "meet sheet" design system (Space Grotesk, paper/ink/lane-blue),
  custom app icon, Dynamic Type, Reduce Motion.
- SwiftData history with score trend and common-issues charts.
- Safety/correctness: pipeline cancellation, honest save-state, camera
  lifecycle fixes, structured logging, orphan video pruning, privacy-safe
  Documents (no file sharing).
- Python pipeline parity: shared model contract, real-footage parity tests,
  input gating, windowed inference; hardened (undeployed) Cloud Run backend.
