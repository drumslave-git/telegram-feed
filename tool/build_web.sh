#!/usr/bin/env bash
# Builds the static web bundle into app/build/web.
#
#   bash tool/build_web.sh                # needs app/web/{tdweb, *.worker.js, *.wasm, sqlite3.wasm}
#                                         # from `dart tool/fetch_tdlib.dart [--local]`
#   bash tool/build_web.sh --no-assets    # compile only (CI): skips the asset check
#
# Credentials come from the environment: TG_API_ID, TG_API_HASH (never committed).
# Serve app/build/web from a site root (tdweb's worker chunks are loaded from `/`); no
# special headers are needed. For a quick look: python -m http.server -d app/build/web 8090
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" != "--no-assets" ]]; then
  for f in app/web/tdweb/tdweb.js app/web/sqlite3.wasm; do
    [[ -f "$f" ]] || { echo "missing $f: run dart tool/fetch_tdlib.dart [--local]" >&2; exit 1; }
  done
  ls app/web/*.worker.js >/dev/null 2>&1 || { echo "missing app/web/*.worker.js" >&2; exit 1; }
fi

# Drift's database worker, compiled from app/web/drift_worker.dart.
(cd app && dart compile js -O4 -o web/drift_worker.js web/drift_worker.dart >/dev/null)
rm -f app/web/drift_worker.js.deps app/web/drift_worker.js.map

defines=()
[[ -n "${TG_API_ID:-}" ]] && defines+=("--dart-define=TG_API_ID=${TG_API_ID}")
[[ -n "${TG_API_HASH:-}" ]] && defines+=("--dart-define=TG_API_HASH=${TG_API_HASH}")
(cd app && flutter build web --release "${defines[@]}")
echo "web bundle: app/build/web"
