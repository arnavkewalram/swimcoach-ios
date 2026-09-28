#!/bin/sh
# The SwimCoach scheme's test pre-action: change the destination simulator's
# appearance once from the host, so `XCUIDevice.shared.appearance` works.
#
# On a simulator's first boot, XCUIDevice.appearance is silently dropped.
# testmanagerd writes the preference, waits two seconds for the system style
# to follow, logs "Timed out waiting for current user interface style to
# update", and XCTest reports success anyway. Nothing inside the simulator
# recovers it for the rest of that boot: not polling, not relaunching the
# app, not Settings' own Dark Appearance switch. A reboot does, and so does a
# single real change made through CoreSimulator (`simctl ui`), which is what
# this does: away from the current appearance and back again.
#
# Without it, SampleSwimsUITests' dark-appearance test fails on every freshly
# created simulator until that simulator has been rebooted. It looks like
# "fails once, then passes" only because xcodebuild shuts down a simulator it
# booted itself, so the next run is a second boot.
#
# `test-without-building -xctestrun` does not run scheme pre-actions; run this
# by hand first there: TARGET_DEVICE_IDENTIFIER=<udid> \
#   TARGET_DEVICE_PLATFORM_NAME=iphonesimulator scripts/prime-simulator-appearance.sh
#
# Best effort by design: it never fails the test run, and does nothing for a
# physical device.

[ "${TARGET_DEVICE_PLATFORM_NAME:-}" = "iphonesimulator" ] || exit 0
udid="${TARGET_DEVICE_IDENTIFIER:-}"
[ -n "$udid" ] || exit 0

# Booting here is harmless when xcodebuild has already done it. `bootstatus`
# waits for as long as a boot takes, so it gets a watchdog: a wedged simulator
# should fail the run in xcodebuild, not hang it here. (No `timeout` on stock
# macOS.) The watchdog's output is detached so it cannot hold xcodebuild's
# pipe open after this script exits.
xcrun simctl boot "$udid" >/dev/null 2>&1
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 &
boot_wait=$!
(sleep 180; kill "$boot_wait") >/dev/null 2>&1 &
watchdog=$!
wait "$boot_wait" 2>/dev/null
booted=$?
{ kill "$watchdog" && wait "$watchdog"; } 2>/dev/null
if [ "$booted" -ne 0 ]; then
    echo "prime-simulator-appearance: $udid did not finish booting; appearance not primed" >&2
    exit 0
fi

current=$(xcrun simctl ui "$udid" appearance 2>/dev/null)
case "$current" in
    light) other=dark ;;
    dark) other=light ;;
    *) exit 0 ;;  # "unsupported", or the query failed
esac

xcrun simctl ui "$udid" appearance "$other" &&
    sleep 2 &&
    xcrun simctl ui "$udid" appearance "$current"
exit 0
