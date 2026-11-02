#!/usr/bin/env bash
set -uo pipefail
mkdir -p verification-output/screenshots
adb shell mkdir -p /sdcard/Download/reloaded-ui
adb shell wm size 1080x2340
adb shell wm density 420
adb shell settings put system font_scale 1.0
# Test the actual launcher, with no live download/update popups during the UI flow.
adb shell svc wifi disable
adb shell svc data disable
gradle --no-daemon -p android :app:connectedDebugAndroidTest -PcontrolsBuild=true -PtargetAbi=x86_64
result=$?
adb pull /sdcard/Download/reloaded-ui/. verification-output/screenshots/ || true
adb logcat -d -s AndroidRuntime > verification-output/android-runtime.txt
exit "$result"
