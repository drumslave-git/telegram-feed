#!/usr/bin/env bash
# Runs the Maestro UI flows against the fake build of the app on the connected emulator.
#
#   tool/maestro.sh                    build the fake app, install it, run every flow
#   tool/maestro.sh --no-build         run the flows against what is installed
#   tool/maestro.sh ... feed.yaml      run these flow files instead of the whole folder
#   MAESTRO_DEVICE=emulator-5556 ...   the emulator to use when several are running
#
# Needs an emulator that adb sees, the Maestro CLI on PATH and Java 17+ in JAVA_HOME. The
# flows clear the app's data, so the emulator must not hold a session worth keeping.
set -euo pipefail
cd "$(dirname "$0")/.."
build=true
if [ "${1:-}" = "--no-build" ]; then
  build=false
  shift
fi
device=${MAESTRO_DEVICE:-}
if $build; then
  (cd app && flutter build apk --debug --dart-define=TG_FAKE=true --target-platform android-x64)
  adb ${device:+-s "$device"} install -r app/build/app/outputs/flutter-apk/app-debug.apk
fi
mkdir -p build
flows=("$@")
if [ ${#flows[@]} -eq 0 ]; then
  flows=(app/maestro)
fi
maestro ${device:+--device "$device"} test --format junit --output build/maestro-report.xml "${flows[@]}"
