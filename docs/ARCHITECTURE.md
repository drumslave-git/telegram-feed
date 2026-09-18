# telegram-feed — Technical Architecture

Status: draft v0.1, 2026-09-17. Companion to SPEC.md.

## 1. Summary

- **Flutter** app, Android only. iOS and web are out of scope (decision log).
- **TDLib** (Telegram's official client library) accessed through its JSON interface (`td_json_client`) via `dart:ffi`.
- The TDLib client and all "always-on" logic live in a single **core isolate**. On Android that isolate is hosted by a foreground service so it survives the UI being killed. The UI is a thin client of the core.
- App data that TDLib does not own (feeds, feed membership, read markers, rules, settings) lives in a local **SQLite** database via **Drift**.
- No backend. Nothing leaves the device except MTProto traffic to Telegram.

```
┌───────────────────────────── device ─────────────────────────────┐
│  UI isolate (Flutter)                                            │
│   screens ── view models ── CoreClient (SendPort/ReceivePort)    │
│                                   │                              │
│  ───────────────────────────────── │ ─────────────────────────── │
│  Core isolate (Android: hosted by foreground service)            │
│   CoreServer ── FeedService ── RuleEngine ── TtsService          │
│        │            │              │                             │
│   TelegramGateway   AppDb (Drift/SQLite)   Notifier              │
│        │                                                          │
│   TDLib (td_json_client via FFI)                                  │
└───────────────────────────────────────────────────────────────────┘
```

## 2. Why these choices

| Choice | Alternatives considered | Reason |
|---|---|---|
| TDLib | GramJS / MTProto from scratch; Bot API | TDLib is Telegram's own library, handles auth, updates, media download, local cache, and has Android and web builds. Bot API cannot read arbitrary channels. |
| On-device session | Server-side session; hybrid | The founder chose on-device. No server cost, no custody of user sessions, matches an open-source product. Cost: notifications depend on the app staying alive, which is fine on Android with a foreground service and is why iOS was dropped. |
| Flutter | React Native, Kotlin Multiplatform | Mature FFI, one codebase that could also target desktop or (dropped) web. |
| Core isolate separate from UI | TDLib in the UI isolate; native Kotlin service owning TDLib | The UI can be destroyed while the service lives on. Keeping TDLib in a Dart isolate keeps the code cross-platform; a Kotlin-owned TDLib would need a second implementation for web. |
| Drift (SQLite) | Hive, Isar, shared_preferences | Relational data (feeds ↔ channels, per-feed read markers), proper queries. |
| Device TTS via `flutter_tts` | Cloud voices | Free, offline, works with the screen off. Cloud voices are a later opt-in. |

## 3. Module layout (Dart packages in one repo)

```
telegram-feed/
  app/                  Flutter application (UI, routing, theming, platform glue)
  packages/
    core/               Core isolate: CoreServer, services, rule engine, TTS, notifier
    telegram_gateway/   TelegramGateway interface + TDLib FFI impl
    app_db/             Drift schema, DAOs, migrations
    rules/              Rule AST, parser, evaluator (pure Dart, heavily unit tested)
    tdlib_bindings/     Generated Dart types for the TDLib JSON API (td_api.tl → Dart)
  docs/
  tool/                 Scripts: TDLib build/download, codegen
```

Pure-Dart packages (`rules`, `app_db`, `core`) get the bulk of the tests. `app/` stays thin.

## 4. Telegram gateway

`TelegramGateway` is the only thing that knows about TDLib. Everything above it works with app-level types (`Channel`, `Post`, `Media`).

```dart
abstract interface class TelegramGateway {
  Stream<AuthState> get authState;                         // current state replayed, then changes
  Future<void> setPhoneNumber(String phone);
  Future<void> checkCode(String code);
  Future<void> checkPassword(String password);
  Future<void> registerUser({required String firstName, String lastName});
  Future<void> requestQrCode();                            // AuthWaitOtherDeviceConfirmation carries the link
  Future<void> logOut();

  Future<List<Channel>> myChannels();                      // joined supergroups with isChannel = true
  Stream<ChannelMembershipEvent> get membershipEvents;     // user joined / left a channel in Telegram

  Future<List<Post>> history(int chatId, {int fromMessageId, int limit, bool onlyLocal});
  Stream<PostEvent> get postEvents;                        // PostAdded / PostEdited / PostsDeleted
  Future<void> markViewed(int chatId, List<int> messageIds);

  Future<FileRef> download(FileRef ref, {int priority});   // completes with localPath set
  Stream<FileProgress> fileProgress(int fileId);
  Future<void> close();

  // phase 3: react, discussion
}
```

Implementations:

- One implementation, `TdlibGateway` (package `telegram_gateway`), over a `TdTransport` (raw JSON in, raw JSON out). `TdClient` matches responses to requests by `@extra`, decodes updates with `tdlib_bindings` and hands them to the gateway strictly in order (an edit that needs a `getMessage` round trip cannot be overtaken by the following delete).
- `FfiTransport` (Android, and desktop for development): loads `libtdjson`, polls `td_receive` in one long-lived receive isolate and demultiplexes by `@client_id`. Imported from `package:telegram_gateway/tdlib_ffi.dart` only on native platforms.
- Post events are emitted only for chats known to be channels; `updateMessageContent`/`updateMessageEdited` are re-fetched with `getMessage` so `PostEdited` carries the full post; `updateDeleteMessages` is forwarded only when `is_permanent`.

TDLib parameters: `use_message_database = true`, `use_chat_info_database = true`, `use_file_database = true`, `files_directory` under app cache. TDLib owns message and file caching; the app never duplicates message bodies into its own DB.

API credentials: `api_id` and `api_hash` come from `--dart-define=TG_API_ID=... --dart-define=TG_API_HASH=...`. The repo contains none. CI for release builds injects them from secrets.

## 5. Feeds

### 5.1 Data model (Drift)

```
feeds            (id, name, position, created_at)
feed_sources     (feed_id, chat_id, position, added_at)         -- PK (feed_id, chat_id)
feed_read_marks  (feed_id, chat_id, last_read_message_id)       -- per feed AND per channel
watched_channels (chat_id, title, username)
```

`watched_channels` is the union of all feed sources. It is what rules see as "global".

### 5.2 Sources

Only channels the account is already a member of can be added. The picker lists `myChannels()` with a local search box. The app never calls `joinChat`, `leaveChat`, `searchPublicChat`, or changes Telegram-side mute or folder settings. Because every source is a joined chat, TDLib delivers `updateNewMessage` for all of them and no polling is needed.

If the user leaves a channel in the official app, `membershipEvents` reports it. The source stays in its feeds but is shown as "left" with an option to remove it; history already in TDLib's local database remains readable until then.

### 5.3 Merged timeline

The timeline is a k-way merge over per-channel histories, ordered by `(date desc, chat_id, message_id desc)`.

- `FeedTimeline` keeps one cursor per source: `oldestLoadedMessageId` and a small page buffer.
- Loading a page: for every source whose buffer is empty, fetch the next `history()` page (limit 30). Then pop from a max-heap keyed by date until the requested count is satisfied. Sources that return nothing are marked exhausted.
- Live updates: `postEvents` for any `chat_id` in the feed are inserted at the head if the user is at the top, otherwise counted into a "N new posts" pill.
- Album messages (media groups, `media_album_id`) are collapsed into a single timeline item.
- Edits replace the item in place; deletes remove it.

Nothing is persisted by the timeline itself; TDLib's message database makes re-fetching cheap and offline-capable.

### 5.4 Read state

- `feed_read_marks` stores, per feed and per channel, the newest message id the user has scrolled past. When a channel is added to a feed the mark starts at Telegram's own read position for it (`chat.last_read_inbox_message_id`), so the backlog is not unread.
- Unread count for a feed = Σ over its sources of messages with id > mark. Computed from TDLib (`getChatHistory` with `only_local`, or `chat.lastMessage.id` compared to the mark for a cheap upper bound) and refreshed on `postEvents`.
- Marking read happens on viewport exit with a debounce, and calls `markViewed` on TDLib so the official Telegram app agrees. Setting `syncReadToTelegram`, default on; when off, only `feed_read_marks` is updated.
- "Jump to first unread" opens the timeline at the oldest mark across sources and loads forward.

## 6. Rules and notifications (phase 2)

### 6.1 Rule model

```
rules (id, name, enabled, scope_kind {global, channel}, scope_chat_id?,
       condition_json, priority {silent, normal, urgent}, read_aloud bool,
       schedule_json?, created_at)
```

Condition AST (package `rules`):

```
Expr = And(List<Expr>) | Or(List<Expr>) | Not(Expr) | Term
Term = { text, wholeWord: bool, caseSensitive: bool }     // multi-word text = phrase match
Schedule = { weekdays: Set<1..7>, from: "HH:mm", to: "HH:mm" }   // local time, may wrap midnight
```

The editor is a visual builder (groups of terms with AND/OR toggles, NOT per term), plus a text form `("bitcoin" OR btc) AND NOT airdrop` that parses to the same AST (`RuleParser`, package `rules`): terms are bare words or quoted phrases, default whole-word and case-insensitive; prefix `~` for substring match, `=` for case-sensitive; `AND` binds tighter than `OR`, `NOT` tightest; `RuleParser.format` renders the AST back. Whole-word matching is Unicode-aware: Dart's `\b` is ASCII-only, so boundaries are `(?<![\p{L}\p{N}_])…(?![\p{L}\p{N}_])` with `unicode: true` (CJK text has no inner boundaries, so users pick `~` there). Case-insensitive matching uses the regex engine's Unicode case folding, which covers Cyrillic.

### 6.2 Evaluation

On every `PostEvent.newMessage` for a watched channel:

1. Extract text: message text, or media caption. Formatted entities are flattened to plain text. Nothing else is matched (no forward origin, no URLs beyond their visible text).
2. Candidate rules = enabled global rules + enabled rules scoped to this `chat_id`, filtered by schedule against the local clock.
3. Evaluate each condition. Collect matches.
4. If none: stop. Otherwise: priority = max over matches, readAloud = any match.
5. Emit a notification (section 6.3) and, if readAloud, enqueue for TTS (section 7).

Edited messages are ignored by the engine. Deleted messages cancel a pending notification if it has not been shown yet.

### 6.3 Notifications

`flutter_local_notifications` with three Android notification channels, created once:

| App priority | Android channel importance | Behaviour |
|---|---|---|
| silent | LOW | In the shade, no sound, no heads-up |
| normal | DEFAULT | Sound and vibration per system settings |
| urgent | HIGH + `bypassDnd` | Heads-up; DND bypass requires the user to grant notification-policy access, which the app requests when the first urgent rule is created |

Each notification: channel title, post excerpt, thumbnail if present, actions **Listen** and **Open in Telegram**. Tapping opens the post inside the first feed containing that channel. Notifications from the same channel are grouped.

Android 13+ requires `POST_NOTIFICATIONS`; requested during onboarding of phase 2.

## 7. Read aloud

- `TtsService` in the core isolate owns the queue and text preparation; the actual `flutter_tts` calls run in the service host isolate (see Android notes), which the core reaches over a port. A single FIFO queue; a new item never interrupts a playing one unless the user stops it (`flutter_tts.speak` flushes by default, so the queue must wait for `awaitSpeakCompletion`).
- Language: `google_mlkit_language_id` on Android (on-device). Detected code selects a voice from the user's per-language preferences, falling back to the system default for that language, then to the app's default voice.
- Text preparation: strip URLs (say "link"), collapse whitespace, drop emoji and formatting markers, prepend "New post in <channel>". Posts over a configurable length are truncated with "… and more".
- Audio focus: request transient focus with ducking; release on queue drain. Never speak during a phone call (check `audio_session` / telephony state).
- The "Listen" action and auto-read use the same path, so behaviour is identical.

## 8. Platform notes

### Android (phase 1 and 2)

- **Foreground service** via `flutter_foreground_task`, service type `specialUse` with `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` explaining the persistent Telegram connection. `dataSync` is not usable: Android 15+ caps it at 6 hours per day (spike P0-2). The app manifest declares the plugin's service itself. Persistent notification "Watching N channels" with a Pause action.
- The foreground task runs a Dart callback in its own Flutter engine. The **core isolate is spawned from that callback**, and it registers its `SendPort` with `IsolateNameServer` under a fixed name. The UI engine looks the port up on start and talks over it. Both engines are in the same process, so ports work across them (verified in spike P0-2).
- **The core isolate is never respawned.** TDLib aborts the process if `td_receive` is called from two threads, and each isolate would start its own receive loop. After a logout TDLib closes its client (`AuthClosed`); the core isolate then creates a new client and gateway itself and `CoreServer.replaceGateway` swaps it in behind the same port, so UI clients just see the new auth states (verified on the emulator, P1-7).
- **Plugins with platform-to-Dart callbacks (`flutter_tts`, `flutter_local_notifications`) cannot run in the core isolate**: Flutter routes platform messages to the root isolate only. The service engine's root isolate (the task handler, "service host") owns those plugins; `Notifier` and `TtsService` in `core` send it `notify` / `speak` commands over a port. Callback-free method-channel calls (e.g. `path_provider`) work from the core isolate via `BackgroundIsolateBinaryMessenger`.
- In phase 1 (no notifications yet) the service is not needed. The core isolate is still used from day one, spawned by the UI, so moving it into the service in phase 2 is a change of host, not of code.
- Battery: on first run of phase 2 the app asks for an exemption from battery optimization and explains why. Without the service the OS kills TDLib within minutes.
- TDLib binaries: prebuilt `libtdjson.so` for arm64-v8a, armeabi-v7a and x86_64, produced by a CI job from a pinned TDLib tag, published as a GitHub release asset and downloaded by `tool/fetch_tdlib.dart`. Not committed to git.

### Web (dropped 2026-09-17)

A web build on tdweb was completed in phase 3 (commit 87e10f3: tdweb transport over `dart:js_interop`, drift on a self-built `sqlite3.wasm`, browser notifications, Web Speech read-aloud) and verified up to QR login on the production DC, then dropped by the founder to keep the product Android-only. The gateway keeps its transport seam (`TdTransport`), so the target can be revived from that commit.

### iOS (not planned)

iOS has no equivalent of a persistent foreground service, so an on-device-only design cannot deliver real-time rule notifications there. Rather than ship a degraded version, iOS is off the roadmap. Nothing in the code should block a future iOS build (the FFI gateway would work), but no effort is spent on it.

## 9. Phase 0 spikes

Each spike is a throwaway branch with a written outcome in `docs/spikes/`.

1. **TDLib FFI on Android.** Load prebuilt `libtdjson.so`, log in, list chats, receive `updateNewMessage`. Exit criterion: login and live updates from a Flutter app on an Android emulator (x86_64 image). All development and testing happens on emulators, never on the founder's personal phone.
2. **Core isolate under the foreground service.** Spawn the core isolate from `flutter_foreground_task`'s callback, exchange ports with the UI engine via `IsolateNameServer`, kill the activity, confirm TDLib stays connected and a notification still fires. Also confirm `flutter_tts` works from that engine with the screen off.
3. **Merged timeline performance.** 50 channels, scroll through 2 000 posts, measure page latency and memory with TDLib's local database. Exit criterion: < 100 ms per page from local cache.
4. **tdweb feasibility.** Log in and fetch history in a Flutter web build. Decide whether web stays on the roadmap or moves behind a GramJS-based gateway.

## 10. Privacy and security

- The TDLib database is stored in the app's private storage, encrypted with a key held in the platform keystore (`flutter_secure_storage`), passed to TDLib as `database_encryption_key`.
- No analytics, no crash reporting by default. Optional opt-in crash reporting (Sentry) may come later; it must never include message content.
- Logout wipes the TDLib database, the app database, and the media cache.
- The app requests only: internet, notifications, foreground service, and (optional) battery-optimization exemption.
- Third-party native binaries (TDLib) are built from pinned sources in Docker (`tool/tdlib`), never downloaded prebuilt from third parties.

## 11. Testing strategy

- `rules`: exhaustive unit tests for the parser and evaluator, including Unicode word boundaries, Cyrillic case folding, schedule wrap-around at midnight.
- `core`: timeline merge tested against a fake `TelegramGateway` with scripted histories and update streams.
- `app_db`: migration tests on every schema change.
- `app`: golden tests for the main screens; one integration test on an emulator that logs in with the project's spare Telegram account on the production DC (Telegram disabled test-DC test numbers in 2024; see `docs/spikes/tdlib-ffi.md`). The session is created once and its TDLib database is reused between runs so the SMS code is not needed on every run.
- All manual testing runs on Android emulators (x86_64 system images, so the `libtdjson.so` x86_64 build is required from day one). No personal devices.

## 12. Decision log

| Date | Decision | Notes |
|---|---|---|
| 2026-09-17 | Android → web | Founder priority |
| 2026-09-17 | iOS dropped from the roadmap | On-device-only cannot give real-time notifications on iOS |
| 2026-09-17 | On-device TDLib session, no backend | |
| 2026-09-17 | Flutter | Single codebase |
| 2026-09-17 | Chronological feed, no ranking | Keep MVP simple |
| 2026-09-17 | Rules per channel or global, never per feed | Feeds are reading views only |
| 2026-09-17 | Rules match text and captions only | No forward origin, edits, or URL matching |
| 2026-09-17 | Device TTS, auto language detection | Cloud voices are a later opt-in |
| 2026-09-17 | Local only, no sync in MVP | Sync backend considered for phase 4 |
| 2026-09-17 | Open source under GPL-3.0 | Forks must stay open |
| 2026-09-17 | Only joined channels as sources | App never joins, leaves, or searches public channels |
| 2026-09-17 | Reading syncs read state to Telegram | Default on, setting to disable |
| 2026-09-17 | Name stays telegram-feed | Rename before public release |
| 2026-09-17 | Emulator login uses a spare real account on the production DC | Telegram disabled test-DC test numbers; the founder's main account is never used (spike P0-1) |
| 2026-09-17 | Foreground service type `specialUse` | Android 15+ caps `dataSync` at 6 h/day (spike P0-2) |
| 2026-09-17 | TTS and notification plugins live in the service host isolate, core sends commands | Background isolates cannot receive platform callbacks (spike P0-2) |
| 2026-09-17 | Share puts the `t.me` link (public username link, else `t.me/c`) into the system share sheet via `share_plus`; copy link uses the clipboard | Private `tg://privatepost` links stay for Open in Telegram only, since other apps cannot open them |
| 2026-09-18 | A channel added to a feed starts at Telegram's read position | Founder decision while dogfooding: the whole history used to count as unread |
| 2026-09-17 | Web target dropped after the phase 3 build worked | Founder decision, Android only; the build stays in history at 87e10f3 |
| 2026-09-17 | Web stays on tdweb, built from source; no GramJS gateway | tdweb 1.8.67 self-built works end to end, npm 1.8.0 is dead (spike P0-4) |
