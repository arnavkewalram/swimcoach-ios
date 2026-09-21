# App Store Connect listing — SwimCoach

Copy-paste source for every text field in App Store Connect. Character limits
are Apple's; the counts in brackets are what these drafts actually use.

---

## Name (30 max)

```
SwimCoach: Stroke Analysis
```
[25] — plain `SwimCoach` is likely taken. Alternates: `SwimCoach — Swim Technique` [26], `SwimCoach Stroke Lab` [20].

## Subtitle (30 max)

```
Film a lap, score your form
```
[27]

## Promotional text (170 max, editable without a new build)

```
Three real swims are built in, so you can see exactly what SwimCoach measures before you ever take it to the pool.
```
[114]

## Description (4000 max)

```
SwimCoach films a freestyle swim and scores its biomechanics — entirely on your iPhone.

Record from the pool deck or import a clip you already have. A neural network reads pose keypoints from every frame, scores three-second windows, and turns them into a 0–100 technique score with a letter grade. You see which faults showed up, exactly when they happened, and which drills address them.

WHAT YOU GET

• A technique score for every swim, with the trend across sessions
• Detected faults — body sag, elbow collapse, knee overbend, kick rate, stroke asymmetry
• A skeleton overlay on your own video, so you can see what the model saw
• An issue timeline: tap a mark to jump to the moment a fault peaked
• Drills matched to the faults you actually have, not a generic list
• Stroke count, stroke rate, kick rate and left/right asymmetry
• Export the overlaid video, or a report card for sharing

TRY IT WITHOUT A POOL

Three real swims ship inside the app — freestyle filmed from the deck and from
underwater. Running one puts it through the identical analysis your own footage
gets. The score and the faults are what the model genuinely found on those
frames. Sample swims stay out of your history, so they cannot move your trends
or your streak.

FILMING THAT WORKS

An on-screen framing guide and a live level indicator help you get a usable
shot: side on, camera at the waterline, whole body in frame.

PRIVATE BY CONSTRUCTION

There is no account and no sign-in. The app makes no network requests at all.
Your videos, the pose data, and every result stay on your iPhone. No analytics,
no tracking, no third-party SDKs.

SwimCoach analyses freestyle technique. It is a training aid, not a medical or
diagnostic tool.
```
[~1500]

## Keywords (100 max total, comma-separated, no spaces)

```
swim,swimming,freestyle,stroke,technique,coach,training,form,analysis,video,pose,drills,lap,triathlon
```
[97] — do not repeat words already in the name or subtitle; Apple indexes those separately.

## Support URL

```
https://arnavkewalram.github.io/swimcoach/support
```

## Marketing URL (optional)

```
https://arnavkewalram.github.io/swimcoach
```

## Privacy Policy URL — required

```
https://arnavkewalram.github.io/swimcoach/privacy
```
Host `docs/privacy-policy.html` at that address before submitting. The URL must
resolve when review runs, or the submission is rejected.

## Copyright

```
2026 Arnav Kewalram
```
App Store Connect prepends the © itself. Note this field is *not* the seller
name — the store will show **Rakhi Chhatani**, the legal entity on the paid
account. See "Attribution" below.

## Age rating

Every questionnaire answer is **None**. Expected result: **4+**.

## Category

Primary **Health & Fitness**. Secondary **Sports**.

---

## App Review Notes — paste verbatim

```
SwimCoach analyses freestyle swimming technique from video, so it normally
requires pool footage.

FOR REVIEW WITHOUT A POOL: tap "Try a sample swim" on the Home screen. The app
ships three real swims, filmed from the deck and from underwater. Running one
performs the identical on-device analysis a user's own recording receives — the
technique score and detected faults are the model's genuine output on those
frames, not canned data.

- No account or login is required. There is no sign-in of any kind, so no demo
  credentials are needed.
- All analysis runs on device. The app makes no network requests.
- Pose detection uses the Vision framework, which does NOT function in the iOS
  Simulator. Please review on physical hardware.
- Camera access records a swim. Microphone audio is captured alongside the
  video so poolside coaching notes are audible on playback; audio is never
  analysed and never leaves the device.
- The bundled sample footage is used under CC BY-SA 4.0 and is credited in the
  app on the sample swims screen.
```

---

## Screenshots

`docs/screenshots/appstore/` — 1320 × 2868 (6.9", iPhone 17 Pro Max), the only
size Apple requires:

| File | Shows |
|---|---|
| `01-home.png` | Score gauge, training log trend, streak, focus fault |
| `02-results.png` | Technique score, skeleton overlay, issue timeline, detected faults |
| `03-report.png` | Shareable report card |
| `04-samples.png` | Sample swims — the screen App Review is pointed at, with real swimmer thumbnails |

Three is the minimum; up to ten are allowed. Worth adding: a fault detail
page with drills.

One caveat — these were captured in the Simulator using the app's demo seed
arguments, so the video frame shows synthetic footage rather than a real
swimmer. The UI is genuine, which is what Apple requires, but screenshots taken
on a device against real footage would sell it better.

---

## Attribution — read before submitting

The App Store "Developer" line shows the legal entity on the paid account:
**Rakhi Chhatani**. That field is not editable, and publishing under someone
else's membership cannot display a different seller name. Showing your own name
there requires your own Apple Developer Program membership.

What you control: the copyright string above, the description, and the app's
own About screen — which currently credits the typeface designer but not you.
