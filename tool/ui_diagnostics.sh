#!/usr/bin/env sh
# Prints what the emulator shows and what the app logged, for a run of the UI flows that
# failed: whether the app's process runs, the focused window, the texts on screen, what
# Android recorded of apps not responding or killed, and the app's log lines. The `ui`
# job of ci.yml runs it when `maestro test` fails, so the step log explains the failure
# without the artifact.
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
echo "== not responding, crashes and kills, oldest first"
adb logcat -d -b events -v time | grep -E "am_anr|am_crash|am_kill.*$pkg" |
  grep -vE "due to (clear data|installPackageLI)" | head -n 40
adb logcat -d -v time |
  grep -E "ANR in|Reason: Input|Destroy timeout|failed to attach" | head -n 40
echo "== app log"
adb logcat -d -v time |
  grep -E "flutter|AndroidRuntime|FATAL|ANR in|not responding|$pkg" | tail -n 300
# The stack traces Android keeps of the last "not responding" show what blocked that app.
echo "== newest not-responding trace"
if adb root >/dev/null 2>&1; then
  adb wait-for-device
  adb shell 'f=$(ls -t /data/anr 2>/dev/null | head -n 1); [ -n "$f" ] && head -n 150 "/data/anr/$f" || echo none'
else
  echo "no root"
fi
