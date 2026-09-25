# telegram-feed

A Telegram client for Android for reading channels, not chatting. Channels combine into feeds, keyword rules decide which posts notify, and posts can be read aloud.

- [Product spec](docs/SPEC.md): what the app does.
- [Architecture](docs/ARCHITECTURE.md): how it is built.
- [Plan](docs/PLAN.md): open work.

## Stack

- Flutter, Android only
- TDLib through `dart:ffi`
- Drift (SQLite) for app data
- Device text-to-speech through `flutter_tts`

## Repository layout

Dart pub workspace: run `flutter pub get` once at the root.

```
app/                       Flutter application
packages/core              core isolate: port protocol, timeline, search, rule engine, sync merge
packages/telegram_gateway  TelegramGateway and its TDLib FFI implementation
packages/app_db            Drift schema for feeds, sources, rules, settings
packages/rules             rule AST, parser, evaluator (pure Dart)
packages/tdlib_bindings    generated TDLib JSON types
packages/versioning        next version and changelog from conventional commits
tool/tdlib                 Docker build of libtdjson.so from the pinned TDLib commit
tool/ci.sh                 what CI runs: analyze, format check, package and app tests
docs/                      spec, architecture, plan
```

## Build and run

Telegram API credentials are not in the repository. Get an `api_id` and `api_hash` at https://my.telegram.org ("API development tools") and pass them at build time. TDLib's public example credentials work for development builds but are rate-limited and sometimes rejected with `API_ID_INVALID`; never ship with them.

```bash
flutter pub get                       # once, at the repository root
dart tool/fetch_tdlib.dart            # prebuilt libtdjson.so for the pinned TDLib commit
cd app && flutter run --dart-define=TG_API_ID=12345 --dart-define=TG_API_HASH=abcdef... \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=...apps.googleusercontent.com   # optional: Google Drive sync
```

To build `libtdjson.so` locally instead, run the Docker build in `tool/tdlib` and then `dart tool/fetch_tdlib.dart --local`.

### Build-time values

| Flag | Needed for | Source |
|---|---|---|
| `TG_API_ID`, `TG_API_HASH` | Every build. Telegram requires every client app to identify itself | https://my.telegram.org, "API development tools" |
| `GOOGLE_SERVER_CLIENT_ID` | Google Drive sync only. Without it the app works and the Sync screen says the build cannot sync | Your Google Cloud project, see below |
| `TG_FAKE=true` | The fake build: a scripted Telegram (`packages/fake_telegram`) instead of TDLib, for the UI tests and for trying the app without an account. Needs no other flag | — |

None of them is committed, so a fork never ships under someone else's identity.

### Google Drive sync (optional)

Sync keeps feeds, rules and settings equal across devices through a hidden app file in the user's own Google Drive (`docs/ARCHITECTURE.md` section 5.5). Google lets an app sign users in only if the app is registered, so a build that syncs needs a Google Cloud project:

1. Enable the **Google Drive API** in the project.
2. Configure the OAuth consent screen. Testing mode is enough for personal use; add the Google accounts that will sign in as test users. The only scope is `drive.appdata`.
3. Create an OAuth client of type **Android** with package `dev.telegramfeed.telegram_feed` and the SHA-1 of the key that signs the build (one client per key; debug and release keys differ):
   `keytool -list -v -keystore ~/.android/debug.keystore -storepass android -alias androiddebugkey`.
   This client id is not used in the code; Google matches it by package and signature.
4. Create an OAuth client of type **Web application** with no settings. Its client id is the value of `GOOGLE_SERVER_CLIENT_ID`. There is no web app or server: Android's sign-in API accepts only a web-type id as the project's handle.

## Tests

```bash
tool/ci.sh                                                      # analyze, format check, unit and widget tests with goldens
tool/update_goldens.sh                                          # regenerate goldens (Linux, in Docker) after intended UI changes
cd app && flutter test integration_test -d emulator-5554 --dart-define=TG_FAKE=true
```

Every test runs against the fake Telegram: the widget tests read its fixtures, and the integration test drives the fake build of the real app on an emulator, logging in with any phone number and the code `12345`. Nothing needs a Telegram account.

## Releases

**Prereleases are automatic.** After CI passes on `main`, `.github/workflows/debug-release.yml` reads the conventional commits since the last `vX.Y.Z` tag (`packages/versioning`): `feat` raises the minor version, `fix` and `perf` the patch, a breaking change (`feat!:` or a `BREAKING CHANGE:` footer) the major (the minor while the version is 0.x). Pushes with only `docs`, `chore`, `test` or `ci` commits release nothing. Without a tag, the version comes from `app/pubspec.yaml`. The workflow tags the commit, builds APKs for `arm64-v8a` and `x86_64` in release mode, and publishes them as a prerelease with a changelog. It takes the TDLib binaries from the release `.github/workflows/tdlib.yml` publishes and fails with a message when that release does not exist.

These APKs are signed with one fixed debug key, so each build installs over the previous one and Google sign-in keeps working. Repository secrets: `TG_API_ID`, `TG_API_HASH`, `DEBUG_KEYSTORE_BASE64` (`base64 -w0 ~/.android/debug.keystore`), and optionally `GOOGLE_SERVER_CLIENT_ID`.

**Signed release APKs** are built by hand for an existing version: run `.github/workflows/release.yml` with the tag (for example `v0.3.0`). It builds that tag with the release key and adds the APKs to the same GitHub release, which then stops being a prerelease. Additional secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. The release key's SHA-1 needs its own Android OAuth client for Google Drive sync (step 3 above).

Create the keystore once, locally, and keep it out of git:

```bash
keytool -genkey -v -keystore telegram-feed-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -w0 telegram-feed-upload.jks   # value for ANDROID_KEYSTORE_BASE64
```

For a local signed build, put the keystore path and passwords in `app/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`). Without that file, release builds are signed with the debug key.

## License

GPL-3.0. See [LICENSE](LICENSE).
