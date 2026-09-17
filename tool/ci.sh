#!/usr/bin/env bash
# Same steps as .github/workflows/ci.yml, runnable locally.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
dart analyze --fatal-infos .
dart format --output=none --set-exit-if-changed app packages tool
for p in packages/*/; do
  echo "== dart test $p"
  (cd "$p" && dart test --reporter=compact)
done
echo "== flutter test app"
(cd app && flutter test)
echo "== flutter build web"
bash tool/build_web.sh --no-assets
