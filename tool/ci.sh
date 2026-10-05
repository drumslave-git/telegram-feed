#!/usr/bin/env bash
# Same steps as .github/workflows/ci.yml, runnable locally.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
dart analyze --fatal-infos .
dart format --output=none --set-exit-if-changed app packages tool
for p in packages/*/; do
  echo "== dart test $p"
  # A Flutter plugin among them (push_runner) needs flutter test.
  if grep -q "sdk: flutter" "$p/pubspec.yaml"; then
    (cd "$p" && flutter test --reporter=compact)
  else
    (cd "$p" && dart test --reporter=compact)
  fi
done
echo "== flutter test app"
(cd app && flutter test)
