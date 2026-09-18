# telegram-feed

A custom Telegram client for *reading*, not chatting. Combine channels into feeds, get notifications from keyword rules instead of a per-chat mute switch, and have posts read aloud.

Status: phases 1 to 3 done (Android MVP, keyword rules and read-aloud, reactions, comments, share). Stabilisation next. Web was built and dropped (see `docs/ARCHITECTURE.md`).

- [Product spec](docs/SPEC.md): what the app does, user stories, phases, resolved decisions.
- [Architecture](docs/ARCHITECTURE.md): Flutter + TDLib design, data model, rule engine, platform notes, phase 0 spikes.

## Tests

```bash
tool/ci.sh                                              # analyze, format check, unit and widget tests (incl. goldens)
cd app && flutter test --update-goldens test/goldens_test.dart   # after intentional UI changes
cd app && flutter test integration_test -d emulator-5554 --dart-define=TG_API_ID=... --dart-define=TG_API_HASH=...
```

The integration test drives the real app on the emulator; the feed flow runs only when the
emulator's account is logged in (it says so and passes otherwise).

## Releases (closed beta)

Pushing a tag `v*` runs `.github/workflows/release.yml`: it downloads the prebuilt TDLib for the
pinned commit, builds signed release APKs per ABI and attaches them to a GitHub release.
Required repository secrets: `TG_API_ID`, `TG_API_HASH`, `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

Create the keystore once, locally, and keep it out of git:

```bash
keytool -genkey -v -keystore telegram-feed-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -w0 telegram-feed-upload.jks   # value for ANDROID_KEYSTORE_BASE64
```

For a local signed build put the keystore path and passwords in `app/android/key.properties`
(`storeFile`, `storePassword`, `keyAlias`, `keyPassword`); without that file release builds are
signed with the debug key.

## License

GPL-3.0. See [LICENSE](LICENSE).

## Repository layout

Dart pub workspace (run `flutter pub get` once at the root).

```
app/                    Flutter application (Android)
packages/core           core isolate: services, timeline, rule engine, TTS/notifier proxies
packages/telegram_gateway  TelegramGateway + TDLib FFI implementation
packages/app_db         Drift schema for feeds, sources, read marks, settings
packages/rules          rule AST, parser, evaluator (pure Dart)
packages/tdlib_bindings generated TDLib JSON types
tool/tdlib              Docker build of libtdjson.so from the pinned TDLib commit
tool/ci.sh              what CI runs: analyze, format check, package and app tests
docs/                   spec, architecture, plan, spike outcomes
```

## Stack

- Flutter (Android)
- TDLib via `dart:ffi`
- Drift (SQLite) for app data
- Device text-to-speech via `flutter_tts`

## Running

Telegram API credentials are not in the repo. Obtain `api_id` and `api_hash` at https://my.telegram.org (TDLib's public example credentials work for development builds but are rate-limited and sometimes rejected with `API_ID_INVALID`; do not ship with them) and pass them at build time:

```bash
flutter pub get                       # once, at the repo root (pub workspace)
dart tool/fetch_tdlib.dart            # prebuilt libtdjson.so for the pinned TDLib commit
cd app && flutter run --dart-define=TG_API_ID=12345 --dart-define=TG_API_HASH=abcdef...
```

Without a GitHub release yet, build the binary locally with Docker (`tool/tdlib`) and run
`dart tool/fetch_tdlib.dart --local`.
