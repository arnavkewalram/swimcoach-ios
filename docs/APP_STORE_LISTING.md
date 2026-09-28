# App Store Connect listing — SwimCoach

Copy-paste source for every text field in App Store Connect. Character limits
are Apple's; the counts in brackets are what these drafts actually use.

---

## Name (30 max)

```
SwimCoach: Stroke Analysis
```
[25] — **registered 2026-09-21**; this is the name on the App Store Connect record. (Plain `SwimCoach` was the likely collision. Unused alternates: `SwimCoach — Swim Technique` [26], `SwimCoach Stroke Lab` [20].)

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
swim,swimming,freestyle,technique,coach,training,video,pose,drills,triathlon,swimmer,fitness,kick
```
[97] — this is the string entered in App Store Connect. The previous draft
(`…,stroke,…,form,analysis,…,lap,…`) was **101 characters, one over the limit**,
and spent four slots on words already in the name and subtitle, which Apple
indexes separately. Dropping those four freed room for `swimmer`, `fitness`
and `kick`.

## Support URL

```
https://arnavkewalram.github.io/swimcoach-site/support/
```

## Marketing URL (optional)

```
https://arnavkewalram.github.io/swimcoach-site/
```

## Privacy Policy URL — required

```
https://arnavkewalram.github.io/swimcoach-site/privacy/
```
Live — served by GitHub Pages from the public
[swimcoach-site](https://github.com/arnavkewalram/swimcoach-site) repo, which
is deliberately separate from this one so the URL survives this repo going
private. `docs/privacy-policy.html` here is a mirror; edit both when the
policy changes. The URL must keep resolving for as long as the app is on the
store.

## Copyright

```
2026 Arnav Kewalram
```
App Store Connect prepends the © itself. Note this field is *not* the seller
name — the store will show **Rakhi Chhatani**, the legal entity on the paid
account. See "Attribution" below.

## Age rating

Every questionnaire answer is **None**. Expected result: **4+**.

This now includes a set of questions about social-media capabilities. SwimCoach
has no accounts, no messaging, no user-generated content feed and no in-app
browser — the only sharing is the system share sheet, which the user initiates.
All **No**.

## Category

Primary **Health & Fitness**. Secondary **Sports**.

---

## App Review Notes — paste verbatim

Also the reply to App Review for the 2026-09-24 Guideline 2.1 "Information
Needed" request (see `APP_STORE_SUBMISSION.md`). Fill in the iOS version the
recording was made on; the whole block stays under Notes' 4,000 characters.

```
Thank you for reviewing SwimCoach. The information you asked for is below. The same text is in the App Review Notes field.

1. SCREEN RECORDING
Attached: SwimCoach-walkthrough.mp4, recorded on an iPhone 15 running iOS <iOS version the recording was made on>. It starts on the Home Screen with launching the app. It then shows the typical flow: Home, the recording screen, a bundled sample swim analyzed on the device, Results, a detected fault and its drills, and About. The app has no account registration, login or account deletion. It has no user-generated content shared with others and no paid content.

2. PURPOSE AND AUDIENCE
SwimCoach is a technique coach for freestyle (front crawl) swimmers: triathletes, masters and fitness swimmers, and the coaches who film them. Filming a swim is easy; knowing what is wrong with the stroke is not, and coaching is expensive. SwimCoach analyzes a side-on video of a swimmer on the iPhone itself. It returns:
- a 0–100 technique score
- the specific faults detected, such as body sag, elbow collapse, knee overbend, kick rate and left/right asymmetry
- when in the clip each fault occurred
- drills that address each fault
It is a training aid, not a medical or diagnostic tool.

3. SETUP AND ACCESS
No account, login or configuration is needed.
- To see the core feature without a pool: on Home, tap "Try a sample swim" (it's also on Home as "Sample swims"). Choose any of the three bundled clips and tap "Analyze this clip". The app runs the same on-device analysis a user's own recording gets. Results shows the score, the detected faults, an issue timeline, a skeleton overlay on the video and matching drills. Sample results are deliberately not saved to the user's history.
- For a user's own swim: "Analyze a swim" opens the camera (film side-on from the pool deck, 3–6 m from the swimmer), or "Import a video" picks a clip from Photos.
- Pose detection uses Apple's Vision framework, which does not run in the iOS Simulator. Please review on a physical iPhone.

4. EXTERNAL SERVICES
None. The app makes no network requests. It uses no third-party SDKs, analytics, authentication, payment processors, or cloud or third-party AI services. All processing happens on the device, using Apple frameworks:
- Vision: body pose detection.
- Core ML: SwimTCN, a model we trained ourselves and bundle in the app.
- AVFoundation: camera and playback.
- SwiftData: local history.
- Foundation Models: on iPhones where Apple Intelligence is available, Apple's on-device model writes three coaching tips. Elsewhere those tips come from built-in text.

5. REGIONAL DIFFERENCES
The app works the same in all regions. The only variation is the three coaching tips on Results. Apple's on-device model writes them where Apple Intelligence is available for the user's region and language, and built-in text is used otherwise. Scores, detected faults, drills and history are identical everywhere. The app is in English.

6. REGULATION AND THIRD-PARTY MATERIAL
The app is not in a regulated industry. It gives swimming technique feedback, makes no medical, injury-prevention or diagnostic claims, and is not a medical device.
It bundles three short sample videos by "It is a wonderful world", used under Creative Commons Attribution-ShareAlike 4.0 from Wikimedia Commons:
- https://commons.wikimedia.org/wiki/File:Front_Crawl_Above_Water.webm
- https://commons.wikimedia.org/wiki/File:Front_Crawl_Underwater.webm
- https://commons.wikimedia.org/wiki/File:Sprint_Front_Crawl_Underwater.webm
Licence: https://creativecommons.org/licenses/by-sa/4.0/
The Sample Swims screen credits the author, the work and the licence, and links to the licence and to each source page. The Space Grotesk typeface is used under the SIL Open Font License 1.1 and credited in About.

ALSO IN THIS BUILD
Build 97 fixes an issue we found in our own device testing. Results for a sample swim wrongly said "a storage error occurred". It now says that samples are not saved to your history.
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
own About screen, which credits you: "Built by Arnav Kewalram — the app, the
SwimTCN model, and the training pipeline behind it."
