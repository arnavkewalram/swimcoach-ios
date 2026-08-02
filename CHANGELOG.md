# Changelog

All notable changes to SwimCoach. Format follows Keep a Changelog; versions
follow semver (MARKETING_VERSION in `iOS/project.yml` is the source of truth).

## [1.29.1] — 2026-08-02

### Fixed
- Erase All Sessions now also clears drill-practice history, and the
  training-log export includes it (a chronological `practice` list) —
  YOUR DATA covers everything the app stores again.

## [1.29.0] — 2026-08-02 — "Polish"

### Changed
- The weekly streak chip now also lives on Home's training log — the
  motivational number where you see it daily, not just in History.
- What's New highlights refreshed to cover practice tracking and streaks
  for the next update announcement.

## [1.28.0] — 2026-08-02 — "Done"

### Added
- **Drill practice tracking**: every drill card has a MARK DONE button;
  practiced drills show a pine-green "PRACTICED N× · LAST <date>" line.
  The library now remembers what you've actually worked on.

## [1.27.1] — 2026-08-02

### Fixed
- Zero-warning build: the score trend chart's tap mapping moved off the
  deprecated `plotAreaFrame` API.

## [1.27.0] — 2026-08-02 — "Streak"

### Added
- **Weekly streak**: consecutive training weeks shown as a pine-green
  chip on the History consistency strip (from two weeks up). A quiet
  current week doesn't break a run that was alive last week — the streak
  holds until a week actually ends empty.

## [1.26.0] — 2026-08-02 — "News"

### Added
- **What's New sheet**: after an update, Home shows the release
  highlights once — updates announce themselves instead of hiding behind
  data-gated panels. Fresh installs get onboarding instead; automated UI
  flows suppress it via a launch argument.

## [1.25.1] — 2026-08-02

### Fixed
- Demo-analyzed sessions now carry a clip duration, so they show the
  stroke-rate cell like real analyses.
- Erase All Sessions sweeps the video store immediately instead of
  leaving a corrupt-blob leak for the next-launch prune.

## [1.25.0] — 2026-08-02 — "Tempo"

### Added
- **Stroke rate (strokes/min)** on Results and the report card — the
  tempo number coaches actually use. Clip duration is now stored with
  each session; older sessions without it simply don't show the cell.

## [1.24.0] — 2026-08-02 — "Consistent"

### Added
- **Consistency strip in History**: sessions per week over the trailing
  twelve weeks as a mini bar row — empty weeks stay as hairline stubs, so
  gaps in the routine are as visible as the training blocks.

## [1.23.0] — 2026-08-02 — "Smoke"

### Added
- **UI smoke tests in CI**: a new XCUITest target launches every major
  route (Home, demo Results, seeded History, Drills, About, Compare) and
  asserts its landmark content renders — routing crashes and blank
  screens are now caught before merge. Runs in the existing test scheme;
  ~27 s added.

## [1.22.2] — 2026-08-02

### Changed
- Code health: HomeView (757 → 384 lines) and ResultsView (764 → 612)
  split into focused files (TrainingLogPanel, HomeCards, IssueRow,
  ImportedVideo); five dead design-system symbols removed (retired
  atmosphere stubs, gradient separator, unused accent alias). Verified
  pixel-identical by screenshot diff; no behavior change.

## [1.22.1] — 2026-08-02

### Changed
- Onboarding caught up with the product: the welcome page mentions Photos
  import, the setup tips point at the level line, and the closing page
  now promises what the app actually delivers — faults on your video,
  the drill library, trends, goals, and focus.

## [1.22.0] — 2026-08-02 — "Import"

### Added
- **Import from Photos**: an Import a video button under the record CTA
  opens the photo library (videos only) and runs the picked clip through
  the full analysis — most real swim footage is filmed by someone else
  and arrives in Photos, and until now the app was record-only.
- **Cancel during analysis**: a quiet CANCEL in the analyzing screen's
  corner aborts the pipeline cleanly and returns Home.

## [1.21.0] — 2026-08-02 — "Archive"

### Added
- **Your data, portable**: About gains a YOUR DATA section — export the
  whole training log as readable JSON (dates, names, notes, scores,
  metrics, fault names; no heavyweight payloads) via the share sheet,
  or erase every session and its video behind a confirmation. On-device
  now also means you can take it with you.

## [1.20.0] — 2026-08-02 — "Focus"

### Added
- **Focus on Home**: the fault that recurs most across your last five
  sessions (minimum twice — one-offs are noise; ties break toward the
  most recent) gets a panel with its severity mark and a one-tap DRILLS
  FOR THIS link. Sessions now store fault names directly so Home
  aggregates without decoding result blobs; older sessions contribute as
  new ones are saved.

## [1.19.1] — 2026-08-01

### Fixed
- **Stroke and kick metrics now agree across platforms.** The Python
  pipeline reported stroke cycles (average of both arms) while the app
  reported arm strokes (sum) — a ~2× disagreement on the headline number.
  Both now use the watch convention (sum). iOS peak spacing is fps-aware
  (0.4 s strokes / 0.2 s kicks, matching Python) instead of a fixed frame
  count, and synchronized ankle peaks count as one kick on both sides.

## [1.19.0] — 2026-08-01 — "Steady"

### Changed
- **Model retrained with camera-roll augmentation**: synthetic training
  now includes ±6° global roll jitter so a slightly tilted phone can't
  masquerade as body sag — faults must show their temporal signature.
  Synthetic F1 holds at 1.000 on all ten labels; sanity checks (no
  saturation, injection detection, healthy-sequence rejection) all pass.
  CoreML export and real-footage parity fixtures regenerated.

## [1.18.1] — 2026-08-01

### Docs
- Public-facing README (the repo went public with none): product
  overview with screenshots, monorepo layout, quickstart, release-cycle
  summary, font license attribution.
- CLAUDE.md now lists every DEBUG launch argument (the doc had fallen
  eight arguments behind the code).

## [1.18.0] — 2026-08-01 — "Shade"

### Added
- **Dark and tinted app icons** (iOS 18 home-screen appearances): dark
  mode gets a transparent-ground icon with a brighter lane-blue S and
  paper lane rules; tinted mode gets the grayscale glyph set the system
  tints. Same geometry as the light icon — one family, three moods.

## [1.17.0] — 2026-08-01 — "Versus"

### Added
- **Compare from Results**: saved sessions with history get a COMPARE TO
  PREVIOUS SESSION row under the score panel — one tap instead of the
  two-tap Compare picker in History.

### Changed
- Compare's Issues section now explains its numbers ("detection
  strength, % of model confidence").
- DEBUG `-demoResultsSaved` launch argument seeds and opens a saved
  session for screenshot automation.

## [1.16.0] — 2026-08-01 — "Faults"

### Added
- **Issue trends in History**: each fault in Common Issues now carries a
  direction arrow once six or more sessions exist — pine green heading
  down when a fault fades from recent sessions, brick red heading up when
  it's emerging. Rates compare the recent half of your sessions to the
  earlier half with a 25% movement threshold, so noise stays unmarked.

## [1.15.1] — 2026-08-01

### Fixed
- **Python pipeline now applies video rotation metadata.** OpenCV detects
  a phone recording's rotation tag but the pip-wheel ffmpeg backend does
  not apply it by default — MediaPipe was fed sideways frames for
  portrait-shot videos (CLI and Cloud Run backend alike). All readers now
  go through `open_video_capture`, which sets
  `CAP_PROP_ORIENTATION_AUTO` explicitly; verified against a committed
  rotation-tagged fixture. Companion to the iOS-side v1.14.1 fix.

## [1.15.0] — 2026-08-01 — "Find"

### Added
- **History search & filters**: pull down to search sessions by name,
  note, or date; grade chips under SESSIONS narrow the list (empty
  selection = all). Charts keep describing the full history.

## [1.14.1] — 2026-08-01

### Fixed
- **Video rotation metadata is now honored end-to-end.** iPhone camera
  recordings store sensor-native frames plus a rotation transform; the
  pipeline ignored it, so on camera footage Vision analyzed sideways
  frames (degrading detection), the skeleton overlay mismapped, and
  exported videos played rotated. Vision now receives the frame
  orientation, the overlay maps against the true display size, and the
  exporter tags output with the source transform while drawing keypoints
  through the inverse mapping (new `VideoTransform` helper, unit-tested
  for all four orientations). Identity-transform sources — every existing
  test fixture — behave exactly as before.

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
