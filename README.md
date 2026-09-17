# telegram-feed

A custom Telegram client for *reading*, not chatting. Combine channels into feeds, get notifications from keyword rules instead of a per-chat mute switch, and have posts read aloud.

Status: phase 0 spikes done (TDLib FFI on Android, foreground-service core isolate, timeline performance, tdweb on web; see `docs/spikes/`). Phase 1 (Android MVP) starts next.

- [Product spec](docs/SPEC.md): what the app does, user stories, phases, resolved decisions.
- [Architecture](docs/ARCHITECTURE.md): Flutter + TDLib design, data model, rule engine, platform notes, phase 0 spikes.

## License

GPL-3.0. See [LICENSE](LICENSE).

## Repository layout

Dart pub workspace (run `flutter pub get` once at the root).

```
app/                    Flutter application (Android, web)
packages/core           core isolate: services, timeline, rule engine, TTS/notifier proxies
packages/telegram_gateway  TelegramGateway + TDLib FFI and tdweb implementations
packages/app_db         Drift schema for feeds, sources, read marks, settings
packages/rules          rule AST, parser, evaluator (pure Dart)
packages/tdlib_bindings generated TDLib JSON types
tool/tdlib, tool/tdweb  Docker builds of libtdjson.so and tdweb from the pinned TDLib commit
tool/ci.sh              what CI runs: analyze, format check, package and app tests
docs/                   spec, architecture, plan, spike outcomes
```

## Stack

- Flutter (Android first, then web)
- TDLib via `dart:ffi` on mobile, tdweb on web
- Drift (SQLite) for app data
- Device text-to-speech via `flutter_tts`

## Running

Telegram API credentials are not in the repo. Obtain `api_id` and `api_hash` at https://my.telegram.org and pass them at build time:

```bash
flutter pub get                       # once, at the repo root (pub workspace)
dart tool/fetch_tdlib.dart            # prebuilt libtdjson.so + tdweb for the pinned TDLib commit
cd app && flutter run --dart-define=TG_API_ID=12345 --dart-define=TG_API_HASH=abcdef...
```

Without a GitHub release yet, build the binaries locally with Docker (`tool/tdlib`, `tool/tdweb`)
and run `dart tool/fetch_tdlib.dart --local`.
