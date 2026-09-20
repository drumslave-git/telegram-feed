# telegram-feed — Plan and Progress

Single source of truth for what is done, in progress, and next. Every session updates this file and commits it.

Legend: `[ ]` not started, `[~]` in progress (name the branch or session note), `[x]` done (commit hash), `[-]` dropped (reason).

**Current phase:** feedback round 7 (founder, 2026-09-20); rounds 1 to 6 and P4-1, P4-2 are closed. **Next task:** H-37 (the channel picker takes several channels at once).

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
- [x] P2-7 Read-aloud settings screen. `ReadAloudScreen` (speed, pitch, maximum length, fallback language, voice per language from the engine's voice list, preview) writing the `tts.*` settings the service's `TtsService` reads; reached from Settings.

## Phase 3 — Interactions and web

- [x] P3-1 Reactions. `Post.reactions` (emoji reactions with counts and own choice, refreshed on `updateMessageInteractionInfo`), gateway `availableReactions` / `react` end to end, reaction chips and a picker on the post card. (ce5fa0d)
- [x] P3-2 Discussion thread view and reply. Gateway `discussion` / `threadHistory` / `reply` / live `comments` (TDLib message threads in the linked discussion group, sender names resolved and cached), `Post.replyCount`, `ThreadScreen` with a reply composer opened from the card's Comments chip. (4b8d9af)
- [x] P3-3 Share / copy link. `telegramShareUri` / `shareText` in core, card overflow menu with Share (system sheet through `share_plus`) and Copy link (clipboard). (74dcba3)
- [x] P3-4 Web build. `TdwebTransport` (tdweb via `dart:js_interop`, JSON strings both ways, `readFile` blobs for media), `AppHost` interface with `CoreHost` (Android) and `WebHost` (gateway and rule engine in the page, drift on self-built `sqlite3.wasm`), `BrowserNotifier`, Web Speech TTS through `flutter_tts` with script-based language guessing, `tool/build_web.sh` static bundle, CI compiles the web build. (87e10f3) Dropped afterwards, see Dropped.

## Stabilisation (before phase 4, decided 2026-09-17)

- [x] S-1 Dogfooding pass on the emulator (2026-09-18, spare account, 12 channels): login, feeds, editor, timeline, read marks, video, reactions, share, copy link, Open in Telegram, rules with dry run, background matches, grouped notifications, tap and Listen actions, background read-aloud, themes, settings. Findings are S-2 to S-8 below, all fixed and re-verified on the device.
- [x] S-2 Rule dry run scanned only 3 posts: TDLib answers `getChatHistory` with short pages (often the single cached message). `TdlibGateway.history` now pages until the limit or the end; local reads stay a single probe. (287f028)
- [x] S-3 Comments chip appeared on channels without a discussion group and opened a dead end. `Post.canComment` (from `reply_info`) gates the chip. (287f028)
- [x] S-4 Open in Telegram did nothing without the Telegram app: url_launcher throws on `tg://` instead of returning false, so the `t.me` fallback never ran. `launchFirst` tries each link and survives the exception (timeline and notification action). (af041b2)
- [x] S-5 A channel added to a feed counted its whole history as unread. The feed's mark now starts at Telegram's read position (`Channel.lastReadMessageId`, founder decision 2026-09-18). (02edf46)
- [x] S-6 Urgent rules never bypassed Do Not Disturb when policy access was granted after the channel existed (Android fixes the flag at channel creation). The notifier switches to a `posts_urgent_dnd` channel once access is granted, checked before every urgent notification. (84ff13d)
- [x] S-7 The notification's Listen action was swallowed when the post already waited in a backed-up read-aloud queue. Explicit requests are now spoken right after the current utterance. The queue itself never drops items (founder decision 2026-09-18). (ad122c9)
- [x] S-8 Launcher and notification shade showed the app as `telegram_feed`; the label is now `telegram-feed`. (ad122c9)

## Tooling

- [x] T-1 Automatic versioned debug releases: `packages/versioning` (next semantic version and changelog from conventional commits), `debug-release.yml` (after green CI on main: tag, debug APKs signed with a fixed key, prerelease), `release.yml` now promotes an existing tag to signed APKs by hand.

## Feedback round 1 (founder, 2026-09-19)

Founder feedback after using the debug release. Decisions taken the same day are in the ARCHITECTURE decision log. Phase 4 continues afterwards.

- [x] F-1 The battery-optimisation banner stays after the exemption is granted until the screen is reopened. `BatteryBanner` re-checks when the app resumes and after the system dialog closes. (bca8076)
- [x] F-2 The channel picker's list is covered by the keyboard; the last channels cannot be reached. The picker sheet is padded by the keyboard inset (`viewInsets`) and respects the safe area; widget test with a simulated keyboard. (0205dbb)
- [x] F-3 Tapping a photo does nothing: full-screen viewer with zoom and album paging. `PhotoViewerScreen`: full-size file, pinch and double-tap zoom, swipe between the photos of an album. (e78d9b7)
- [x] F-4 Video player: controls, full screen, double-tap seek at the edges; fix sound with an endless spinner. `VideoSessions` (playback lives outside the widget tree, one player per file shared by the inline and the full-screen view, one video with sound at a time), `VideoStage` (scrubber with buffered range, speed, mute, replay, 10 s double-tap seek with a hint, double tap in the middle for full screen), `FullscreenVideoScreen` (immersive, landscape for wide videos). Timeline rows are keyed by post: without keys a new post shifted player state under another post, the likely cause of sound with a spinner. Verified on the emulator. (2e44288, 97bad8c)
- [x] F-5 Videos start much slower than in the official app: play while TDLib downloads instead of after. `MediaServer` (loopback HTTP with a secret path, byte ranges served from TDLib's partial file, a range that is not there yet re-aims the download; headers go out at once through a detached socket), gateway `downloadFrom` / `downloadedPrefix` / `cancelDownload`. On the emulator videos of 8, 105 and 46 MB were ready after 1.1, 0.7 and 1.8 s, the last one with its index at the end of the file. The HTTP 416 of the first run did not come back; a file without a known size is now downloaded whole instead of streamed, and the server logs a range outside the file. (2e44288, 97bad8c)
- [x] F-6 Autoplay of short videos, with settings. `AutoplayPolicy` and `AutoplayScope` (settings `media.autoplay*`, synced; defaults 60 s and 20 MB), start at 60 % visible, pause below 20 %, first tap turns the sound on; Media section in Settings. Verified on the emulator; settings golden regenerated on Linux. (60636c0)
- [x] F-7 Timeline runs oldest to newest like a Telegram chat and opens at the remembered position or at the first unread post. Reversed positioned list (index 0 = newest at the bottom), opening position decided before the list is built (notification post, remembered row, first unread under an `Unread posts` divider, newest), a post is read once its end was on screen, new posts wait on a badge button while the user reads older ones; the app-bar jump action is gone. Widget tests for each case, verified on the emulator, timeline goldens regenerated. (2865e4c)
- [x] F-8 Tabbed main screen: `+`, Feeds (the list of feeds), one tab per Telegram folder (its channels), All channels. `HomeScreen` with `ChannelList` (photo, newest post, time, unread count; search on All channels), gateway `chatFolders()` and richer `Channel`, `TimelineView` split from `TimelineScreen` so one channel opens as a timeline with Telegram's own read position. A tab per feed was built first; the founder replaced it with the single Feeds tab the same day. Verified on the emulator; `home.png` golden replaces `feeds.png`. (632d622)
- [x] F-9 Account section in Settings shows photo, name, username, phone, bio. `AccountHeader`: profile photo (initial until it loads), name with a Premium star, username, phone with `+`, bio from `getUserFullInfo`, Telegram ID; `UserInfo` gained `photo`, `bio`, `isPremium`. The F-8 gateway test for folders compared records holding lists and failed unnoticed; fixed here, and the whole `tool/ci.sh` now runs before every commit. (44cb11a)
- [x] F-10 Per-feed content filters (media presence, media type, minimum video length, text length); they apply to the timeline and to rules. `FeedFilter` in `core` (media presence, media kinds, minimum video length, minimum length of text posts), `feeds.filter_json` (schema v5 with migration test), filtering in `FeedTimeline`, read marks pass over hidden posts (`coveredFrom`), the rule engine drops a post that every feed with its channel hides, the filter syncs with the feed, `Show` row and sheet in the feed editor. Opening now also settles at the newest post when the unread ones nearly fit the screen. Verified on the emulator. (086a32a)
- [x] F-11 Application icon: three channels merging into one feed, white on a blue-to-teal gradient. Adaptive icon as vector XML (foreground, gradient background, monochrome layer for themed icons), PNGs for launchers without adaptive icons rendered by `app/tool/generate_icons.dart` (preview in `docs/icon.png`), and `ic_stat_feed` as the status bar icon of the service and post notifications. Seen on the emulator in the app drawer and the notification shade. (c3356ca)
- [-] F-12 Two login notices in the official app after one login: the founder logged in once and Telegram's Devices list shows one telegram-feed session, so the app created a single authorization. Nothing in the code opens a second one (one TDLib database, one core isolate; a second instance could not lock the database). Why Telegram showed two notices was not established; to be reopened if two sessions ever show up.

## Feedback round 2 — video viewer like the official app (founder, 2026-09-19)

Founder decisions of the same day: the download button fills Telegram's cache (no gallery export); an autoplayed video goes back to muted autoplay after full screen, any other video is paused and its streaming cancelled; swipe to close, hold for 2×, picture-in-picture and album paging belong to this round.

- [x] V-1 A tap plays in full screen at once, in the orientation the device has (nothing is forced). Leaving full screen pauses the video and cancels its streaming download; an autoplayed video returns to muted autoplay. Inline controls go away, the timeline only shows posters and muted autoplay. `VideoSession.retainForViewer` / `releaseFromViewer`, `InlineVideo` for rows, `VideoStage` only in the viewer. (e07347e)
- [x] V-2 Zoom in full screen: double tap in the middle zooms in and out, pinch zooms, a drag moves the zoomed picture; the edges keep the 10 s seek. `InteractiveViewer` in `VideoStage`, helpers in `media/zoom.dart`. (a3ee5d5)
- [x] V-3 Download button in the top left corner of a video (timeline and viewer): size, progress ring, tap again cancels. The download goes to Telegram's cache and survives leaving full screen. `VideoDownloads` + `VideoDownloadButton`; timeline goldens regenerated. (c8efba1)
- [x] V-4 Swipe down or up closes the viewer with a fading background; holding a finger on the video plays at 2× while held. `SwipeToClose`, see-through viewer route, autoplay rests under it. (378ee21)
- [x] V-5 One viewer for photos and videos: swiping sideways pages through the album of the post. `MediaViewerScreen` replaces `PhotoViewerScreen` and `FullscreenVideoScreen`; only the page in front has a session. (5afc101)
- [x] V-6 Picture-in-picture: a mini player floating over the timeline, and Android's system PiP window when the app is left while a video plays. `MiniPlayer` (overlay, drag, pause, back to the viewer, close), `SystemPip` + `PipHost` + `MainActivity` (`tf/pip`, auto-enter from Android 12), the foreground video pauses when the activity is stopped. The download button also learns live when a file got complete by streaming. (faf12fd)

Verified on the emulator (NewsFeed, 2026-09-19): a tap opens the viewer at once and a 22 MB video plays after 2.4 s; portrait stays portrait and a rotated device is followed; double-tap zoom, drag of the zoomed picture, hold for 2×, album position, swipe down to close; leaving after 1.2 s of playback cancels the streaming download (`media: … closed, streaming download cancelled`); the button shows `39 MB / 45 MB` with a ring and is gone once the file is complete; mini player over the timeline; Home turns the activity into a portrait system window showing only the video, coming back continues in the viewer, dragging the window away stops the audio track. Found and fixed there: the system window was armed as 16:9 because a session counted as playing before its player was initialized.

## Feedback round 3 — posts like the official app (founder, 2026-09-19)

Founder decisions of the same day: the unread dot sits next to the time in a reserved slot, so nothing moves when a post becomes read; a feed made from a folder is a one-time copy of its channels; autoplay keeps the settings of F-6 (they were overlooked), they only become easier to find.

- [x] R-1 Long press on a folder tab offers "Create feed from folder": a feed with the folder's name and its current channels, in the folder's order, each starting at Telegram's read position; the Feeds tab comes up with an Open action. (7b3703e)
- [x] R-2 Posts look like the official app: bubbles on a tinted chat background, the channel's avatar beside the bubble, coloured channel name (Telegram's seven peer colours), views / edited / time in the bottom right corner on the last line of the text (`BubbleText`, a render object of its own) or on top of the pictures when nothing follows them, the unread dot in a reserved slot beside the time, reaction pills, a comments bar, a round share button beside the bubble, day pills between days; a tap or long press on the bubble opens the menu (reactions strip, Open in Telegram, Comments, Share, Copy link). `PostCard` moved to `feeds/post_card.dart`. Older posts are now fetched as soon as the loading row is built: with the shorter rows its spinner could end up just off screen and turn for ever. (8d25f14)
- [x] R-3 Albums as Telegram's mosaic: `layoutAlbum` ports the grouped layout of the official apps (hand-made arrangements for two to four pictures, row splitting for more), `AlbumMosaic` crops photos and videos into the cells (`MediaView.fill`), audio and documents stay a list. The timeline goldens got an album; the dark golden had never been dark (it was captured before the theme animation ran), fixed in the test. (8d25f14)
- [x] R-4 Formatted text: `Post.entities` (`TextEntity` with offset, length, kind, url) mapped from TDLib's entities and carried through the isolate codec; `FormattedText` cuts the text at every entity boundary, so nested and overlapping formatting works: bold, italic, underline, strikethrough, monospace, quotes, spoilers (covered until tapped), links, mentions and e-mail addresses that open, coloured hashtags. Rules, read-aloud and sharing keep using the plain text. A test of `BubbleText` found that the footer never shared the last line of the text (the check ignored line leading); fixed. (b9028da)
- [x] R-5 Avatars everywhere else: comments carry `authorId` and `authorPhoto` (the gateway resolves each sender once: user or chat), the thread view shows the post as its timeline row on top and comments as bubbles with the author's photo, coloured name, formatted text and the time in the corner, own comments on the right; feed editor, channel picker and the rule scope list show channel photos. Found on the emulator and fixed here: the footer squeezed the reactions into a narrow column (the pills now use the full width, the footer takes the free end of the last row), and a bubble sized to the pixel pushed the time of a short comment to a line of its own. SPEC and ARCHITECTURE (5.7, new 5.9, decision log) describe the round. (a94e9e8)
- [x] R-6 Autoplay settings are easier to find: the menu of a post with a video has "Video autoplay settings", a sheet with the same switch and limits (`showAutoplaySettings`, `AutoplaySettings`); the Settings section is called "Video autoplay" instead of "Media". (99c3731)

- [x] R-7 Found in the emulator's log while checking this round: sync ran every 16 seconds for ever. Each run writes its time into `settings`, the watcher sees that table, so every run scheduled the next one (since P4-1). The controller now remembers what the device held after its last run (`exportLocal().encode()`) and a change notification only leads to a Drive request when the synced data differs; device-local settings no longer trigger one either. (347b4c5)

- [x] R-8 Founder, after seeing the round: avatars take too much space. The avatar moved into the bubble's title line, at its right end (`BubbleTitle`, posts and comments), and the share button beside the bubble is gone (founder decision; sharing stays in the menu), so bubbles span the whole width. Seen on the emulator: title line with name and photo, a five-photo mosaic from edge to edge. (b34ee69)

Verified on the emulator (NewsFeed, 2026-09-19, light and dark; before R-8 moved the avatars): rows show the channels' photos, coloured names, bold, quotes and links in the text, views, "edited" and the time on the last line; a photo with a video sits side by side and three photos as one on top of two; reactions use the full width with the time at the end of the last row; the menu opens on a tap on the text with the channel's emoji on top, a tap on a picture still opens the viewer; the comments screen shows the post with its autoplaying video on top and comments with avatars (initials for authors without a photo) and coloured names; the long press on the "Real News" tab offers "Create feed from folder" (not created there: the emulator syncs its feeds to the founder's Drive; the creation itself is covered by the widget test); the menu of a video post opens the autoplay sheet; after R-7 the log shows one sync at launch and none in the following 70 seconds.

## Feedback round 4 — channels and feeds like the official app (founder, 2026-09-19)

Founder decisions of the same day: a feed is merged channels, so search, date navigation and shared media run over all of a feed's sources as one merged list and obey the feed's filter (F-10); the feed editor becomes the feed's info screen and gains the same media tabs; mute and leave stay out of the channel info screen because notifications are the app's own rules.

- [x] C-1 Gateway: search in a channel (query and media filters, paging, total count), the post nearest a date, and channel info (description, subscribers, link), end to end through the core isolate. `searchHistory` pages like `history` because TDLib answers short pages, `messageIdByDate` turns a 404 into 0, `channelInfo` reads `getSupergroupFullInfo` and the chat's big photo. (b07a649)
- [x] C-2 Merged search and merged media over a feed in `core`: a paged k-way merge over the sources that obeys `FeedFilter`, and the nearest post to a date across sources. `FeedSearch` (albums stay uncollapsed, `totalCount` is Telegram's upper bound until the search is exhausted) and `anchorsForDate`; ARCHITECTURE 5.10. (07c0efe)
- [x] C-3 Search in the timeline: the app bar turns into a search field, results are rows with channel, snippet and date, a tap opens the timeline at the post, up and down step through the results with "3 of 47". Opening a result anchors the timeline at it (`jumpToPost`, `FeedTimeline.loadNewer`, gateway `historyAfter`), which C-4 reuses for dates; the corner button rebuilds the live timeline. Timeline goldens regenerated (the search action). (3397e41)
- [x] C-4 Jump to date: a calendar in the search bar and on the day pill; the timeline opens at the nearest post of that day (in a feed, the nearest across sources). `pickDate` / `jumpToDate` settle on the first post of the day; a date before everything the sources have only reports that. (19b9b57)
- [x] C-5 Channel info screen: the app-bar title opens photo, name, @username, subscribers, description and the link, with the shared media tabs Media, Files, Links, Music and Voice. `ChannelInfoScreen` + `SharedMediaTabs` (one `FeedSearch` per tab, media as a grid that opens the viewer over the whole tab). (1fe8594)
- [x] C-6 The feed editor gains the same media tabs, merged over the sources and obeying the feed's filter. The editor is the feed's info screen: a "Channels" tab with sources, filter and picker, then Media, Files, Links, Music, Voice over all sources; the feed's title in the timeline opens it. Feed editor golden regenerated (the tab bar). (c2d2862)
- [x] C-7 Scroll-to-bottom button with the unread counter, as in the official app. The badge counts the unread posts between the reader and the newest one (`FeedTimeline.unreadBefore`) plus the ones that arrived while reading; the button also leaves a jumped timeline. Timeline goldens regenerated (the badge). (88ede03)

- [x] C-8 Found while checking the round on the emulator: a date jump landed at the end of the chosen day, not at its beginning. The first page of history covers only thirty rows, and a busy feed has many more in a day, so the oldest loaded row of the day was taken for its first post. The timeline now pages down to the day before (capped at 300 rows) and then settles on the first post of the day. (6696d99)

- [-] Mute and leave in the channel info screen: the app has its own notification rules (founder decision 2026-09-19).
- [-] Pinned posts bar, selecting several posts, search over all channels from the home screen: not part of this round (founder decision 2026-09-19). All three were taken up in round 7 (H-12, H-17, H-25).

Verified on the emulator (NewsFeed and Real News, 2026-09-19): the magnifier turns the app
bar into a search field and a query answers with the posts of all three channels, each row
with its channel, the marked words and the time; a tapped result opens the timeline at that
post with "3 of 42131" at the bottom, and the arrows step to the older and the newer match
with the surrounding posts of the other channels around them. The calendar opens from the
search bar and from a day pill (pre-set to that day), a date lands under the "September 15"
pill with the last post of the 14th above it, and the button at the corner carries the unread
count. A channel's title opens its info: photo, 882K subscribers, description, `@ssternenko`
with its link and a copy button, and the tabs Media (a grid with the length on videos, a tap
opens the viewer at "1 of 30"), Files, Links (URL, text and day), Music, Voice. The feed's
title opens the editor with the Channels tab and the same media tabs over all its channels.
Found and fixed there: C-8.

## Feedback round 5 — notifications (founder, 2026-09-19)

Founder decisions of the same day: "notify about every post" is a rule with an empty condition, not a second per-channel switch, so scope, priority, schedule and read-aloud carry over; the permanent service notification gets two settings, a minimal mode and a master switch for background watching (the minimal mode was dropped again in N-6 the same day, after the emulator showed Android ignores it).

- [x] N-1 The group summary counts the posts Android still holds (`getActiveNotifications` for the group, plus the one being shown) instead of a tally that only ever grew, and a cancellation that empties a group takes the summary down with it. (7b0e0c4)
- [x] N-2 The service notification is configurable: `service.minimalNotification` posts it on `core_min` at `IMPORTANCE_MIN` (no status-bar icon, bottom of the shade) instead of `core` at `LOW`, and `service.background` off keeps the service from starting at all, so the core runs in-process and rules only notify while the app is open. Both are read when the core is brought up and so apply at the next app start: the core cannot change host while TDLib is polling (ARCHITECTURE 8). Device-local, not synced. (e81ae65) The minimal half was dropped again in N-6 after the emulator showed it changes nothing; the background half stays and is verified below.
- [x] N-3 A rule with no condition notifies about every post of its channels. The evaluator already matched `And([])`; the editor now saves it for plain rules too, says so under the condition, and the rules list shows "every post". (2e13123)

- [x] N-4 A filtered feed shows the whole post: an album whose parts do not all pass is shown complete, with the caption that sits on the part a media-kind filter would drop. `FeedFilter.wholePost` (on for every feed, old filters included) and `mayShow`; `FeedTimeline` carries a hidden part into the row its siblings open (held per chat and album until that row exists); the rule engine and the search by words ask `mayShow` too, the shared media tabs stay strict; "Show the whole post" checkbox in the feed editor's Show sheet. (74b7498) Verified on the emulator (NewsFeed, 2026-09-19, light and dark): with the feed filtered to videos, a two-part post of Лачен пише keeps the picture beside the video and its caption, and a three-part post of INSIDER UA keeps the picture under its two videos; unchecking the box leaves the bare videos in both, and "Show everything" put the feed back as it was.

- [x] N-5 Found while verifying N-2 on the emulator: switching background watching off killed the app on the very next start. Android restores the foreground service before Dart runs, the host stops it again, and the core it had spawned left its `td_receive` pump isolate polling, so the app's own core made TDLib abort the process ("Receive must not be called simultaneously from two different threads"; two tombstones). A core now hands TDLib back on a `shutdown` call of the port protocol (close the client, wait for `authorizationStateClosed`, kill the receive isolate and wait for its exit), the service's `onDestroy` waits for its `onStart` first, and `CoreHost` waits for the core's port to disappear before spawning one of its own. (95af990)
- [x] N-6 Found in the same run: "Keep that notification minimal" changes nothing a user can see (Android raises a foreground service's channel to `IMPORTANCE_LOW` whatever is asked for, and a silent notification has had no status-bar icon since Android 12), and it only ever reached a service the app started itself. The switch, the setting and the `core_min` channel are gone (founder decision 2026-09-19); the Background section says instead what Android allows. (cb5c409)
- [x] N-7 Found in the dry run of the N-3 rule ("16 of the last 20 posts match"): a post with no text at all never notified, because the evaluation drops such posts before the conditions. A post without text now passes exactly the rules with no condition, and what it carries takes the place of the text ("Photo", "Video", the file's name); the notification, the dry run and the rules list say so. (e4c0e8b)

Verified on the emulator (2026-09-19, spare account, rule "Every post test" on INSIDER UA,
deleted afterwards): the editor shows "No condition: every new post from this rule's
channels notifies", saves without keywords, and the rules list reads "INSIDER UA · every
post" (N-3); a new post of that channel raised a notification with the channel's name, the
post's text and the Listen / Open in Telegram actions, and tapping it opened the feed at
that post. The group summary read "1 new post" while one post was in the shade, and "1 new
post" again for the next one after the first had been tapped away, where the old tally
would have said 2; Android took the summary down with its last post (N-1). Background
watching off left no permanent notification and started the core in-process, with the
handover in the log (`core: handed TDLib back` → `service: core down` → the app's own
`core: TDLib 1.8.67`) and no crash (N-5); the Background section now has one switch and the
note about Android (N-6); the dry run says "20 of the last 20 posts match" with "Photo" and
"Video" under the channel's name (N-7). Before N-6 the minimal mode was seen to post on
`core_min` and to look exactly like `core` in the shade.

## Feedback round 6 (founder, 2026-09-20)

Founder decisions of the same day: channels the account archived in Telegram stay out of the
app's lists, but a channel that only a chat folder holds is read from that folder's list; feed
tags show in the home channel lists, in the feed editor's channel picker and in the rule
editor's scope list.

- [x] G-1 A folder joined through an invite link showed its tab but no channels: the app built every channel list from Telegram's main chat list, which does not hold such channels. `myChannels()` now walks the main list and every folder, each channel once, and logs where they came from; the home screen asks for the folders first. The archive stays unread. (d86f15f) The emulator confirmed the cause: `75 channels from the main list`, `6 channels from folder "🙂"`.
- [x] G-2 A video the timeline autoplays starts from the beginning when it is tapped open in the viewer: `retainForViewer` seeks to zero unless it is taking the session over from the mini player or the system window, where the watcher is continuing the video. (7538f02)
- [x] G-3 "Save to Saved Messages" in the post menu: gateway `saveToSavedMessages` forwards the post and every part of its album into the chat with oneself, through the core isolate; the menu scrolls now, since its entries no longer fit on a short screen. (2045967)
- [x] G-4 Space between the newest post and the bottom edge of the screen: the reversed list carries 8 px plus the system inset at its visual bottom. (f1dd955)
- [x] G-5 Channel lists tag each channel with the feeds it belongs to: `feedNamesByChat` in `app_db` and `FeedTags` chips in the home lists (live as feeds and sources change), the feed editor's channel picker and the rule editor's scope list. (e09734a, tests 6639200)

- [x] G-6 The icon in the status bar had the launcher's blue background instead of a plain white glyph. Two paths could produce it: `flutter_local_notifications` keeps its default icon in shared preferences, where the UI isolate's initialisation (`@mipmap/ic_launcher`, there only for tap handling) decided the icon of the posts the service shows afterwards; and Android restores a running foreground service with the notification content saved when it was started, which on an old install comes from a build that named no icon. Every notification names `ic_stat_feed` now, the UI initialises with it too, and the service's minute-by-minute update names it again, so a stale one corrects itself. (8444b4f) Seen on the emulator: a rule notification about a new post of INSIDER UA put the bare glyph in the status bar, next to the system's own icons and with no background (`icon=Icon(typ=RESOURCE … 0x7f08007b)` for the post and its group summary); the permanent service notification shows the same glyph once its channel is raised to Default, which Android otherwise keeps out of the status bar. The rules used for the check were written straight into the database with a null `sync_id` (nothing to sync) and deleted afterwards, and the channel was put back to Silent.

Verified on the emulator (2026-09-20, spare account): the 🙂 folder that had been joined
through an invite link lists its six channels with photos, previews, times and unread counts,
and the log names the folder as their only chat list (G-1); a seven-second video that had
been autoplaying in a row opened in the viewer at `0:00 / 0:07` with the sound on (G-2); the
menu of a post carries "Save to Saved Messages" and answers "Saved to Saved Messages", with
no error from Telegram — the official app is not installed on the emulator, so the arrival is
visible in the founder's own Telegram (G-3); the newest post keeps its distance from the
bottom edge and from the gesture bar (G-4); the channels of the Real News tab each carry a
"NewsFeed" tag under their preview (G-5). The channel picker and the rule scope list list
every joined channel of the account, which is not a screen to capture, so widget tests cover
their tags instead.

## Feedback round 7 (founder, 2026-09-20)

The round started with two findings of the founder's own (H-1, H-2) and then with a
feature-by-feature comparison of the app against the official Telegram Android app as a
channel reader: every difference found in the code was put to the founder, who picked what
the app takes over and dropped the rest (the list at the end of this round, and the Dropped
section). The order is the founder's: what is most visible while reading comes first. Each
task updates SPEC.md and ARCHITECTURE.md as it lands, so those two keep describing the app
as it is; the decisions themselves are in the ARCHITECTURE decision log already.

The comparison left out what the spec calls a non-goal: chats, groups, calls and stories,
joining or leaving channels, editing Telegram's chat folders, muting a channel (rules take
that place) and sponsored posts, which this app will never show.

- [x] H-1 The menu of a folder tab could hardly be called when the folder's name is a single
  emoji: the long press only covered the label, which is a few pixels wide. Tabs carry their
  own padding now (`labelPadding` of the bar is zero) and a minimum width of 72 px, so the
  press is answered anywhere in the tab. (6f62b46)
- [x] H-2 The day of the topmost post floats over the timeline while it is scrolled, as the
  date does in the official app: `FloatingDay` fades in with a scroll the reader started
  (`UserScrollNotification`, so opening a feed or a date jump brings nothing out) and fades
  out 900 ms after the list comes to rest. A tap opens the calendar on that day, like the day
  pills between the posts. (93771eb)

Verified on the emulator (2026-09-20, spare account, NewsFeed): a long press inside the 🙂
folder tab but well left of the glyph opens "Create feed from folder", where the same press
used to reach nothing (H-1). The timeline opens with no pill in sight, a scroll upwards puts
"Today" over the top of the list, it is gone three seconds after the list comes to rest, and a
tap on it while it is up opens the calendar on that day ("Jump to date", Sun, Sep 20); a tap
after it has faded goes to the post underneath, as it should (H-2).

### In every post (most visible while reading)

- [x] H-3 Link previews: the card under a post with a link (site, title, description, picture),
  which TDLib hands over ready-made and the gateway used to drop. `LinkPreview` in the gateway
  models from TDLib's `linkPreview` (picture, video flag and length per kind of link), through
  the isolate codec, and `LinkPreviewCard` in the bubble: accent bar and tint in the channel's
  colour, the picture wide or as a small square as TDLib asks, above or below the card's words,
  the card itself above or below the post's text, a play badge and the length on a video link.
  A tap anywhere on it opens the link. A preview is not `Post.media`, so a post with a link
  stays a text post for a feed's filters. (ce93ce8) Verified on the emulator (2026-09-20,
  NewsFeed): searching the feed for "youtube" and opening a result of STERNENKO shows the post
  with its own text and link and, under it, the card — thumbnail with the play badge, "YouTube"
  in the channel's green, the video's title in bold and its description, on the tinted block
  with the accent bar; a live stream has no length, so no length badge; a tap on the card handed
  the link to the YouTube app. Light and dark are in the timeline goldens, which gained a
  picture-less card.
- [x] H-4 "Forwarded from" header: `ForwardOrigin` from TDLib's four origins (channel with the
  original post, chat, user, hidden sender with the name it shows), named by the gateway through
  the sender cache of the comments — one request per origin and session — and drawn under the
  title line as the official app does, signature and all. A tap opens the original post when the
  account follows that channel, and says so when it does not.
- [x] H-5 Reply and quote preview: `ReplyTarget` from TDLib's `reply_to` (the answered post's
  chat and id, the quote the author picked, the words of the post otherwise, a thumbnail of its
  media, and whose post it was for a reply across chats). Inside the channel TDLib gives the ids
  alone, so the gateway fetches the answered post once and keeps its words. `RepliedPost` draws
  the quote block above the text; a tap jumps to that post in the timeline, or opens the channel
  it belongs to when the account follows it.
- [x] H-6 Copying text out of a post: "Copy text" in the post menu (absent on a post without
  words) and a copy button at the end of every monospace block, which copies that block alone
  and says so.
- [x] H-7 Text size for posts: a slider in Settings' Appearance section from 80 % to 160 % in
  5 % steps, with a line of text at the chosen size beside it. `PostTextScale` sits above the
  navigator and hands the factor to every post card and to the comments through a `MediaQuery`
  of their own, so the rest of the app keeps the system's text size. Kept in `settings`
  (`appearance.postTextScale`) and synced like the theme.
- [x] H-8 Swipe back: the app's themes carry `CupertinoPageTransitionsBuilder` for every
  platform, so screens slide in and a drag from the left edge closes them, as everywhere in the
  official app. A drag anywhere else still belongs to the screen, and the media viewer has a
  route of its own and keeps its swipe down to close.
- [x] H-9 Double tap on a post sends the quick reaction: a thumbs up until the reader reacts
  with something else from the menu, which then becomes the quick one (`reactions.quick`). A
  second double tap takes it back. Two things followed from Flutter's gesture arena: the menu
  now opens on a long press only, because a plain tap would swallow the second tap of the
  double one (as it does in the official app); and the recognizer sits on the post's words, or
  on the pictures of a post without words, not on the whole bubble — a recognizer there holds
  the arena for 300 ms and made every reaction pill, comments bar and picture answer late.
- [x] H-10 Stickers and round video messages: `StickerMedia` (file, format, size, the emoji it
  stands for, a still thumbnail) and `VideoMedia.isVideoNote`. `StickerView` draws a `webp`
  sticker as a picture, a `tgs` one through Lottie (Telegram's gzipped Lottie, `lottie` added to
  the app), and a `webm` one as a silent looping video, all at their own proportions instead of
  the bubble's width; a round video message is the ordinary player clipped to a circle. Neither
  opens the media viewer, and both carry a name for read-aloud, search and rule notifications
  ("A Sticker", "Video message"). A sticker counts as `other` for a feed's media filters.
- [x] H-11 Custom emoji in a post's text: `TextEntityKind.customEmoji` with the sticker id
  (dropped until now), the gateway's `customEmoji(ids)` over `getCustomEmojiStickers` with a
  cache of its own and one request per text, and `FormattedText` drawing each one as its
  sticker at the height of a line — animated ones animate, since they are stickers like any
  other. An id Telegram does not know, or a text drawn without a gateway, keeps the plain
  emoji that stands in the text.
- [x] H-12 Pinned post bar: `pinnedPost(chatId)` over TDLib's `getChatPinnedMessage` (a channel
  with nothing pinned answers with an error, which the gateway turns into none) and `PinnedBar`
  over a channel's timeline — the pin, "Pinned post", one line of what it says, a tap that jumps
  to it and a cross that puts it away for the visit. A feed mixes channels and gets no bar
  (founder decision, round 7). (Reopened from round 4.)

### Reading flow and the lists

- [x] H-13 Mark everything read: `MarkRead` moves the marks of a feed's channels (or of a
  folder's channels in every feed that holds them) to the newest post each channel has, and
  tells Telegram the same through `markViewed` unless read sync is off. "Mark all read" sits in
  the feed's row menu and in the long-press menu of a folder tab; H-15 adds it to a channel row.
- [x] H-14 Unread counts on the folder tabs: a badge with the number of the folder's channels
  that have posts the account has not read, which is how Telegram counts on its own tabs.
- [x] H-15 Long press on a channel row opens a menu: "Mark all read" (H-13's action for that
  one channel), "Channel info", and "Add to a feed", which lists the reader's feeds, greys out
  the ones the channel is already in, and adds it starting at Telegram's read position as the
  feed editor does.
- [x] H-16 Connection status: `ConnectionStatus` from TDLib's `updateConnectionState`, a stream
  of its own over the core port, and `ConnectionTitle` under the title of the home screen and of
  every timeline — "Connecting…", "Waiting for network…", "Connecting to proxy…", "Updating…",
  and nothing at all once it is ready.
- [x] H-17 Selecting several posts: "Select" in the post menu starts it, every tap then picks
  or drops a row (the row answers nothing else while the timeline selects, and carries a tick),
  and the app bar becomes "N selected" with Copy text, Share and Save to Saved Messages, each
  over every picked post, oldest first. Forwarding to a chat stays out: this app does not write
  to chats. (Reopened from round 4.)
- [x] H-18 A t.me link inside a post that points at a channel the account follows opens in our
  own timeline, post and all: `telegramTargetOf` reads `t.me/<name>[/<post>]`, `t.me/c/<id>/<post>`,
  `tg://resolve` and `tg://privatepost`, and leaves invite links, sticker sets and web pages to
  the apps that handle them.

### Media

- [x] H-19 Voice and music can be dragged to seek and played at 1×, 1.5× and 2×: the sound
  moved out of the widget into `AudioSessions`, the app's one player, behind an `AudioEngine`
  interface (`just_audio` in the app, a fake in the tests, as `Speaker` does for read-aloud).
  The row shows play or pause, a slider, the position and the length, and the speed button.
- [x] H-20 A player bar under every screen while a voice message or a song plays
  (`AudioBarHost` in the app's builder, so it survives every route): the name, the position
  and length, play or pause, the speed and a cross that stops it. The sound is the session's,
  not the post's, so scrolling away or leaving the screen does not cut it off.
- [x] H-21 The viewer pages through the media of the whole timeline instead of the post's own
  album: the card hands it every picture and video the timeline holds, newest first, opened at
  the one that was tapped, and the viewer asks for more when the reader comes within two pages
  of the older end — which pages the timeline itself, so the feed's filter and its channels are
  obeyed without a second kind of search.
- [x] H-22 The viewer says which channel a picture came from, on what day, and what its post
  said — the caption over a dark band at the bottom — and carries Share and Save to Saved
  Messages, which act on that post. `ViewerDetail` travels with the items, so the details grow
  with them as older pages load.
- [x] H-23 "Save to gallery" in the viewer: a `tf/gallery` method channel copies the file into
  `Pictures/telegram-feed` or `Movies/telegram-feed` through `MediaStore`, which asks for no
  permission for a file the app wrote itself on Android 10 and later. The file is downloaded
  first when it is not in the cache yet. Replaces the round 2 decision that the download button
  only fills Telegram's cache; that button stays as it is.
- [x] H-24 Automatic downloads: a switch and a size limit for pictures per kind of connection
  (Wi-Fi and mobile data, with metered Wi-Fi counting as mobile), read from a `tf/network`
  method channel and the settings by `AutoDownloadScope`. A picture over the limit, or on a
  connection the reader excluded, waits for a tap; nothing starts at all until the settings are
  known, so a cold start does not spend mobile data the reader forbade. Videos keep the
  autoplay limits of F-6 and files keep waiting for a tap, which the section says.

### Search

- [x] H-25 Search from the home screen over the posts of every channel the account follows:
  `searchAllChannels` over TDLib's own search of all chats (filtered to channels, paged with
  Telegram's token), the magnifier in the app bar, the results as the same rows the feed search
  uses — each naming its channel — and a tap that opens that channel at the post. (Reopened
  from round 4.)
- [x] H-26 Media filters in the search bar: chips for Everything, Media, Links, Files, Music
  and Voice under the field, in the feed and channel search and in the home search alike. A
  chip on its own is a search too ("every file of my channels"), and the words travel with it.
- [x] H-27 Search inside a comment thread: `searchThread` asks TDLib to search that thread
  (`searchChatMessages` scoped to the message thread), so a comment far above is found without
  loading everything in between. The magnifier in the comments' app bar turns it into a field,
  and what it finds takes the place of the thread until the search is closed.
- [x] H-28 The search bar remembers the last ten queries and offers them when it opens, with a
  Clear beside them: `RecentSearches` keeps one list for the whole app in `settings`, newest
  first and without repeats, and both search bars (home and timeline) read and write it.

### Screens and account

- [x] H-29 Saved Messages are readable in the app: `savedMessages()` hands the chat with
  oneself over as a channel (title "Saved Messages"), and the row in Settings opens it as an
  ordinary timeline, with its own read position from Telegram. The home and settings goldens
  were regenerated (the new row, and the folder-tab badges of H-14).
- [x] H-30 Archived channels have a place of their own: `archivedChannels()` walks Telegram's
  archive list, and an "Archive" row at the top of All channels opens them as an ordinary
  channel list (with the same row menu). The ordinary lists still do not walk the archive, so
  an archived channel stays out of them — the round 6 decision, refined.
- [x] H-31 A tap on the channel photo in the info screen opens it on the whole screen, in the
  media viewer with the channel's name on it; a channel without a photo says so. The avatars in
  the lists and in the bubbles stay small targets and keep leading where they led.
- [x] H-32 Similar channels and the QR code in the info screen: `similarChannels(chatId)` over
  TDLib's suggestions (an error where it has none means no section), drawn as a row of photos
  and names — a tap opens one in the official app, since this app never joins a channel — and a
  QR action that shows the channel's link as a code, drawn with the `qr_flutter` the QR login
  already uses.
- [x] H-33 Sound and vibration per rule priority: a Settings section where normal and urgent
  rules each get a sound from Android's own picker (`tf/notifications.pickSound`, through
  `startActivityForResult`) and a vibration switch; silent rules stay silent. Android fixes a
  channel's sound at creation, so the choice is part of the channel id — the default choice
  adds no suffix, so an older install keeps the channels it has, and a chosen sound makes a
  channel of its own while the ones of earlier choices are deleted. The service reads the
  settings when it brings the watcher up, as the background switch does.
- [x] H-34 App lock: a PIN of at least four digits, kept as a salted SHA-256 hash in the
  keystore beside the AI key (never as itself), with the device's own fingerprint or face
  offered first where the reader allows it (`local_auth`) and the PIN always there as the way
  in. `LockGate` sits above the navigator, so no screen and no notification tap goes round it,
  and locks again when the app has rested longer than the chosen timeout (at once, a minute,
  five minutes, an hour). The TDLib database is untouched: the lock is the app's own.
- [x] H-35 Several Telegram accounts, up to four as in the official app. `AccountStore`
  (`accounts.json` beside the databases, since it says which of them to open) holds the
  accounts and the one in use; `appPaths([accountId])` gives each account its own TDLib
  directory and its own app database, and account 1 keeps the paths the app has always used,
  so an install that predates this finds its data where it left it. The UI host and the
  service host both read the active account, so they open the same one. Switching takes the
  host down — core, database and sync with it — and brings a new one up on the other
  account's paths (`AccountSwitch` hands the root's switch down to the Accounts screen), so
  an account without a session lands on the login screen. Removing an account deletes its
  TDLib data and its database; the last one cannot be removed.

### Founder's own three, after the comparison (2026-09-20)

- [x] H-36 "New feed" belongs inside the Feeds tab: the `+` left the tab bar, which now
  carries tabs only, and became a floating button that stands on the Feeds tab and nowhere
  else. The home golden was regenerated.
- [ ] H-37 The channel picker of a feed takes several channels at once: check them off and add
  them in one go.
- [ ] H-38 Feed positioning is tested thoroughly on fixture data instead of real channels: where
  a feed opens for every read state, what resuming the app from the background does to it, what
  a new post while reading does, and the read marks that follow. Fixture posts and channels live
  in the tests, so nothing depends on the spare account.

Dropped in this round (founder decision 2026-09-20, from the same comparison): polls and
quizzes; giveaways, invoices and paid media as cards; selecting part of a post's text by hand;
translating a post; the waveform of a voice message; voice transcription; swiping a channel
row to mark it read; an in-app browser and Instant View; registering the app as a handler for
t.me links from other apps; chat wallpaper and bubble colours; automatic night mode on a
schedule; interface languages other than English; a "Mark as read" action on a notification;
an in-app banner for new posts; replying from a notification; sharing into the app from other
apps; a home-screen widget; the list of active sessions; managing two-step verification;
per-channel cache size; channel statistics. They are in the Dropped section at the end of this
file with their reasons.

## Phase 4 — Extras

- [x] P4-1 Sync of feeds, rules and settings between devices through the user's Google Drive, no backend of ours (founder decisions 2026-09-18). Schema v4 (sync ids, edit times, tombstones), `SyncSnapshot` merge and `SyncEngine` in core, `DriveSyncStore` (REST, `drive.appdata`), `GoogleDriveAuth`, `SyncController`, Sync screen in Settings. Verified on the emulator with the founder's Google account: first run pushed the file, and a database made stale by hand (old feed name, rule removed) was restored from Drive (`pulled 2`). (5da876c, 2d95ccc)
- [x] P4-2 AI semantic rules. `rules.semantic_prompt` (schema v3), `MatchedRule` details on match events, `SemanticClient` for OpenAI-compatible endpoints, `SemanticGate` in the service host (one request per post, failures skip the rule and leave a quiet note), AI settings screen with the key in the keystore, rule editor field with the send-everything warning and a model-backed dry run. (a372673)
- [ ] P4-3 AI-generated podcast from a feed.
- [ ] P4-4 Optional cloud voices.

## Dropped

Round 7 (founder decision 2026-09-20, from the feature-by-feature comparison with the
official app; each one was put to the founder and not picked):

- [-] Polls and quizzes: they stay "unsupported content"; a poll is a thing to take part in, not to read.
- [-] Giveaways, invoices and paid media as cards: same, and none of them is readable content.
- [-] Selecting part of a post's text by hand: the whole text can be copied (H-6), and a selection would fight the long-press menu.
- [-] Translating a post: Telegram's own translation is a server feature the app cannot call, and neither an endpoint of the reader's nor Android's translator was wanted.
- [-] Waveform of a voice message: the bar with seek and speed (H-19) is enough.
- [-] Voice transcription: Telegram's is a Premium server feature, and Android's recognizer was not wanted.
- [-] Swiping a channel row to mark it read: the long-press menu (H-15) carries that action.
- [-] In-app browser and Instant View: links keep going to the system browser (founder left the choice to the session; the browser is not the app's business and Instant View is a screen of its own).
- [-] Registering the app as a handler for t.me links from other apps: it would put a chooser in front of every t.me link on the device; links inside our own posts do open here (H-18).
- [-] Chat wallpaper and bubble colours: one tinted backdrop, light and dark, stays.
- [-] Automatic night mode on a schedule: the system's own switch is enough.
- [-] Interface languages other than English.
- [-] "Mark as read" action on a notification.
- [-] In-app banner for a new post while the app is open: the shade is where notifications belong.
- [-] Replying to a comment thread from a notification.
- [-] Sharing into the app from other apps.
- [-] Home-screen widget with a feed.
- [-] List of active sessions and terminating them: account management stays in the official app.
- [-] Managing two-step verification: same.
- [-] Per-channel cache size and clearing: Settings clears the whole cache.
- [-] Channel statistics for channels the account administers.

Earlier:

- [-] iOS build: on-device-only cannot deliver real-time notifications on iOS (2026-09-17).
- [-] Adding unjoined public channels: only joined channels are sources (2026-09-17).
- [-] Web build: completed in P3-4 (87e10f3) and dropped on 2026-09-17 by founder decision; Android only. Revive from that commit if ever needed.
