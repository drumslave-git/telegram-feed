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
  Future<List<ChatFolder>> chatFolders();                  // Telegram folders, reduced to their channels

  Future<List<Post>> history(int chatId, {int fromMessageId, int limit, bool onlyLocal});
  Stream<PostEvent> get postEvents;                        // PostAdded / PostEdited / PostsDeleted
  Future<void> markViewed(int chatId, List<int> messageIds);

  Future<FileRef> download(FileRef ref, {int priority});   // completes with localPath set
  Stream<FileProgress> fileProgress(int fileId);
  Future<FileProgress> downloadFrom(int fileId, {int offset, int priority});  // play while downloading
  Future<int> downloadedPrefix(int fileId, int offset);    // bytes readable from offset
  Future<void> cancelDownload(int fileId);
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
feeds            (id, name, position, created_at, sync_id, updated_at, filter_json?)
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
- Live updates: `postEvents` for any `chat_id` in the feed are inserted at the newest end if the user is there, otherwise they wait and are counted on the "to newest" button, which releases them.
- Layout: the list is reversed (index 0 is the newest post, at the bottom), so loading older pages appends at the far end and never shifts what is on screen. A row inserted at the newest end does shift every index; the screen then re-anchors on index 0. Rows are keyed by `(chat_id, album or message id)`.
- Opening (`_open` in `TimelineScreen`): the list widget takes its start position only when it is first built, so the first pages are loaded before it is. The position is, in this order: the post a notification asked for; where the user left the feed earlier in the session (kept in memory per feed: row and its edge); the first unread post; the newest post. For the first unread post the sources are loaded down to their read marks, at most 300 rows; the "Unread posts" divider is drawn on top of that row, and because a reversed list aligns rows by their bottom edge, the row above it is aligned just below the top of the screen. If the unread posts do not fill the screen, the newest post is put at the bottom instead of leaving a gap.
- Album messages (media groups, `media_album_id`) are collapsed into a single timeline item.
- Edits replace the item in place; deletes remove it.

Nothing is persisted by the timeline itself; TDLib's message database makes re-fetching cheap and offline-capable.

### 5.4 Read state

- `feed_read_marks` stores, per feed and per channel, the newest message id the user has scrolled past. When a channel is added to a feed the mark starts at Telegram's own read position for it (`chat.last_read_inbox_message_id`), so the backlog is not unread.
- Unread count for a feed = Σ over its sources of messages with id > mark. Computed from TDLib (`getChatHistory` with `only_local`, or `chat.lastMessage.id` compared to the mark for a cheap upper bound) and refreshed on `postEvents`.
- A post is read once its end has been on screen, as in Telegram. Marking is debounced and calls `markViewed` on TDLib so the official Telegram app agrees. Setting `syncReadToTelegram`, default on; when off, only `feed_read_marks` is updated.
- The timeline opens at the first unread post (section 5.3); there is no separate jump action.

### 5.5 Sync through Google Drive (phase 4)

Feeds with their sources, rules and a whitelist of settings (theme, read-aloud preferences, read sync, AI endpoint and model) stay the same on all of a user's devices through one JSON file in the hidden app data folder of their own Google Drive. There is no server of ours. Read positions, the AI API key, the Telegram session and device state never sync.

- **Identity of items.** Feeds and rules carry a random `sync_id` (local row ids differ per device) and an `updated_at` stamp, settings an `updated_at` (schema v4). A feed's list of sources is part of the feed: adding, removing or reordering sources stamps the feed. Deleting a feed or rule leaves a row in `sync_tombstones`; a logout wipe leaves none, and sync is turned off before the wipe, so an emptied database is never merged into the file.
- **Merge** (`SyncSnapshot.merge`, package `core`): item by item, the newer edit wins; a deletion beats edits made before it, and an edit made after the deletion brings the item back; tombstones expire after 180 days. The file is canonical JSON with a format version; a file from a newer version is refused.
- **Run** (`SyncEngine`): export the database, read the file, merge, apply what changed locally (`applySynced*` in `app_db`), write the file only if it differs. Two devices writing at once can hide each other's edits in the file, but never lose them: every run merges the device's whole local state back in, so the next sync heals it.
- **When** (`SyncController`, UI isolate): at start, 15 seconds after a local edit, every 15 minutes while the app is open, and on demand from Settings. Pulled rule changes reach the core the same way local edits do, through the database watchers.
- **Drive access** (`DriveSyncStore`, `GoogleDriveAuth`): `google_sign_in` for the account and an access token with the single scope `drive.appdata`, then plain REST calls (`files.list` in `appDataFolder`, media download, multipart create, media update). A 401 gets one retry with a fresh token. Needs an Android OAuth client (package name + signing SHA-1) in a Google Cloud project and that project's web client id at build time: `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`. Without it the Sync screen says the build cannot sync.

### 5.6 Video playback

- **Playing while downloading.** A video starts as soon as its first bytes are there, as in the official app. `MediaServer` (UI isolate) is an HTTP server on the loopback interface; the player (`video_player`, ExoPlayer) opens `http://127.0.0.1:<port>/<secret>/<fileId>` and asks for byte ranges. Bytes TDLib already has are read from its partial file, where they sit at their final offsets; for a range that is not there yet the download is aimed at it (`downloadFile` with `offset`) and the response waits. Seeking and MP4 files with the index at the end are the same case: another range. The newest request decides where TDLib downloads. Response headers are written at once through a detached socket, because dart:io holds them back until the first body byte and the player's read timeout would run meanwhile. The path contains a random token, since other apps can reach the port; the port closes when nothing plays. A finished file is played from disk without the server; a file without a known size is downloaded whole first.
- **Sessions.** `VideoSessions` keeps one `VideoSession` (player plus state) per file id outside the widget tree, so the timeline row and the viewer show the same player. Only one session has sound at a time. Timeline rows are keyed by post, because the list otherwise reuses row state by position and a new post at the top shifts state under another post.
- **Viewer** (`MediaViewerScreen`, `VideoStage`, `ZoomablePhoto`): one full-screen viewer for the photos and videos of a post; a sideways swipe pages through the album, with the position (`2 of 5`) beside the back arrow. A tap on a video plays it there at once, as the official app does; the timeline has no player controls. Only the video page in front has a session: its neighbours are posters, and turning the page hands the session back exactly as leaving does. The viewer is immersive and leaves the orientation to the device. Controls: back arrow, tap shows or hides them, scrubber with the buffered range, speed, mute, replay at the end; double tap on the left or right third seeks 10 s, in the middle it zooms to 2.5× around the tapped point and back; a pinch zooms up to 6× and a drag moves the zoomed picture (`InteractiveViewer` around the player's texture, zoom helpers in `media/zoom.dart` shared with photos); a finger held down plays at 2× until it lifts, then the chosen speed returns. The gesture layer lies behind the buttons, not around them, so button taps do not wait out the double-tap window. A vertical drag with one finger carries the picture away while the black behind it fades, and closes the viewer past 120 px or with a flick (`SwipeToClose`); it is off while the picture is zoomed, and a second finger takes the drag recognizer out of the arena so a pinch stays a pinch. For that the viewer's route is not opaque, so timeline rows under it remain visible to the visibility detector: autoplay rests while the row's route is not the current one. Leaving the viewer pauses the video, disposes the player and cancels the unfinished streaming download at once (`releaseFromViewer`).
- **Download button** (`VideoDownloads`, `VideoDownloadButton`): a pill in the top left corner of a video in the timeline and in the viewer's top bar, as in the official app: arrow and size, then a progress ring with the bytes that cancels on tap, nothing once the file is complete. It downloads the whole file into TDLib's cache (priority 16, below a playing video's 32); nothing is exported to the gallery. A file the user asked for is not cancelled when its player closes, and cancelling the wish leaves a playing video its download. Posts carry the `FileRef` of the time they were loaded, so the button asks TDLib (`getFileDownloadedPrefixSize`) whether the file is complete by now, and listens to the file's progress while it shows: a short video that autoplays under it is streamed whole within seconds.
- **Picture-in-picture** has two parts, as in the official app. *Mini player* (`MiniPlayer`): the viewer's PiP button moves the session into a small window in the root navigator's overlay that floats over the timeline and every other screen; drag it (it rests at the nearer side), tap for pause and play, open it in the viewer again, or close it. A session counts its sound-watching holders separately (`retainForViewer` / `releaseFromViewer`), so the viewer and the mini player hand a video to each other without it stopping, and it ends when the last of them lets go. Opening the viewer ends a mini player that shows another video. *System window* (`SystemPip`, `PipHost`, `MainActivity`): Android's picture-in-picture shrinks the whole activity, so it cannot float over our own screens; it takes over when the app is left. While a video plays in the viewer or the mini player (`VideoSessions.foreground`, which counts only once the player is initialized, because the window needs the picture's size) the activity is armed over the channel `tf/pip` with the video's aspect ratio, clamped to Android's 1:2.39 to 2.39:1: auto-enter from Android 12, `onUserLeaveHint` on 8 to 11. In the window `PipHost`, which sits above the navigator, shows nothing but the video and keeps the screens alive offstage, since they were not made for a window that small. When the activity is stopped (the window was dragged away, or the device has no such window) the foreground video pauses; nothing plays from the background.
- **Autoplay** (`AutoplayPolicy`, settings `media.autoplay*`, synced): a video up to 60 s and 20 MB (both adjustable; animations only by size) starts muted and looping in its row (`InlineVideo`) once 60 % of it is visible, and pauses below 20 %. A tap opens the viewer on the same player with sound; leaving the viewer mutes it again and it keeps autoplaying. A row that the list rebuilds picks its autoplay session up again within a grace period of 0.8 s; after that the player is disposed and the download cancelled. `AutoplayScope` sits above the navigator and hands the policy to the media widgets.

### 5.7 Main screen

`HomeScreen` is a tab bar: `+`, "Feeds", the Telegram chat folders, "All channels".

- The Feeds tab lists the feeds with the number of channels that have new posts (`FeedsController`); the tab label counts the feeds that have any. A tap opens the feed as `TimelineScreen(feed:)`, dragging reorders, the row's menu leads to its channels, rename and delete. `+` creates a feed and goes straight to its channel editor.
- Folder tabs come from `chatFolders()`: TDLib announces the folders in `updateChatFolders`; the chats of each are read with `getChats(chatListFolder)`, which already applies the folder's include and exclude rules and Telegram's order, and only channels are kept. Folders without channels get no tab. The app never edits folders.
- Channel lists (`ChannelList`) show photo, newest post, time and Telegram's unread count from `Channel`. They reload when the app resumes, three seconds after a new post, and on pull to refresh.
- A channel opens as `TimelineScreen(channel:)`: the same timeline with one source. It belongs to no feed, so its read marks are Telegram's own position (`last_read_inbox_message_id`); reading moves it through `viewMessages` when `syncReadToTelegram` is on and is not recorded otherwise.
- The folders arrive from TDLib a moment after the screen is up. The `TabController` is replaced only when the set of folders changes, and the selected tab stays selected.
- A long press on a folder tab offers "Create feed from folder": a feed with the folder's name and the channels it has at that moment, in the folder's order, each starting at Telegram's read position. It is a one-time copy; the feed does not follow the folder afterwards.

### 5.9 Posts and comments look like the official app

A timeline row (`PostCard`, `feeds/post_card.dart`) is drawn like a post in the official Android app, in the group-chat form because a feed mixes channels: the channel's photo beside a bubble on a tinted backdrop (`ChatColors`), the channel's name in one of Telegram's seven peer colours (`peerColor`, by id), media edge to edge, the text, reaction pills, a comments bar, a round share button beside the bubble, and day pills between days.

- Views, "edited" and the time sit in the bottom right corner. `BubbleText` is a render object of its own that puts this footer on the last line of the text when there is room and on a line of its own otherwise; with reactions the pills use the full width and the footer takes the free end of the last row; with nothing under the pictures it lies on top of them.
- The unread dot has a reserved slot beside the time and only fades, so nothing moves when a post becomes read.
- A tap or a long press on the bubble opens the menu: the emoji the channel allows, Open in Telegram, Comments, Share, Copy link, and for posts with a video the autoplay settings (`showAutoplaySettings`, the same switch and limits as in Settings).
- Albums of photos and videos are a mosaic: `layoutAlbum` ports the grouped layout of the official apps (hand-made arrangements for two to four pictures by their proportions, row splitting towards a 3:4 block for more). The mosaic always fills the bubble's width and is at most one and a half widths tall; cells crop their picture. Audio and documents of an album stay a list.
- `Post.entities` and `Comment.entities` carry TDLib's text entities (offsets in UTF-16 units). `FormattedText` cuts the text at every entity boundary, so nested and overlapping formatting works; links, mentions and e-mail addresses open through `launchFirst`, spoilers are covered until tapped. Rules, read-aloud, sharing and notifications keep using the plain text.
- Avatars: the timeline takes channel photos from `myChannels()` (the database keeps titles only); comments carry `authorId` and `authorPhoto`, resolved once per sender by the gateway. The thread view shows the post as its timeline row on top and comments as bubbles, own comments on the right without a photo. Feed editor, channel picker and the rule scope list show the channel photos too.

### 5.8 Feed filters

`feeds.filter_json` (schema v5) holds a `FeedFilter` (package `core`): media presence (any, with media, text only), a set of media kinds (photo, video, gif, audio, voice, document, other; empty = all), a minimum video length and a minimum length for posts without media. Null means everything. Unknown values from a newer version are ignored, broken JSON shows everything.

- **Timeline.** `FeedTimeline` runs every post through the filter as it leaves a source's buffer or arrives live; hidden posts never become rows. Album parts are judged one by one.
- **Read state.** Hidden posts must not stay unread forever, or a channel that only posts hidden things would keep its feed marked as new. The timeline remembers which ids it hid and which it showed per channel; `coveredFrom(chat, id)` is the newest id such that everything between is hidden. Reading a row covers the hidden posts after it, and hidden posts that directly follow the read mark are covered as soon as the source is loaded down to the mark. Covered ids go the same way as seen ones: `feed_read_marks`, and `viewMessages` when read sync is on. The feeds list's cheap unread bound cannot see content, so a feed may show as new until it is opened once.
- **Rules.** The rule engine gets, per channel, the filters of all feeds that contain it (`filtersByChat`). A post that every one of them hides is dropped before the conditions are looked at; one feed that shows it is enough. The core re-reads them when a feed row changes.
- **Editing.** The feed editor's "Show" row opens a sheet with the four controls; the row's subtitle is the filter in words.
- **Sync.** The filter travels with the feed as the optional `filter` key of the snapshot. The file's format version stays 1: a device on an older version ignores the key and keeps syncing, and the filter survives as long as that device does not edit the feed.

## 6. Rules and notifications (phase 2)

### 6.1 Rule model

```
rules (id, name, enabled, scope_kind {global, channel}, scope_chat_id?,
       condition_json, priority {silent, normal, urgent}, read_aloud bool,
       schedule_json?, created_at, semantic_prompt?)
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
2. Drop the post if every feed containing the channel hides it (section 5.8). Candidate rules = enabled global rules + enabled rules scoped to this `chat_id`, filtered by schedule against the local clock.
3. Evaluate each condition. Collect matches.
4. If none: stop. Otherwise: priority = max over matches, readAloud = any match.
5. Emit a notification (section 6.3) and, if readAloud, enqueue for TTS (section 7).

Edited messages are ignored by the engine. Deleted messages cancel a pending notification if it has not been shown yet.

### 6.4 AI semantic rules (phase 4)

A rule may carry a description of what the post should be about (`rules.semantic_prompt`, schema v3). Its keyword condition then is an optional pre-filter; an empty one (`And([])`) lets every post of the rule's channels through, and the editor warns that all of them are sent out.

- The rule engine stays synchronous and offline: it applies scope, schedule and keywords only, and the `MatchEvent` lists every matched rule with its prompt (`MatchedRule`).
- The service host finishes the decision (`SemanticGate`): one request per post to an OpenAI-compatible `chat/completions` endpoint (`SemanticClient`) with all pending descriptions numbered; the model answers with the matching numbers or `NONE`. The request carries only `model` and `messages`: reasoning models need room to think before the short answer, and some providers reject a custom temperature or token cap. An empty answer counts as a failed check, not as `NONE`. `MatchEvent.withSemanticVerdicts` keeps keyword rules and the confirmed semantic ones, and priority and read-aloud are recomputed from what is left.
- When the check cannot be done (no endpoint, offline, bad key, rate limit, odd answer) the semantic rules are skipped for that post. Keyword rules on the same post still fire, nothing is retried, and the reason is stored in the `ai.lastError` setting, which the rules screen shows as a quiet note until a check succeeds again.
- Endpoint and model are settings (`ai.baseUrl`, `ai.model`); the API key is in the Android keystore through `flutter_secure_storage`, never in the database, and is deleted on logout. Plain `http://` endpoints are allowed for models on the user's own network, with a warning.
- The rule editor's dry run sends the newest 8 posts that pass the keywords to the model.

### 6.3 Notifications

`flutter_local_notifications` with three Android notification channels, created once:

| App priority | Android channel importance | Behaviour |
|---|---|---|
| silent | LOW | In the shade, no sound, no heads-up |
| normal | DEFAULT | Sound and vibration per system settings |
| urgent | HIGH + `bypassDnd` | Heads-up; DND bypass requires the user to grant notification-policy access, which the app requests when the first urgent rule is created. Android fixes a channel's DND bypass at creation, so the notifier posts on `posts_urgent` until access exists and then creates `posts_urgent_dnd` (and deletes the other); it re-checks before every urgent notification |

Each notification: channel title, post excerpt, thumbnail if present, actions **Listen** and **Open in Telegram**. Tapping opens the post inside the first feed containing that channel. Notifications from the same channel are grouped.

Android 13+ requires `POST_NOTIFICATIONS`; requested during onboarding of phase 2.

## 7. Read aloud

- `TtsService` in the core isolate owns the queue and text preparation; the actual `flutter_tts` calls run in the service host isolate (see Android notes), which the core reaches over a port. A single FIFO queue; a new item never interrupts a playing one unless the user stops it (`flutter_tts.speak` flushes by default, so the queue must wait for `awaitSpeakCompletion`).
- Language: `google_mlkit_language_id` on Android (on-device). Detected code selects a voice from the user's per-language preferences, falling back to the system default for that language, then to the app's default voice.
- Text preparation: strip URLs (say "link"), collapse whitespace, drop emoji and formatting markers, prepend "New post in <channel>". Posts over a configurable length are truncated with "… and more".
- Audio focus: request transient focus with ducking; release on queue drain. Never speak during a phone call (check `audio_session` / telephony state).
- The "Listen" action and auto-read use the same path; the only difference is that a Listen request is spoken right after the current utterance instead of at the end of the queue. The queue never drops items, however far it is behind (founder decision 2026-09-18).

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
- Nothing leaves the device except Telegram traffic, with two opt-in exceptions. Google Drive sync (section 5.5) stores feeds, rules and some settings in the user's own Drive, in a folder only this app can read. And: AI semantic rules (section 6.4) send the text of the posts they check to the endpoint the user configured. No rule of that kind, no request.
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
| 2026-09-18 | Sync goes through the user's Google Drive; no sync backend | Founder decision; keeps the project backend-free |
| 2026-09-18 | Drive access through the Drive API with Google sign-in (app data folder), not the system file picker | Founder decision; works without the Drive app, needs an OAuth client of the founder's Google Cloud project |
| 2026-09-18 | Sync covers feeds with sources, rules and settings; read positions stay per device; merge per item, newest edit wins | Founder decision |
| 2026-09-18 | AI semantic rules use any OpenAI-compatible endpoint; the user enters endpoint, model and key in Settings | Founder decision; no provider lock-in, works with local models |
| 2026-09-18 | Keyword pre-filter of an AI rule is optional per rule, with a warning when empty | Founder decision; the user trades coverage against cost and privacy |
| 2026-09-18 | A semantic check that fails skips that rule for that post, quietly | Founder decision; no retries, no fallback alerts, other rules still fire |
| 2026-09-18 | Read-aloud queue never drops items; Listen requests go next | Found while dogfooding with busy channels; founder chose completeness over freshness |
| 2026-09-18 | A channel added to a feed starts at Telegram's read position | Founder decision while dogfooding: the whole history used to count as unread |
| 2026-09-17 | Web target dropped after the phase 3 build worked | Founder decision, Android only; the build stays in history at 87e10f3 |
| 2026-09-17 | Web stays on tdweb, built from source; no GramJS gateway | tdweb 1.8.67 self-built works end to end, npm 1.8.0 is dead (spike P0-4) |
| 2026-09-19 | Videos play while they download, through a loopback HTTP server over TDLib's partial file | Founder feedback: the official app starts videos much sooner; keeps `video_player` instead of a player with a custom data source |
| 2026-09-19 | Short videos autoplay muted; limits 60 s and 20 MB by default, adjustable in Settings | Founder feedback |
| 2026-09-19 | A tapped video plays in the full-screen viewer at once, orientation is never forced; leaving the viewer pauses it and cancels its streaming download, an autoplayed video returns to muted autoplay. Inline player controls are gone | Founder feedback round 2: behave like the official app |
| 2026-09-19 | The download button on a video fills Telegram's cache and survives leaving the viewer; no export to the gallery | Founder decision, feedback round 2: same as the official app |
| 2026-09-19 | One viewer for photos and videos with album paging, swipe to close and hold for 2×; it replaces the photo viewer and the full-screen video screen | Founder decision, feedback round 2: the parts of the official viewer wanted in this round |
| 2026-09-19 | Picture-in-picture is an in-app mini player over the timeline plus Android's system window when the app is left | Founder decision, feedback round 2. Android's window shrinks the whole activity and cannot float over our own screens, so the official app's two behaviours need two mechanisms |
| 2026-09-19 | Timeline in chat order (oldest on top), opens at the remembered position, else the first unread post | Founder feedback: same behaviour as a chat in Telegram; replaces newest-first and the jump-to-unread action |
| 2026-09-19 | Main screen is a tab bar: `+`, Feeds (the list of feeds), one tab per Telegram folder listing its channels, All channels | Founder feedback; a tab per feed was built first and replaced the same day by the single Feeds tab, founder decision |
| 2026-09-19 | Folder tabs and All channels show channels only | Founder decision; the app stays a channel reader, chatting is a non-goal |
| 2026-09-19 | Feeds have content filters; they apply to the timeline and to rules (a post hidden by every feed with its channel does not notify) | Founder decision; refines "rules never per feed": rules stay per channel or global, filters only silence what no feed shows |
| 2026-09-19 | Posts and comments are drawn like the official app: bubbles with avatars, coloured names, mosaic albums, formatted text, footer with views and time | Founder feedback round 3; the group-chat form, since a feed mixes channels and avatars were asked for everywhere |
| 2026-09-19 | The unread dot sits beside the time in a reserved slot and only fades | Founder decision, feedback round 3: the dot in front of the title made the title jump when a post became read |
| 2026-09-19 | A feed made from a Telegram folder is a one-time copy of its channels | Founder decision, feedback round 3; no link to the folder, no schema change |
| 2026-09-19 | Autoplay keeps the switch and limits of F-6; they are also reachable from the menu of a video post | Founder feedback round 3: the settings existed but were overlooked |
