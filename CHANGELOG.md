# Changelog

All notable changes to SwimCoach. Format follows Keep a Changelog; versions
follow semver (MARKETING_VERSION in `iOS/project.yml` is the source of truth).

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
