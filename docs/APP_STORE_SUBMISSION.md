# Submitting SwimCoach to the App Store

Written for this app specifically — real bundle IDs, real blockers, real
values. Work top to bottom; each phase assumes the one above it is done.

Facts this guide relies on:

| | |
|---|---|
| Bundle ID | `com.arnavkewalram.SwimCoach` |
| Team ID | `NH96D7GY86` — the paid Individual team (Rakhi Chhatani). `4VH58A4KM6` is a free Personal Team and cannot publish. |
| Version / build | `1.51.1` / `96` (in `iOS/project.yml`) |
| Deployment target | iOS 17.0, iPhone only, portrait only |
| Network use | None. No accounts, no analytics, no IAP. |

---

## Phase 0 — Clear the blockers

Do not start the submission machinery until these are done. Each one either
fails the upload or draws a rejection.

### 0.1 Sample-clip licence — resolved (v1.51.1)

The bundled footage is three clips by *It is a wonderful world* on Wikimedia
Commons (`File:Front Crawl Above Water.webm`, `File:Front Crawl
Underwater.webm`, `File:Sprint Front Crawl Underwater.webm`), all **CC BY-SA
4.0** — verified against the Commons `extmetadata` API on 2026-09-19. The
catalog, the unit tests, the UI tests, `project.yml` and the CHANGELOG now
agree, and the in-app credit states that the clips were trimmed and rescaled,
which ShareAlike §3(a)(1)(B) requires for modified material.

ShareAlike attaches to the *clips* (they are separable adaptations), not to
the app around them; distributing them under the same licence, with the
credit and the licence link on the screen that plays them, discharges it.

If you ever swap footage again, confirm the licence at the source first:

```bash
curl -s "https://commons.wikimedia.org/w/api.php?action=query&titles=File:<name>&prop=imageinfo&iiprop=extmetadata&format=json"
```

### 0.2 Get the test suite green

```bash
cd iOS && xcodegen generate
xcodebuild test -project SwimCoach.xcodeproj -scheme SwimCoach \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Green as of v1.51.1 (2026-09-19). CI runs the same suite on every PR; do not
upload a build from a red branch.

### 0.3 Commit, push, merge

`fix/app-store-readiness` carries the sample-swim feature, the v1.51.0 and
v1.51.1 release commits and all the App Store configuration. Open the PR,
let CI go green, squash-merge, then tag `v1.51.1` on `main` and cut the
GitHub release from the CHANGELOG section — the release cycle in
`CLAUDE.md`. Archive from the tagged commit so the build in the store is
the build in git.

---

## Phase 1 — Identity and certificates (one time)

### 1.1 Confirm the membership is active

<https://developer.apple.com/account> → Membership. It must say **Apple
Developer Program**, active, not expired. A free/personal team cannot submit.

### 1.2 Apple Distribution certificate — done

This machine now has:

```
Apple Distribution: Rakhi Chhatani (NH96D7GY86)
```

which is the one a Release archive signs with (`project.yml` sets
`DEVELOPMENT_TEAM: NH96D7GY86`, automatic signing). If it ever disappears —
new Mac, expired, revoked — Xcode will make another:

> Xcode → Settings → Accounts → select your Apple ID → **Manage Certificates**
> → **+** → **Apple Distribution**

Needs Admin or Account Holder role if the team has more than one member.

Verify:

```bash
security find-identity -v -p codesigning | grep "Apple Distribution"
```

### 1.3 Register the App ID

<https://developer.apple.com/account/resources/identifiers> → **+** →
App IDs → App → Bundle ID **Explicit** → `com.arnavkewalram.SwimCoach`.

Leave every capability off. SwimCoach uses none — no push, no iCloud, no
sign-in, no background modes. Enabling one you do not use creates an
entitlement mismatch at upload.

---

## Phase 2 — Create the App Store Connect record

<https://appstoreconnect.apple.com> → My Apps → **+** → New App.

| Field | Notes |
|---|---|
| Platform | iOS |
| Name | 30 chars, **globally unique across the whole store**. "SwimCoach" is a plausible collision — have alternates ready ("SwimCoach — Stroke Analysis"). This is the name users see. |
| Primary language | English (U.S.) |
| Bundle ID | Pick the one registered in 1.3 |
| SKU | Internal only, never shown. `SWIMCOACH-001` is fine. |
| User access | Full Access |

The name is not permanently locked, but it can only be changed while no
version is in review.

---

## Phase 3 — Prepare metadata and assets

All of this is entered in App Store Connect, not in the repo. Everything here
is required before the Submit button activates.

### 3.1 Privacy policy URL — live

Required for **every** app, including ones that collect nothing, and it must
resolve when you submit and for as long as the app is on sale.

<https://arnavkewalram.github.io/swimcoach-site/privacy/> — GitHub Pages from
the public [swimcoach-site](https://github.com/arnavkewalram/swimcoach-site)
repo (also serves the support and marketing URLs). It is a separate repo on
purpose: Pages on a free plan stops working the day a repo goes private, and
this one is slated to. The policy describes what the app does — video and
results stay on the device, no account, no network transmission, no
analytics, no third-party SDKs — and `docs/privacy-policy.html` here mirrors
it.

### 3.2 App Privacy questionnaire

App Store Connect → your app → App Privacy.

Answer **"Data Not Collected."** This has to match
`iOS/SwimCoach/PrivacyInfo.xcprivacy`, which declares no tracking and no
collected data types. A mismatch between the manifest and the label is
something Apple checks.

### 3.3 Screenshots — required

Minimum one size, 3–10 images:

| Display | Pixels | Required? |
|---|---|---|
| 6.9" (iPhone 17 Pro Max) | 1320 × 2868 | Yes — covers all modern iPhones |
| 6.5" | 1242 × 2688 | Optional fallback |

`docs/screenshots/*.png` are 420×913 development captures and **cannot** be
used. Capture fresh from the iPhone 17 Pro Max simulator:

```bash
xcrun simctl boot "iPhone 17 Pro Max"
xcrun simctl io booted screenshot shot.png
```

Note that Vision pose extraction does not run in the simulator, so live
analysis output has to be captured on a physical device.

Show the real UI. Marketing frames and captions are allowed; a screenshot that
does not depict the actual app is Guideline 2.3.

### 3.4 Text

| Field | Limit | Notes |
|---|---|---|
| Subtitle | 30 | Appears under the name |
| Promotional text | 170 | Editable without a new build |
| Description | 4000 | What it does. No pricing talk, no competitor names, no "beta". |
| Keywords | 100 total | Comma-separated, no spaces. Do not repeat the app name or words already in the title. |
| Support URL | — | Required. A GitHub Pages page or repo issues URL works. |
| Marketing URL | — | Optional |

**Avoid medical framing.** SwimCoach analyzes technique. Wording that implies
injury prevention, diagnosis, or treatment moves it toward Guideline 1.4.1
(physical harm) and invites demands for clinical evidence. "Detects stroke
faults and maps them to drills" is safe; "prevents shoulder injury" is not.

### 3.5 Age rating

Questionnaire under the app's General Information. Every answer is None for
this app; it should come out **4+**.

### 3.6 App Review notes — the highest-leverage field for this app

**App Review does not have a swimming pool.** A reviewer who opens SwimCoach,
is asked to film a swim, and cannot, files it as non-functional under
Guideline 2.1. This is the single most likely rejection for this app, well
above anything in the Info.plist.

Your v1.51.0 "Try a sample swim" feature is exactly the mitigation — but only
if you point at it. Paste into App Review Notes:

> SwimCoach analyzes freestyle swimming technique from video, so it normally
> requires pool footage.
>
> For review, tap **"Try a sample swim"** on the Home screen. The app ships
> three real swims (deck and underwater). Running one performs the identical
> on-device analysis a user's own recording receives — the technique score and
> detected faults are the model's genuine output on those frames, not canned
> data.
>
> - No account or login is required; there is no sign-in of any kind.
> - All analysis runs on device. The app makes no network requests.
> - Pose detection uses the Vision framework, which **does not function in the
>   iOS Simulator** — please review on physical hardware.
> - Camera access is used to record a swim; microphone audio is captured with
>   the video so poolside coaching notes are audible on playback, and is never
>   analyzed.

No demo account is needed — say so explicitly rather than leaving the field
blank, which reads as an oversight.

---

## Phase 4 — Build and upload

### 4.1 Bump the build number

App Store Connect rejects a build number it has already seen. In
`iOS/project.yml`, increment `CURRENT_PROJECT_VERSION` (currently `96`) for
**every** upload, including re-uploads after a failure. `MARKETING_VERSION`
only changes when the user-facing version does.

```bash
cd iOS && xcodegen generate   # required after ANY project.yml change
```

### 4.2 Archive

```bash
cd iOS
xcodebuild archive -project SwimCoach.xcodeproj -scheme SwimCoach \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/SwimCoach.xcarchive
```

Release configuration compiles clean (`** ARCHIVE SUCCEEDED **`, verified);
the only warnings are deprecated synchronous `AVAsset` APIs in
`PoseAnalyzer.swift`, which do not block submission.

Do **not** pass `CODE_SIGNING_ALLOWED=NO` — that was only for verifying
compilation without certificates. A real archive must be signed.

### 4.3 Upload

Use the Xcode UI for a first submission; it handles signing and reports
errors far better than the CLI.

> Xcode → Window → **Organizer** → select the archive → **Distribute App**
> → **App Store Connect** → **Upload** → Automatically manage signing

Processing takes 15–60 minutes. You get an email when the build finishes
processing or is rejected outright (which happens before human review, for
things like missing icons or invalid entitlements).

### 4.4 Export compliance

Already handled — `ITSAppUsesNonExemptEncryption: false` is declared in
`project.yml`, so App Store Connect will not stop and ask on each upload.

---

## Phase 5 — Submit

1. App Store Connect → your app → the version → **Build** → select the
   processed build.
2. Confirm every section has a green check.
3. **Add for Review** → **Submit for Review**.

Choose whether to release automatically on approval or manually. Manual is
better for a first release — you decide when it goes live.

### What to expect

- Review is typically 24–48 hours; first submissions get more scrutiny.
- Expect at least one round trip. That is normal, not a failure.
- Rejections arrive in App Store Connect with a guideline number and usually a
  screenshot.

### If rejected

Read the guideline number. If it is a misunderstanding — likely here, given
the "needs a pool" problem — reply in Resolution Center and explain, pointing
again at the sample-swim path. You do not need a new build to reply.

If it needs a code change: fix, bump `CURRENT_PROJECT_VERSION`, archive,
upload, resubmit.

---

## Already done

Verified in this repo, so you do not need to re-check:

- `ITSAppUsesNonExemptEncryption: false` — no export-compliance prompt per upload
- `NSPhotoLibraryUsageDescription` removed — the picker is out-of-process and
  the permission was never exercised
- `NSMicrophoneUsageDescription` explains the use, not just the capture
- Camera-denied state offers **Open Settings** instead of a dead end
- `PrivacyInfo.xcprivacy` ships, declares no tracking/collection, and its
  required-reason codes match the APIs in use
- App icon set complete (1024 + dark + tinted)
- Launch screen declared; orientation matches the iPhone-only device family
- `UIFileSharingEnabled: false` — users' swim videos stay out of Files
- Release archive builds clean
- `iOS/SwimCoachTests/AppStoreConfigurationTests.swift` pins all of the above
  against the built bundle, so a regression fails a test rather than a review
