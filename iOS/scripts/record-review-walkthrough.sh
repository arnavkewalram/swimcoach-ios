#!/usr/bin/env bash
# Records the App Review walkthrough on a connected iPhone.
#
# App Review asks new developer accounts for a screen recording on a physical
# device that begins with launching the app (Guideline 2.1, Information
# Needed). This builds the app, drives AppReviewWalkthroughUITests with
# XCTest's own screen recording on, and writes that recording out as an .mp4.
#
# XCTest records, not `devicectl device capture screen-record`: devicectl
# reports "Screen Recording is not supported by this device" on an iOS 26
# iPhone, while XCTest records the same phone fine (variable frame rate —
# ~30 fps while the screen moves, held frames while it is still).
#
# The app under test is a RELEASE build: the Debug build's Home carries a
# DEV TOOLS panel that must not appear in footage sent to Apple. Xcode cannot
# run the scheme's tests in Release (the unit tests use DEBUG-only fixtures),
# so the UI tests are built normally and their test plan is repointed at a
# separately built Release app.
#
# Prerequisites on the phone: Developer Mode, and Settings → Developer →
# UI Automation on. Keep it unlocked and untouched while this runs.
#
# Usage: iOS/scripts/record-review-walkthrough.sh <device-udid> [output.mp4]
set -euo pipefail

udid="${1:?usage: $0 <device-udid> [output.mp4]}"
out="$(cd "$(dirname "${2:-.}")" && pwd)/$(basename "${2:-SwimCoach-walkthrough.mp4}")"
cd "$(dirname "$0")/.."

derived="build/review-recording"
products="$derived/Build/Products"
signing=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration)

echo "▸ Building the UI test runner"
xcodebuild build-for-testing -quiet -project SwimCoach.xcodeproj -scheme SwimCoach \
  -destination "id=$udid" -derivedDataPath "$derived" "${signing[@]}"

echo "▸ Building the app in Release"
xcodebuild build -quiet -project SwimCoach.xcodeproj -scheme SwimCoach \
  -configuration Release -destination "id=$udid" -derivedDataPath "$derived" "${signing[@]}"

echo "▸ Pointing the UI test plan at the Release app"
python3 - "$products" <<'PY'
import glob, plistlib, sys
products = sys.argv[1]
source = next(p for p in glob.glob(f"{products}/SwimCoach_*.xctestrun")
              if not p.endswith("ReviewRecording.xctestrun"))
plan = plistlib.load(open(source, "rb"))
ui = plan["SwimCoachUITests"]
release_app = "__TESTROOT__/Release-iphoneos/SwimCoach.app"
ui["UITargetAppPath"] = release_app
# Only the runner and the Release app get installed — a Debug copy of the
# app listed here would be installed over the Release one.
ui["DependentProductPaths"] = [
    p for p in ui.get("DependentProductPaths", []) if "UITests-Runner" in p
] + [release_app]
# Record the screen, and keep the recording even though the test passes.
ui["PreferredScreenCaptureFormat"] = "screenRecording"
ui["SystemAttachmentLifetime"] = "keepAlways"
trimmed = {"SwimCoachUITests": ui}
if "__xctestrun_metadata__" in plan:
    trimmed["__xctestrun_metadata__"] = plan["__xctestrun_metadata__"]
plistlib.dump(trimmed, open(f"{products}/ReviewRecording.xctestrun", "wb"))
PY

echo "▸ Running the walkthrough (recording)"
result="$derived/walkthrough.xcresult"
rm -rf "$result"
status=0
xcodebuild test-without-building -quiet \
  -xctestrun "$products/ReviewRecording.xctestrun" -destination "id=$udid" \
  -resultBundlePath "$result" \
  -only-testing:SwimCoachUITests/AppReviewWalkthroughUITests || status=$?

if [[ $status -ne 0 ]]; then
  echo "✗ The walkthrough failed (exit $status) — not exporting a recording." >&2
  echo "  Result bundle: $result" >&2
  exit "$status"
fi

echo "▸ Extracting the recording"
attachments="$derived/attachments"
rm -rf "$attachments" && mkdir -p "$attachments"
xcrun xcresulttool export attachments --path "$result" --output-path "$attachments" >/dev/null
python3 - "$attachments" "$out" <<'PY'
import json, shutil, sys
folder, out = sys.argv[1], sys.argv[2]
manifest = json.load(open(f"{folder}/manifest.json"))
videos = [a for test in manifest for a in test["attachments"]
          if a["suggestedHumanReadableName"].startswith("Screen Recording")
          and a["exportedFileName"].endswith(".mp4")]
if len(videos) != 1:
    sys.exit(f"expected one screen recording in the result bundle, found {len(videos)}")
shutil.copyfile(f"{folder}/{videos[0]['exportedFileName']}", out)
PY
echo "✓ $out"
