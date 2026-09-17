# telegram-feed

A custom Telegram client for *reading*, not chatting. Combine channels into feeds, get notifications from keyword rules instead of a per-chat mute switch, and have posts read aloud.

Status: specification stage. No code yet.

- [Product spec](docs/SPEC.md): what the app does, user stories, phases, resolved decisions.
- [Architecture](docs/ARCHITECTURE.md): Flutter + TDLib design, data model, rule engine, platform notes, phase 0 spikes.

## License

GPL-3.0. See [LICENSE](LICENSE).

## Planned stack

- Flutter (Android first, then web)
- TDLib via `dart:ffi` on mobile, tdweb on web
- Drift (SQLite) for app data
- Device text-to-speech via `flutter_tts`

## Running (future)

Telegram API credentials are not in the repo. Obtain `api_id` and `api_hash` at https://my.telegram.org and pass them at build time:

```bash
flutter run --dart-define=TG_API_ID=12345 --dart-define=TG_API_HASH=abcdef...
```
