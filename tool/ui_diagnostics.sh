#!/usr/bin/env sh
# Prints what the emulator shows and what the app logged, for a run of the UI flows that
# failed: whether the app's process runs, the focused window, the texts on screen and the
# app's log lines. The `ui` job of ci.yml runs it when `maestro test` fails, so the step
# log explains the failure without the artifact.
pkg=dev.telegramfeed.telegram_feed
echo "== process"
adb shell pidof "$pkg" || echo "not running"
echo "== focused window"
adb shell dumpsys window | grep -E 'mCurrentFocus|mFocusedApp'
echo "== on screen"
if adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1; then
  adb shell cat /sdcard/window.xml | tr '>' '\n' |
    grep -oE '(text|content-desc)="[^"]+"' | head -n 80
else
  echo "no view hierarchy"
fi
echo "== app log"
adb logcat -d -v time |
  grep -E "flutter|AndroidRuntime|FATAL|ANR in|not responding|$pkg" | tail -n 300
