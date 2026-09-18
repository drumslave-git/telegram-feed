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

## Releases

**Versions are automatic.** After CI passes on `main`, `.github/workflows/debug-release.yml`
reads the conventional commits since the last `vX.Y.Z` tag (`packages/versioning`): `feat`
raises the minor version, `fix` and `perf` the patch, a breaking change (`feat!:` or a
`BREAKING CHANGE:` footer) the major (the minor while the version is 0.x). Pushes with only
`docs`, `chore`, `test` or `ci` commits release nothing. The workflow tags the commit, builds
debug APKs for `arm64-v8a` and `x86_64`, and publishes them as a prerelease with a changelog.
The first release takes the version from `app/pubspec.yaml`.

Debug APKs are signed with one fixed debug key, so each build installs over the previous one
and Google sign-in keeps working. Repository secrets: `TG_API_ID`, `TG_API_HASH`,
`DEBUG_KEYSTORE_BASE64` (`base64 -w0 ~/.android/debug.keystore`), optional
`GOOGLE_SERVER_CLIENT_ID`. The TDLib binaries come from the release that
`.github/workflows/tdlib.yml` publishes; until it has run once, debug releases fail with a
message saying so.

**Signed release APKs** are made by hand for a version that already exists: run
`.github/workflows/release.yml` with the tag (for example `v0.3.0`). It builds that tag with
the release key and adds the APKs to the same GitHub release, which then stops being a
prerelease. Additional secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`; the release key's SHA-1 needs its own Android
OAuth client for Google Drive sync (see "Google Drive sync" above).

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
cd app && flutter run --dart-define=TG_API_ID=12345 --dart-define=TG_API_HASH=abcdef... \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=...apps.googleusercontent.com   # optional: Google Drive sync
```

Without a GitHub release yet, build the binary locally with Docker (`tool/tdlib`) and run
`dart tool/fetch_tdlib.dart --local`.

### Build-time values

| Flag | Needed for | Where it comes from |
|---|---|---|
| `TG_API_ID`, `TG_API_HASH` | Always. Telegram requires every client app to identify itself | https://my.telegram.org, "API development tools" |
| `GOOGLE_SERVER_CLIENT_ID` | Only for Google Drive sync. Without it the app works and the Sync screen says the build cannot sync | A Google Cloud project of yours, see below |

None of them is committed: a fork must not ship under someone else's identity.

### Google Drive sync (optional)

Sync keeps feeds, rules and settings the same across devices through a hidden app file in the
user's own Google Drive (`docs/ARCHITECTURE.md` section 5.5). Google only lets an app sign users
in if the app is registered, so a build that can sync needs a Google Cloud project:

1. Enable the **Google Drive API** in the project.
2. Configure the OAuth consent screen. Testing mode is enough for personal use; add the Google
   accounts that will sign in as test users. The only scope used is `drive.appdata`.
3. Create an OAuth client of type **Android** with package `dev.telegramfeed.telegram_feed` and
   the SHA-1 of the key that signs the build (one client per key: debug and release differ):
   `keytool -list -v -keystore ~/.android/debug.keystore -storepass android -alias androiddebugkey`.
   This client id is never put in the code; Google matches it by package and signature.
4. Create an OAuth client of type **Web application**, no settings needed. Its client id is the
   value of `GOOGLE_SERVER_CLIENT_ID`. There is no web app or server: Android's sign-in API only
   accepts a web-type id as the project's handle.
