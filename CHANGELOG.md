# Changelog

All notable changes to SwimCoach. Format follows Keep a Changelog; versions
follow semver (MARKETING_VERSION in `iOS/project.yml` is the source of truth).

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
