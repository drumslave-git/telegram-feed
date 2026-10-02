#!/usr/bin/env sh
# Closes what a fresh emulator's boot can leave on screen before the UI flows start. The
# emulator runner presses a key right after boot; when the launcher has no window yet,
# Android answers with "Pixel Launcher isn't responding", a dialog that stays over every
# flow until someone closes it. It appears some seconds after boot, so for 30 s every
# not-responding dialog is closed with the "close system dialogs" broadcast.
end=$(($(date +%s) + 30))
while [ "$(date +%s)" -lt "$end" ]; do
  if adb shell dumpsys window | grep -q "Application Not Responding"; then
    adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null
    echo "closed a not-responding dialog"
  fi
  sleep 2
done
