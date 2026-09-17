# telegram-feed — Plan and Progress

Single source of truth for what is done, in progress, and next. Every session updates this file and commits it.

Legend: `[ ]` not started, `[~]` in progress (name the branch or session note), `[x]` done (commit hash), `[-]` dropped (reason).

**Current phase:** 2 (rules and voice). **Next task:** P2-7.

## Phase 0 — Spikes

Throwaway branches `spike/<name>`. Each spike ends with a short outcome note in `docs/spikes/<name>.md` and a tick here. Emulator only (x86_64).

- [x] P0-1 TDLib FFI on Android emulator: build `libtdjson.so` (x86_64 + arm64) in Docker, load via `dart:ffi`, log in, list chats, receive `updateNewMessage`. (828c1c5 on `spike/tdlib-ffi`; outcome `docs/spikes/tdlib-ffi.md`). Test-DC login replaced by the spare production account, since Telegram disabled test numbers.
- [x] P0-2 Core isolate under `flutter_foreground_task`: spawn core isolate from the service callback, exchange ports with the UI engine via `IsolateNameServer`, kill the activity, confirm TDLib stays connected and a local notification fires. Confirm `flutter_tts` speaks from that engine with the screen off. (95e9e50 on `spike/core-isolate-service`; outcome `docs/spikes/core-isolate-service.md`). Findings: service type must be `specialUse`; TTS/notification plugins run in the service host isolate, not the core isolate.
- [x] P0-3 Merged timeline performance: 50 channels, 2 000 posts, page latency < 100 ms from TDLib local database. (8e27371 on `spike/timeline-perf`; outcome `docs/spikes/timeline-perf.md`). p50 2.7 ms, p95 16 ms; first page 110 to 150 ms, to be seeded from `chat.last_message` in P1-10.
- [x] P0-4 tdweb feasibility in Flutter web: log in and fetch history. Decide web stays on tdweb or moves to a GramJS gateway. (5980657 on `spike/tdweb`; outcome `docs/spikes/tdweb.md`). Decision: web stays on tdweb, built from source by `tool/tdweb`; npm tdweb is dead.

## Phase 1 — Android MVP

- [x] P1-1 Repo scaffold: Flutter app + packages (`core`, `telegram_gateway`, `app_db`, `rules`, `tdlib_bindings`), Dart pub workspace (no melos), CI (`.github/workflows/ci.yml`, same steps in `tool/ci.sh`) running analyze, format check and tests.
- [x] P1-2 `tdlib_bindings`: generate Dart types from `td_api.tl` for the pinned TDLib commit d1085f9 (`tool/generate.dart`; 2 183 constructors, 1 022 functions, 211 sealed types; round-trip tests).
- [x] P1-3 `telegram_gateway`: `TelegramGateway` interface + `TdlibGateway` over a `TdTransport` (auth flow, myChannels, history, postEvents, markViewed, download, membershipEvents) with `FfiTransport`; unit-tested against a scripted fake transport. Not yet exercised on the emulator (P1-5/P1-7 will).
- [x] P1-4 `tool/fetch_tdlib.dart` + CI job (`.github/workflows/tdlib.yml`) that builds `libtdjson.so` (`tool/tdlib`) and tdweb (`tool/tdweb`) from the pinned commit and publishes them as release assets `tdlib-<sha7>`. The fetch script also has `--local` for the Docker outputs; the workflow itself runs once the repo has a GitHub remote.
- [x] P1-5 Core isolate + `CoreClient` port protocol; spawned from the UI in this phase. `CoreServer`/`CoreClient` (the client implements `TelegramGateway`), model codec, `native_isolate.dart`; verified on the emulator: app reaches `AuthWaitPhoneNumber` through the core isolate.
- [x] P1-6 `app_db`: Drift schema (`feeds`, `feed_sources`, `feed_read_marks`, `watched_channels`, `settings`) with DAO methods, schema validation test and behaviour tests (cascade, watched-channel pruning, monotonic read marks, wipe). Schema v1; `drift_dev schema dump` starts with v2.
- [x] P1-7 Login screens: phone, code, 2FA password, QR login; logout wipes all data. `AuthGate` + `_StepForm` screens with inline Telegram errors, `CoreHost` (spawns/finds the core, respawns after logout, wipes `app_db`), widget tests. On the emulator the phone screen shows; real login needs the founder's own `api_id`/`api_hash` (Telegram answers `API_ID_INVALID` to TDLib's example id from the app) and the founder typing the code.
- [x] P1-8 Feeds list screen with unread badges; create, rename, reorder, delete. `FeedsScreen` + `FeedsController` (badge = sources whose `lastMessageId` is newer than the feed's read mark, refreshed on new posts and mark changes); `Channel.lastMessageId` added to the gateway. Widget tests run drift under `runAsync`.
- [x] P1-9 Feed editor: add joined channels from a searchable picker, remove, reorder. `FeedEditorScreen` + `ChannelPicker` (bottom sheet, filters by title/username, hides already-added channels, flags channels the account left). Reached from the feeds list until the timeline exists.
- [x] P1-10 Merged timeline: k-way merge, pagination, live inserts, album collapsing, edits and deletes. `FeedTimeline` in `core` (local-then-network fill, dedupe, pending "N new posts" when scrolled down) with unit tests; `TimelineScreen` + `PostCard` in the app (media shown as labels until P1-11), edit action opens the feed editor.
- [x] P1-11 Media: inline photos, video playback, voice and audio playback, download progress. `MediaView`/`Downloaded` (progress from `fileProgress`, photo size chosen by viewport width, video and audio download on play, documents on tap), `video_player` and `just_audio` widgets. Widget tests with a scripted download gateway; playback itself needs a logged-in emulator run.
- [x] P1-12 Read state: mark on scroll, unread counters, jump to first unread, `syncReadToTelegram` setting. `ReadMarker` (debounced, newest id per chat, `viewMessages` when the setting is on), positioned list in `TimelineScreen` (items above the viewport count as read, unread dot per card, jump loads until the marks are reached), `firstUnreadIndex`/`reachedMarks` in `FeedTimeline`. Setting UI comes with P1-14.
- [x] P1-13 Open in Telegram deep link. `telegramPostUri` in `core` (`https://t.me/<user>/<id>` for public channels, `tg://privatepost` plus `t.me/c` fallback for private ones, TDLib id → server id), `url_launcher` action on every card, manifest `<queries>` for https/tg.
- [x] P1-14 Settings screen: account, appearance, storage usage and cache clearing, licenses. `SettingsScreen` (account via new `me()`, log out, `syncReadToTelegram` toggle, theme mode segmented control persisted in `settings` and applied by `MaterialApp`, storage via `getStorageStatisticsFast` and `optimizeStorage`, Flutter license page). Gateway gained `me`, `storageStats`, `clearCache` end to end.
- [x] P1-15 Golden tests for main screens (login phone/code/QR, feeds, editor, timeline light+dark, settings; Ahem font, 0.3 % tolerance comparator in `flutter_test_config.dart`); `integration_test/app_test.dart` runs the real app on the emulator, verified: reaches the login screen and skips the feed flow until the spare account is logged in.
- [x] P1-16 Closed beta build (signed APK via CI). `release.yml` on `v*` tags: fetches TDLib, signs from secrets (`key.properties` + keystore, debug fallback locally), builds per-ABI release APKs and attaches them to a GitHub release. Needs the GitHub remote, the tdlib release and the secrets listed in the README before it can run.

## Phase 2 — Rules and voice

- [x] P2-1 `rules` package: AST, text-form parser, evaluator, schedule matcher. Unit tests incl. Unicode word boundaries and Cyrillic case folding. Text form `(a OR b) AND NOT c` with `~` (substring) and `=` (case-sensitive) modifiers, round-trips via `RuleParser.format`; JSON form for `condition_json`.
- [x] P2-2 Rule engine in core: evaluate on `postEvents`, priority merge, read-aloud flag, ignore edits, cancel on delete. `RuleEngine` + `RuleSpec.fromRow`; `rules` table (schema v2) with DAO, schema dumps and a v1→v2 migration test.
- [x] P2-3 Foreground service hosting the core isolate; battery-optimization exemption prompt; "Watching N channels" notification with Pause. `service/core_service.dart` (specialUse service, task handler spawns the core and registers its port, notification counts watched channels, Pause/Resume buttons drive `setPaused`), `CoreHost` starts the service and falls back to an in-process core, forwards rule/source changes with `refresh`; battery exemption helpers exposed (prompt UI lands with the rules screens in P2-6). Verified on the emulator: service foreground with the notification, UI reconnects to the running core after the activity is destroyed.
- [x] P2-4 Notifications: three channels (silent, normal, urgent with DND bypass), grouping, Listen and Open in Telegram actions, tap opens post in feed. `service/notifier.dart` (channels `posts_silent|normal|urgent`, `bypassDnd` on urgent, per-channel group summaries, cancel on delete, actions routed to the service host over `telegram_feed.notifier`), `notifications/notification_launch.dart` (tap → first feed containing the channel, timeline focused on the post; Open in Telegram; policy-access helpers via a small Kotlin method channel). Listen action logs until P2-5.
- [x] P2-5 TTS service: queue, language detection, voice selection, text preparation, audio focus, call detection. `prepareForSpeech` in `core` (URLs → "link", emoji/markers dropped, channel prefix, sentence-aware truncation); `TtsService` FIFO queue over a `Speaker` interface (ML Kit language id, per-language voice and rate/pitch from settings, `flutter_tts` with audio focus, `audio_session` interruptions pause and re-speak, so no telephony permission); Listen action and auto-read share one path. Settings UI is P2-7.
- [x] P2-6 Rules list and rule editor screens (visual builder + text form), test-against-recent-posts. `RulesScreen` (enable switches, battery-exemption banner), `RuleEditorScreen` (OR-of-AND builder ⇄ text form via `BuilderModel`, scope picker, priority, read-aloud, enabled, weekday/time schedule, DND policy prompt on urgent, dry run over recent posts). Reached from the feeds list's Rules action.
- [ ] P2-7 Read-aloud settings screen.

## Phase 3 — Interactions and web

- [ ] P3-1 Reactions.
- [ ] P3-2 Discussion thread view and reply.
- [ ] P3-3 Share / copy link.
- [ ] P3-4 `TdwebGateway` and Flutter web build; browser notifications and Web Speech TTS; static hosting (no special headers, spike P0-4).

## Phase 4 — Extras

- [ ] P4-1 Optional sync backend for feeds and rules.
- [ ] P4-2 AI semantic rules.
- [ ] P4-3 AI-generated podcast from a feed.
- [ ] P4-4 Optional cloud voices.

## Dropped

- [-] iOS build: on-device-only cannot deliver real-time notifications on iOS (2026-09-17).
- [-] Adding unjoined public channels: only joined channels are sources (2026-09-17).
