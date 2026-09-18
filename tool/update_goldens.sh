#!/usr/bin/env bash
# Regenerates app/test/goldens on Linux, the platform CI compares them on. Golden images
# rendered on Windows or macOS differ by more than the CI tolerance.
#
#   bash tool/update_goldens.sh            # needs Docker
#
# Uses the official Dart image plus Flutter from source at the version CI pins.
set -euo pipefail
cd "$(dirname "$0")/.."
FLUTTER_VERSION=$(grep -m1 'flutter-version:' .github/workflows/ci.yml | awk '{print $2}')
root=$(pwd -W 2>/dev/null || pwd)
MSYS_NO_PATHCONV=1 docker run --rm \
  -v "$root:/src:ro" -v "$root/app/test/goldens:/goldens" \
  dart:stable bash -c "
    set -e
    apt-get update -qq >/dev/null
    apt-get install -y -qq git curl unzip xz-utils zip libglu1-mesa rsync >/dev/null
    git clone -q --depth 1 -b $FLUTTER_VERSION https://github.com/flutter/flutter.git /flutter
    export PATH=/flutter/bin:\$PATH
    git config --global --add safe.directory '*'
    rsync -a --exclude build --exclude .dart_tool --exclude .git /src/ /work/
    cd /work && flutter pub get >/dev/null 2>&1
    cd app && flutter test --update-goldens test/goldens_test.dart | tail -1
    cp test/goldens/*.png /goldens/
    flutter test 2>&1 | tail -1
  "
