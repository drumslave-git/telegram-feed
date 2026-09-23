# telegram-feed — Architecture

Companion to [SPEC.md](SPEC.md).

## 1. Summary

- **Flutter** app, Android only.
- **TDLib**, Telegram's client library, through its JSON interface (`td_json_client`) via `dart:ffi`.
- The TDLib client and the rule engine live in one **core isolate**. With background watching on, a foreground service hosts it, so it keeps running when the UI is closed. With background watching off, the UI spawns it. The UI is a client of the core.
- Data TDLib does not own (feeds, sources, rules, settings) lives in **SQLite** through **Drift**. Read state is Telegram's own and stays in TDLib.
- No backend. The device talks to Telegram, and, when the user turns them on, to the user's own Google Drive (sync) and to an AI endpoint the user configures (AI rules).

```
┌─────────────────────────────── device ───────────────────────────────┐
│  UI isolate (Flutter)                                                │
│   screens ── FeedTimeline / FeedSearch ── CoreClient ── AppDatabase  │
│                                              │                       │
│  ─────────────────────────────────────────── │ ───────────────────── │
│  Service host (root isolate of the foreground service's engine)      │
│   CoreServiceHandler ── Notifier ── TtsService ── SemanticGate       │
│                                              │                       │
│  ─────────────────────────────────────────── │ ───────────────────── │
│  Core isolate                                                        │
│   CoreServer ── TdlibGateway ── RuleEngine ── AppDatabase            │
│                     │                                                │
│   TDLib (td_json_client via FFI)                                     │
└──────────────────────────────────────────────────────────────────────┘
```

## 2. Technology choices

| Choice | Reason |
|---|---|
| TDLib | Handles auth, updates, media download and a local message cache. The Bot API cannot read arbitrary channels. |
| Session on the device | No server and no custody of user sessions. Real-time notifications need the app to stay alive, which a foreground service provides on Android. |
| Flutter | Mature FFI and one codebase. |
| Core isolate separate from the UI | The UI can be destroyed while the service keeps the core running. TDLib stays in Dart, with no Kotlin implementation. |
| Drift (SQLite) | Relational data (feeds ↔ channels, rules) with real queries. |
| Device TTS via `flutter_tts` | Free, offline, works with the screen off. |

## 3. Module layout

```
telegram-feed/
  app/                  Flutter application: screens, service host, platform glue
  packages/
    core/               CoreServer, CoreClient, port protocol, FeedTimeline, FeedSearch, FeedFilter,
                        RuleEngine, sync merge, read-aloud text preparation, Telegram links
    telegram_gateway/   TelegramGateway interface, TdlibGateway, FfiTransport
    app_db/             Drift schema, DAOs, migrations
    rules/              Rule AST, parser, evaluator, schedules (pure Dart)
    tdlib_bindings/     Dart types generated from td_api.tl
    versioning/         Next version and changelog from conventional commits
  tool/                 CI script, TDLib build and download, golden update
  docs/
```

The pure-Dart packages carry most of the tests. `app/` stays thin.

## 4. Telegram gateway

`TelegramGateway` is the only layer that knows about TDLib. Everything above it works with app-level types (`Channel`, `Post`, `Media`, `Comment`, `FileRef`).

| Area | Members |
|---|---|
| Login | `authState`, `setPhoneNumber`, `checkCode`, `checkPassword`, `registerUser`, `requestQrCode`, `logOut` |
| Channels | `myChannels`, `membershipEvents`, `chatFolders`, `archivedChannels`, `savedMessages`, `channelInfo`, `similarChannels`, `pinnedPost` |
| Posts | `history`, `historyAfter`, `postEvents`, `markViewed`, `readState`, `readUpdates`, `messageIdByDate`, `customEmoji` |
| Search | `searchHistory`, `searchAllChannels`, `searchThread` |
| Files | `download`, `fileProgress`, `downloadFrom`, `downloadedPrefix`, `cancelDownload` |
| Interactions | `availableReactions`, `react`, `saveToSavedMessages`, `discussion`, `threadHistory`, `reply`, `comments`, `closeThread` |
| Account and state | `me`, `storageStats`, `clearCache`, `connection`, `close` |

Implementation:

- `TdlibGateway` (package `telegram_gateway`) runs over a `TdTransport` (raw JSON in, raw JSON out). `TdClient` matches responses to requests by `@extra`, decodes updates with `tdlib_bindings` and hands them to the gateway strictly in order, so an edit that needs a `getMessage` round trip cannot be overtaken by the following delete.
- `FfiTransport` loads `libtdjson`, polls `td_receive` in one long-lived receive isolate and demultiplexes by `@client_id`. TDLib aborts the process if `td_receive` is called from two threads, so there is exactly one receive isolate per process. Imported from `package:telegram_gateway/tdlib_ffi.dart`.
- Post events are emitted only for chats known to be channels. `updateMessageContent` and `updateMessageEdited` are re-fetched with `getMessage`, so `PostEdited` carries the full post. `updateDeleteMessages` is forwarded only when `is_permanent`.
- TDLib answers `getChatHistory` with short pages, often a single cached message. `history` pages until the limit or the end. Local reads (`only_local`) stay a single probe.

TDLib parameters: `use_message_database`, `use_chat_info_database` and `use_file_database` are true; the files directory is `files/` inside the account's TDLib directory. TDLib owns message and file caching; the app never copies message bodies into its own database.

API credentials: `api_id` and `api_hash` come from `--dart-define=TG_API_ID=... --dart-define=TG_API_HASH=...`. The repository contains none. CI injects them from secrets.

## 5. Feeds

### 5.1 Data model (Drift, schema version 7)

```
feeds            (id, name, position, created_at, sync_id, updated_at, filter_json?)
feed_sources     (feed_id, chat_id, position, added_at)                 -- PK (feed_id, chat_id)
watched_channels (chat_id, title, username?)
rules            (see section 6.1)
settings         (key, value, updated_at?)
sync_tombstones  (kind, sync_id, deleted_at)                            -- PK (kind, sync_id)
```

`watched_channels` is the union of all feed sources: every channel the app watches.

The UI, the background service and the core each open their own connection to the file (`appDatabaseFile`). Every connection sets `busy_timeout` to five seconds, so a write waits for another connection's write instead of failing with "database is locked".

After an update all three connections find the old schema at once, and drift runs a migration outside any transaction. `AppDatabase._migrate` therefore takes the whole migration into one `BEGIN EXCLUSIVE` transaction, reads `user_version` again inside it and stamps the new one there: the connection that arrives second waits (`busy_timeout` is a minute while migrating) and then finds nothing left to do, instead of working on a schema another connection is replacing.

### 5.2 Sources

Only channels the account has joined can be added. The picker lists `myChannels()` with a search box; several channels are ticked and added with one press. A checkbox under the search, shown when some channel is in a feed already, leaves those channels out (`picker.hideInFeeds`, kept on the device) and unticks the ones it hides. The app never calls `joinChat`, `leaveChat` or `searchPublicChat`, and never changes Telegram-side mute or folder settings. Every source is a joined chat, so TDLib delivers `updateNewMessage` for all of them and nothing is polled.

When the user leaves a channel in the official app, `membershipEvents` reports it. The source stays in its feeds, marked as left, until the user removes it.

### 5.3 Merged timeline

The timeline is a k-way merge over per-channel histories, ordered by `(date desc, chat_id, message_id desc)`.

- `FeedTimeline` keeps one cursor per source (`oldestLoadedMessageId`) and a small page buffer.
- Loading a page: every source whose buffer is empty fetches its next `history()` page (limit 30), all at once. Then rows are popped from a max-heap keyed by date until the page is full. A source that returns nothing is exhausted.
- Live updates: `postEvents` for any source are inserted at the newest end when the reader is there; otherwise they wait and are counted on the button to the newest posts, which releases them.
- Layout: the list is reversed (index 0 is the newest post, at the bottom), so loading older pages appends at the far end and never shifts what is on screen. A row inserted at the newest end shifts every index; the screen then re-anchors on index 0. Rows are keyed by `(chat_id, album or message id)`.
- Opening (`_open` in `TimelineScreen`), as the official app opens a chat: the list widget takes its start position only when it is first built, so the first pages load before it is. The position is, in this order: the post a notification asked for; where the reader left the timeline scrolled up; the first unread post; the newest post. For the first unread post the sources load down to Telegram's read positions, at most 300 rows. The "Unread posts" divider is drawn on top of that row, and the row above it is aligned just below the top of the screen. When the unread posts do not fill the screen, the newest post goes to the bottom instead of leaving a gap.
- The kept position (`SavedPosition`, `feeds/saved_position.dart`) is the lowest row on the screen and the height of its bottom edge, in the settings under `position.feed.<id>` or `position.chat.<chat id>`, on this device only. It is written when the timeline closes and when the app pauses, and removed instead when the reader is at the newest post or that row is still unread, as the official app does. Opening searches it among the newest 300 rows; everything newer than it is loaded on the way, so the divider goes on the first unread post below it. A rebuild within the visit (a changed filter or source) keeps the reader where they are.
- The divider belongs to the visit: it keeps its row through jumps and rebuilds, and the timeline notes when it has been on the screen.
- A rebuild of a list that stays up (the loading spinner in between may never be drawn) jumps to its opening position after the frame; the positions reported until that jump is laid out describe the old list and are ignored.
- Album messages (`media_album_id`) collapse into one row.
- Edits replace a row in place; deletes remove it.

The timeline persists nothing. TDLib's local message database answers a history request in about 2 ms.

### 5.4 Read state

Read state works as in the official Android app (`ChatActivity` in its source), with a feed read like one chat.

- The read state is Telegram's own: one read position per channel (`last_read_inbox_message_id`), shared by every feed that holds the channel, the channel's own timeline and the official app. The app stores none. `readState(chat)` reads it with the unread count and the newest post (TDLib's `getChat`); `readUpdates` carries TDLib's `updateChatReadInbox`, which comes whenever a position moves (here, in the official app, on another device) or the unread count changes. The timeline keeps the positions of its channels in memory from there and moves them as the reader reads.
- A post is read once 80 % of its row has been above the bottom edge of the screen, an album's row once all of it has (`visibleToBeRead` of the official app). Of the rows that pass, the newest decides: `FeedTimeline.passedAt` names, for every channel of the timeline, its newest post at that row or older in the timeline's order (shown or hidden; from a source's buffer when none of its rows is that old), and every channel's position moves there. So everything above the newest post read is read, as in a chat, and at the newest post of a live timeline with nothing waiting the whole feed is read, hidden posts after it included.
- `ReadMarker` sends the positions after 300 ms, and when the timeline closes, through `markViewed` (TDLib's `viewMessages` with `force_read`, which moves the position to the newest id it names): the posts that were on the screen, for their view counts, and the newest post passed per channel.
- "Mark all read" (`MarkRead`, `feeds/mark_read.dart`) moves the position of every channel of a feed, a folder or one channel to its newest post with `markViewed`. It is in the feed's row menu, the folder tab's long-press menu and a channel row's menu.
- Unread count of a feed (`FeedsController`), counted as Telegram counts: every post after the read position, each part of an album one post. With the "Count unread posts" switch on (`badge.countPosts`, synced, default on) the badge shows the posts; off, the number of channels with any.
  - A feed that shows everything counts Telegram's own `unread_count` of each channel, from `myChannels` and then `readUpdates`; nothing is read from the history.
  - A feed that hides some posts counts, per channel with an unread count, the posts after the read position that its filter lets through: a single post when it passes, an album when one part passes, with all its parts when the feed shows whole posts. They are read from `history`, newest first, in pages of 100, down to the read position, at most 1 000 per channel (the badge then reads "999+"). The count is kept: a position that moves on drops the posts it passed, a new single post is added, a deleted one is removed; a new album part, or a changed filter, counts the channel again.
  - The number of channels with news comes first, so the line under the feed's name appears at once; the filter may still take a channel away when its posts are counted.
  - The count sits on the right of the feed's row, before its menu.
- The button to the newest posts carries the unread posts of the timeline (`FeedTimeline.unreadPosts`, every part of an album one) plus the posts that arrived while reading. A tap, as `onPageDownClicked` of the official app: to the "Unread posts" divider while it has not been on the screen in this visit (rebuilding the live timeline at the first unread post when a jump left the divider behind); else back to the post whose reply quote the reader tapped; else to the very end, releasing the posts that waited. Reaching the newest post forgets the reply's place, as the official app does.
- Posts carry no read mark of their own, as in the official app: the divider and the counters say what is new.

### 5.5 Sync through Google Drive

Feeds with their sources, rules and a whitelist of settings (`isSyncedSetting`: theme, post text size, "Count unread posts", `tts.*`, `media.*`, AI endpoint and model) are kept equal on all of a user's devices through one JSON file in the hidden app-data folder of the user's own Google Drive. Read state is Telegram's and reaches the other devices through Telegram. The kept timeline positions, the AI API key, the Telegram session and every other setting (background watching, rule sounds, app lock, recent searches, quick reaction) stay on the device.

- **Identity.** Feeds and rules carry a random `sync_id` (local row ids differ per device) and an `updated_at` stamp; settings carry `updated_at`. A feed's sources are part of the feed: adding, removing or reordering sources stamps the feed. A rule names its feed by the feed's `sync_id` (`feed`), and a device applies it to its own row of that feed; a rule whose feed it does not have stays out. Deleting a feed or a rule leaves a row in `sync_tombstones`, and so does every rule a deleted feed or a removed channel takes along. Logout turns sync off before wiping the database and leaves no tombstones, so an emptied database is never merged into the file.
- **Merge** (`SyncSnapshot.merge`, package `core`): item by item, the newer edit wins; a deletion beats edits made before it, and an edit made after the deletion restores the item. Tombstones expire after 180 days. The file is canonical JSON with format version 2, in which every rule belongs to a feed. A file of version 1 is read without its rules, which belonged to no feed, and is written back as version 2; a file with a newer version is refused.
- **Run** (`SyncEngine`): export the database, read the file, merge, apply the changes locally (`applySynced*` in `app_db`), write the file only if it differs from what is stored. Two devices writing at once can hide each other's edits in the file but never lose them: every run merges the device's whole local state back in, so the next run repairs the file.
- **Schedule** (`SyncController`, UI isolate): at start, 15 seconds after a local edit, every 15 minutes while the app is open, and on demand from Settings. A change notification leads to a Drive request only when the synced data differs from what the device held after its last run. Pulled rule changes reach the core through the database watchers, like local edits.
- **Drive access** (`DriveSyncStore`, `GoogleDriveAuth`): `google_sign_in` for the account and an access token with the single scope `drive.appdata`, then REST calls (`files.list` in `appDataFolder`, media download, multipart create, media update). A 401 gets one retry with a fresh token. At start the device asks only for the Drive token of the account it signed in with (`sync.account`, device-local), which needs no UI; Google's account sign-in, which shows a "Signing you in" sheet, runs only when that email is unknown. A build needs an Android OAuth client (package name and signing SHA-1) in a Google Cloud project and that project's web client id: `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`. Without it the Sync screen says the build cannot sync.

### 5.6 Video playback

- **Playing while downloading.** A video starts as soon as its first bytes are there. `MediaServer` (UI isolate) is an HTTP server on the loopback interface; the player (`video_player`, ExoPlayer) opens `http://127.0.0.1:<port>/<secret>/<fileId>` and asks for byte ranges. Bytes TDLib already has are read from its partial file, where they sit at their final offsets; for a range that is not there yet the download is aimed at it (`downloadFile` with `offset`) and the response waits. Seeking, and MP4 files with the index at the end, are the same case. The newest request decides where TDLib downloads. Response headers are written at once through a detached socket, because `dart:io` holds them back until the first body byte and the player's read timeout would run out meanwhile. The path contains a random token, since other apps can reach the port; the port closes when nothing plays. A finished file plays from disk without the server; a file without a known size is downloaded whole first.
- **Sessions.** `VideoSessions` keeps one `VideoSession` (player plus state) per file id outside the widget tree, so the timeline row and the viewer show the same player. Only one session has sound at a time. Timeline rows are keyed by post, so a new post at the top cannot shift player state under another post.
- **Viewer controls** (`MediaViewerScreen`, `VideoStage`, `ZoomablePhoto`; paging in section 5.13): a tap on a video in the timeline opens it in the viewer and plays it there; the timeline has no player controls. Only the page in front has a session: its neighbours are posters, and turning the page hands the session back exactly as leaving does. The viewer is immersive and follows the device's orientation. Controls: back arrow; a tap shows or hides them; a scrubber with the buffered range; speed; mute; replay at the end. A double tap on the left or right third seeks 10 s; in the middle it zooms to 2.5× around the tapped point and back. A pinch zooms up to 6× and a drag moves the zoomed picture (`InteractiveViewer` around the player's texture; zoom helpers in `media/zoom.dart`, shared with photos). A finger held down plays at 2× until it lifts. The gesture layer lies behind the buttons, so button taps do not wait out the double-tap window. A vertical drag with one finger carries the picture away while the black behind it fades, and closes the viewer past 120 px or with a flick (`SwipeToClose`); it is off while the picture is zoomed, and a second finger leaves the drag to the pinch. The viewer's route is not opaque, so timeline rows under it stay visible to the visibility detector; autoplay rests while the row's route is not the current one. Leaving the viewer pauses the video, disposes the player and cancels an unfinished streaming download at once (`releaseFromViewer`). A video the timeline was autoplaying starts from the beginning in the viewer; one taken over from the mini player or the system window keeps its position.
- **Download button** (`VideoDownloads`, `VideoDownloadButton`): a pill in the top left corner of a video in the timeline: arrow and size, then a progress ring with the bytes that cancels on tap, nothing once the file is complete. In the viewer's top bar the same button is `compact`: the ring alone while the file downloads, and nothing otherwise, because the viewer's menu is where a download is asked for. It downloads the whole file into TDLib's cache (priority 16, below a playing video's 32). A download the user asked for is not cancelled when its player closes, and cancelling it leaves a playing video its stream. Posts carry the `FileRef` of the time they were loaded, so the button asks TDLib (`getFileDownloadedPrefixSize`) whether the file is complete by now, and follows the file's progress while it is shown.
- **Picture-in-picture** has two parts. *Mini player* (`MiniPlayer`): the viewer's PiP button moves the session into a small window in the root navigator's overlay that floats over every screen; it can be dragged (it rests at the nearer side), paused and played with a tap, opened in the viewer again, or closed. A session counts its sound-watching holders (`retainForViewer` / `releaseFromViewer`), so the viewer and the mini player hand a video to each other without stopping it, and it ends when the last one lets go. Opening the viewer ends a mini player that shows another video. *System window* (`SystemPip`, `PipHost`, `MainActivity`): Android's picture-in-picture shrinks the whole activity, so it takes over only when the app is left. While a video plays in the viewer or the mini player (`VideoSessions.foreground`, counted once the player is initialized, because the window needs the picture's size) the activity is armed over the channel `tf/pip` with the video's aspect ratio, clamped to 1:2.39 to 2.39:1: auto-enter from Android 12, `onUserLeaveHint` on 8 to 11. In the window, `PipHost` (above the navigator) shows only the video and keeps the screens alive offstage. When the activity is stopped the foreground video pauses; nothing plays from the background.
- **Autoplay** (section 5.14 decides which videos): a video that loads by itself starts muted and looping in its row (`InlineVideo`) once 60 % of it is visible, and pauses below 20 %; it streams through the loopback server while its automatic download goes on. A tap opens the viewer on the same player with sound; leaving the viewer mutes it again and it keeps autoplaying. A row the list rebuilds picks its autoplay session up again within 0.8 s; after that the player is disposed, and the download continues only if the automatic download wants the file.

### 5.7 Main screen

`HomeScreen` is a tab bar of "Feeds", the Telegram chat folders and "All channels". The app bar holds the search over all channels, Rules and Settings. A floating button on the Feeds tab creates a feed and opens its channel editor; it shows only while the Feeds tab is up.

- `ConnectionTitle` sits in the app bar of the home screen and of every timeline. It follows the gateway's `connection` stream (TDLib's `updateConnectionState`, carried over the core port as `CoreStream.connection`) and puts "Connecting…", "Waiting for network…", "Connecting to proxy…" or "Updating…" under the title until TDLib is ready.
- The Feeds tab lists the feeds, each with its count (section 5.4) and a line naming the channels with new posts (`FeedsController`). The tab label carries the feeds' posts together, or the number of feeds with any. A tap opens the feed as `TimelineScreen(feed:)`; dragging reorders; the row's menu leads to its channels, its rules, rename, mark all read and delete.
- Folder tabs come from `chatFolders()`: TDLib announces the folders in `updateChatFolders`; the chats of each are read with `getChats(chatListFolder)`, which applies the folder's include and exclude rules and Telegram's order, and only channels are kept. A folder without channels gets no tab. The app never edits folders. The `TabController` is replaced only when the set of folders changes, and the selected tab stays selected.
- A folder tab's badge comes from Telegram's own `unreadCount` per channel: the unread posts of its channels together, or the number of its channels with any, as the "Count unread posts" switch says.
- `myChannels()` walks the main chat list and every folder list, each channel once, because a channel joined through a folder invite link is in its folder's list and in no other. The home screen asks for the folders first so the gateway knows which lists to walk. The archive is not walked, so an archived channel appears in these lists only when a folder holds it.
- The archive has a row of its own at the top of All channels: `archivedChannels()` walks `ChatListArchive` when that row is tapped and shows the result as an ordinary channel list.
- A long press on a folder tab offers "Create feed from folder" (a feed with the folder's name and its current channels in the folder's order; the feed does not follow the folder afterwards) and "Mark all read".
- Every tab carries its own padding (the bar's `labelPadding` is zero) and is at least 72 px wide, so the long press covers the whole tab, including a folder named with a single emoji.
- A long press on a channel row opens its menu (mark as read, channel info, add to a feed) under the finger: the row is wrapped in a `GestureDetector`, since a `ListTile`'s own long press reports no position.
- Channel lists (`ChannelList`) show photo, newest post, time and Telegram's unread count from `Channel`, with the tags of the feeds the channel is in at the end of the preview line (`AppDatabase.feedNamesByChat`, live through `watchFeeds` and `watchSourceChanges`). Every row is two lines tall, whatever a channel has, and the initials of a channel without a photo take its own colour (`peerColor`). The feed editor's channel picker carries the same tags. Lists reload when the app resumes, three seconds after a new post, and on pull to refresh.
- A channel opens as `TimelineScreen(channel:)`: the same timeline with one source. It reads and moves Telegram's read position like a feed does (section 5.4).
- Saved Messages is the chat with oneself, handed over by `savedMessages()` as a `Channel` titled "Saved Messages" and opened from Settings as an ordinary timeline. It belongs to no feed.

### 5.8 Feed filters

`feeds.filter_json` holds a `FeedFilter` (package `core`): media presence (any, with media, text only), a set of media kinds (photo, video, gif, audio, voice, document, other; empty means all), a minimum video length, a minimum length for posts without media, and `wholePost` (true unless the JSON says otherwise). Null means everything. Unknown values are ignored; broken JSON shows everything.

An album is several messages, so the four content settings judge its parts one by one. `wholePost` makes the row the unit instead: one part that passes carries the others (`FeedFilter.mayShow` checks presence only, since a single message cannot see its siblings; the row decides the rest). An album whose parts all fail stays hidden.

- **Timeline.** `FeedTimeline` runs every post through the filter as it leaves a source's buffer or arrives live; hidden posts never become rows. A hidden part of a whole-post feed joins the row its siblings opened. If that row does not exist yet (parts arrive newest first from history, and one by one when live) the part waits in a small map keyed by chat and album, capped at eight, which the opening part empties. From then on it counts as shown.
- **Read state.** Hidden posts must not stay unread, or a channel that only posts hidden things would keep its feed marked as new. The timeline remembers the ids and dates of the posts it hid, and `passedAt` counts them with the rows around them: a hidden post older than the newest row read is read, and at the newest post of a live timeline all of them are.
- **Rules.** A rule sees the posts of its own feed as that feed shows them: the engine gets every feed with its channels and filter (`feedsForRules`), and a rule is only evaluated for a post its feed's filter lets through. It asks `mayShow`, so the caption of an album notifies when the feed shows whole posts. A rule can therefore notify about an album the timeline hides; the error is on the side of notifying.
- **Search.** `FeedSearch` asks `mayShow` for a search by words and `allows` for the shared media tabs, which list single media items by kind.
- **Editing.** The feed editor's "Show" row opens a sheet with the four content controls and the "Show the whole post" checkbox (shown only for a feed with media); the row's subtitle is the filter in words.
- **Sync.** The filter travels with the feed as the optional `filter` key of the sync snapshot.

### 5.9 Posts and comments

Screens use `CupertinoPageTransitionsBuilder` on every platform (`appPageTransitions` in `main.dart`): they slide in, and a drag from the left edge pops them. The media viewer keeps its own see-through route and its swipe down.

A timeline row (`PostCard`, `feeds/post_card.dart`) is drawn like a post in the official Android app, except that nothing stands beside the bubble, so text and pictures get the whole width. A bubble on a tinted backdrop (`ChatColors`) starts with its title line (`BubbleTitle`): the channel's name in one of Telegram's seven peer colours (`peerColor`, by id) and the channel's photo, small, at the right end of that line. Then media edge to edge, the text, reaction pills and a comments bar. Day pills stand between days.

- Views, "edited" and the time sit in the bottom right corner. `BubbleText` is a render object that puts this footer on the last line of the text when there is room and on a line of its own otherwise. With reactions, the pills use the full width and the footer takes the free end of the last row. With nothing under the pictures it lies on top of them.
- A double tap sends the quick reaction (`reactions.quick`, a thumbs up until the reader picks another from the menu strip; the timeline reads it once when it opens). A second double tap takes it back. The recognizer sits on the post's words, or on the pictures of a post without words: on the whole bubble it would hold the gesture arena for 300 ms and delay every tap inside it. For the same reason the menu opens on a long press only.
- A long press on the bubble opens the menu: the reactions the channel allows, Open in Telegram, Comments, Share, Copy text, Copy link, Save to Saved Messages, Select, and on posts with a video "Autoplay and download settings", which opens Data and storage. The menu scrolls, since its entries do not all fit on a short screen. `saveToSavedMessages` forwards the whole album into the chat with oneself, keeping the channel as the source.
- Every bubble takes the whole row, whatever it holds, so the posts of a timeline line up.
- "Copy text" copies the row's words. Every `TextEntityKind.pre` block ends with a copy button of its own (a `WidgetSpan` inside the text, so it sits where the block ends).
- "Select" starts a selection: `TimelineViewState` keeps the picked rows by `(chat id, row id)`, each card gets a tick and a layer that swallows every other tap, and `TimelineScreen` replaces its app bar with "N selected" plus Copy text, Share and Save to Saved Messages, which run over the picked rows oldest first (saving groups them per channel, so an album goes in one call).
- The post text size (`appearance.postTextScale`, 0.8 to 1.6, synced) comes from `PostTextScale`, an inherited value above the navigator. `PostCard` and the comments wrap themselves in a `MediaQuery` whose `textScaler` is clamped to that factor, so posts follow the setting and the rest of the app follows the system.
- The list keeps 8 px plus the system inset under the newest post, which in the reversed list is the bottom edge of the screen.
- A forwarded post carries `Post.forwardedFrom` (`ForwardOrigin`: the name, the origin chat and post, the origin user, the author signature, and whether the sender hides itself). TDLib gives ids, not names, so `TdlibGateway._post` resolves them through the sender cache the comments use: one `getChat` or `getUser` per origin and session. `ForwardedFrom` draws "Forwarded from <name> (signature)" under the title line; a tap opens the original post when the account follows that channel, and says so otherwise.
- A post that answers another carries `Post.replyTo` (`ReplyTarget`: the answered post's chat and id, the quote with `manualQuote` when the author picked one, the words otherwise, a thumbnail, and the name for a reply across chats). TDLib sends the origin and content only when the answered post is in another chat; inside the channel `TdlibGateway._reply` fetches that post once and keeps its words and thumbnail in a map cleared past 500 entries. `RepliedPost` draws the block above the text; a tap jumps to the post when it belongs to the timeline's channels, else opens that channel.
- A post with a link carries TDLib's `linkPreview` as `Post.linkPreview` (`LinkPreview`: url, display url, site, title, author, description as plain text, a `PhotoMedia` for the picture, the video flag with its length, and TDLib's `show_large_media`, `show_media_above_description` and `show_above_text`). `_previewPicture` reads the picture out of each kind of link (photo, article, app, video with its cover, embedded player thumbnail, animation, document, audio cover); kinds without one (chat, sticker set, invoice, unknown kinds) give a card of words alone. `LinkPreviewCard` (`feeds/link_preview.dart`) draws an accent bar and a tint in the channel's peer colour, the site in that colour, the title, a description of at most three lines, and the picture either the width of the card or as a 56 px square beside the words, with a play badge and the length on a video link. A tap opens the link through `onOpenLink`, like a link in the text. A preview is not `Post.media`: a feed that shows text posts only still shows a post with a link.
- A channel's timeline carries `PinnedBar` at the top when `pinnedPost(chatId)` finds one (TDLib's `getChatPinnedMessage`; a channel with nothing pinned answers with an error, which means none). A tap jumps to that post, the cross hides the bar for the visit, and the floating day pill moves below it. A feed mixes channels and has no bar.
- The day of the topmost row floats over the list (`FloatingDay`, the same pill as between days). It fades in when the reader starts a scroll (`UserScrollNotification` with a direction, so opening a feed, a date jump or a new post brings nothing out), follows the top of the screen from `itemPositions`, and fades out 900 ms after the list comes to rest, leaving the tree. A tap opens the calendar on that day. A scroll notification can arrive from inside the list's layout, where a rebuild must not be scheduled, so the pill's state lives in two `ValueNotifier`s written after the frame.
- A sticker (`StickerMedia`) is drawn by `StickerView` at its own proportions, about 180 px on its longest side: `webp` as a picture, `tgs` through `Lottie.file` with `LottieComposition.decodeGZip`, `webm` as a silent looping video (`LoopingVideo`). A round video message is `VideoMedia.isVideoNote`, the ordinary player inside a `ClipOval` of 200 px. Neither opens the media viewer. Both carry a name for read-aloud, search and rule notifications ("A Sticker", "Video message"). A sticker counts as `other` for a feed's media filters.
- Albums of photos and videos are a mosaic: `layoutAlbum` ports the grouped layout of the official apps (fixed arrangements for two to four pictures by their proportions, row splitting towards a 3:4 block for more). The mosaic fills the bubble's width and is at most one and a half widths tall; cells crop their picture. Audio and documents of an album stay a list.
- A custom emoji is `TextEntityKind.customEmoji` with the sticker id. `FormattedText` asks the gateway for the stickers of all ids in one text at once (`customEmoji`, TDLib's `getCustomEmojiStickers`, cached in the gateway) and draws each as a `StickerView` the height of a line. Without an answer the plain emoji in the text stands.
- `Post.entities` and `Comment.entities` carry TDLib's text entities (offsets in UTF-16 units). `FormattedText` cuts the text at every entity boundary, so nested and overlapping formatting works. Links, mentions and e-mail addresses open through `launchFirst`; spoilers are covered until tapped. Rules, read-aloud, sharing and notifications use the plain text.
- Avatars: the timeline takes channel photos from `myChannels()` (the database keeps titles only). Comments carry `authorId` and `authorPhoto`, resolved once per sender by the gateway. The thread view (`ThreadScreen`) shows the post as its timeline row on top and comments as bubbles with the same title line (author's name, photo at its right end); the account's own comments sit on the right without name and photo. The feed editor, channel picker and rule scope list show channel photos too.

### 5.10 Search, dates and shared media

Search, date jumps and shared media run over all of a feed's sources as one merged list and obey the feed's filter.

- **Home search.** `searchAllChannels` asks TDLib's `searchMessages` over the main chat list with its channel filter, pages with the token TDLib returns, and drops anything that is not a channel of this account. Results use the rows of the feed search; a tap opens that channel's timeline at the post.
- **Filter chips.** `SearchFilterChips` sits under both search fields and maps to `HistoryFilter`: Everything, Media, Links, Files, Music, Voice. A chip with no words is a search of its own.
- **Recent searches.** `RecentSearches` (`search.recent` in `settings`) keeps the last ten queries of the whole app, newest first and without repeats. Both search bars offer them while nothing is typed and can clear them.
- **Comment search.** `searchThread` calls `searchChatMessages` scoped to the thread, so Telegram finds a comment far above without the app paging the whole thread. The results replace the thread while the field is open.
- **Engine.** Search and the media tabs share `FeedSearch` (package `core`): the merge of `FeedTimeline` over `searchHistory` instead of `history`, with a buffer and a next offset per source, `(date desc, chatId, messageId desc)`, and `loadMore()` for the next page. Albums are not collapsed: a result row or a media tile is one message. A media tab is the same search with an empty query and a `HistoryFilter` (photo and video, document, link, audio, voice), which the gateway turns into TDLib's `SearchMessagesFilter`.
- **Counts.** Telegram's `total_count` per source is summed into `FeedSearch.totalCount`. It counts what the server matched, so with a filter it is an upper bound; once the search is exhausted the number of results is exact.
- **In the timeline.** The magnifier turns the app bar of `TimelineScreen` into a search field (`SearchResults`, `SearchResultTile`, `SearchStepper` in `feeds/timeline_search.dart`). Typing runs a `SearchSession` after 300 ms; the results cover the timeline, each row naming its channel and marking the words. A tap opens the result: the list makes way, the bar keeps the query, and the bottom bar steps through the matches with "3 of 47".
- **Jumping to a post.** `TimelineViewState.jumpToPost` rebuilds the timeline anchored at that post: the post itself for its own channel, `anchorsForDate` for the others. One page of newer posts loads straight away, so the post stands among its neighbours. `FeedTimeline.loadNewer` (gateway `historyAfter`, TDLib's negative offset) adds more as the reader scrolls down; every row it adds moves the indices, so the list is jumped back to where the reader was. While the timeline is jumped, new posts wait on the badge, the remembered position is left alone, and the corner button rebuilds the live timeline at its newest post. A rebuilt list keeps the scroll position of the old one, so a later opening also jumps explicitly; `initialScrollIndex` counts only for the first build.
- **Dates.** `anchorsForDate` asks every source for the newest post sent no later than the chosen day (`getChatMessageByDate`; a 404 means the channel has nothing that old and contributes nothing there). The calendar opens from the search bar or from a day pill (`TimelineViewState.pickDate`, `jumpToDate`). The timeline pages down to the day before (at most 300 rows) and settles on the first post of the chosen day, or on the closest older post for a day without posts. A date before everything the sources have is reported as such.
- **Button to the newest posts.** It carries the unread counter and leaves a jumped timeline (section 5.4).
- **Channel info.** A channel's title in the timeline opens `ChannelInfoScreen`: photo (a tap opens it in the media viewer), name, subscribers, description, the link (`@username` for a public channel, the invite link for a private one), the channel's QR code (`qr_flutter`), similar channels (`similarChannels`, TDLib's suggestions; a tap opens one in the official app) and the shared media tabs. It has no mute and no leave.
- **Shared media tabs** (`SharedMediaTabs`, `feeds/shared_media.dart`): Media, Files, Links, Music and Voice, each a `FeedSearch` with no query, paged as it scrolls. Media is a grid of cropped pictures with the length on videos; a tap opens the viewer over everything the tab has loaded. Files name the file before download and carry the timeline's download control. Links open in the browser. Music and Voice use the timeline's audio players.
- **Feed info.** `FeedEditorScreen` is the feed's info screen: a "Channels" tab with the sources, the filter row and the picker, a "Rules" tab with the feed's rules (`RuleList`) and a button for a new one, and the same five media tabs over all of the feed's channels, with the feed's filter. A tab's search starts over when the channels or the filter change. The feed's title in the timeline opens it.

### 5.11 Settings

`SettingsScreen` holds the profile (`AccountHeader`: photo, name, username, phone, bio, Telegram ID) and one row per screen, and no setting of its own. Log out is in the app bar's menu. The rows, in order:

- Accounts and Saved Messages, under the profile.
- Screens in `settings/`: Chat settings (`ChatSettingsScreen`: post text size with a preview, theme); Privacy and security (`PrivacyScreen`: app lock); Notifications and sounds (`NotificationsScreen`: sound and vibration per rule priority, the Badge counter's "Count unread posts", background watching, and a row that opens Android's notification settings of the app); Data and storage (`DataStorageScreen`: storage usage with its own screen and the cache button; one row per connection with the preset's summary and the connection's switch behind a divider, each leading to `AutoDownloadScreen`; the reset; the Autoplay switches). `AutoDownloadScreen` has the connection's switch, a data-usage slider over Low, Medium and High with a Custom stop placed by how much it downloads, and photos, videos and files with their limits in a sheet.
- The app's own screens: Read aloud, AI rules, Google Drive sync, each with its state on the right where it has one.
- About (a dialog listing what leaves the device) and the licenses, then the version line (`package_info_plus`).

`settings/settings_tiles.dart` holds the shared pieces: the section header, the note under a section and the row that leads to a screen.

### 5.12 Sound

`AudioSessions` (`media/audio_session.dart`) is the app's one audio player: voice messages and music play in it, so only one sound is heard at a time and a post that scrolls away keeps playing. It sits behind an `AudioEngine` interface (`just_audio` in the app, a fake in the tests) and holds the track, whether it plays, the position and the speed (1×, 1.5×, 2×) as notifiers, which the row in the post and the player bar both follow. `AudioBarHost` sits in the app's `builder`, under the navigator, so the bar stands under every screen while something plays and the sound survives scrolling away or opening another screen.

### 5.13 Media viewer

The viewer (`MediaViewerScreen`) pages through every picture and video the timeline holds, not only one post's album. The card asks the timeline for its media (`_viewerMedia`, newest first down to each album's first picture, the feed's filter already applied because it walks the loaded rows) and opens at the tapped one. With `newestFirst` the pages run the other way round, older on the left as in the official app: a swipe to the left goes forward in time, and "N of M" and the picture's hero tag count from the album's first picture. Two pages from the older end it calls `onNeedOlder`, which pages the timeline and hands the list back grown; a list that does not grow is the end. A `ViewerDetail` per item carries the channel, the day and the caption, which the top bar and the band at the bottom show. The viewer's Save to Saved Messages acts on the post the picture belongs to (`onSave` by index).

A picture grows out of the row it was tapped in and shrinks back into it: both sides name it the same way (`mediaHeroTag`, the post and the picture's place in it), the row from the post it draws and the viewer from the `ViewerDetail` it was handed, so neither has to be told. Only the page in front carries the name, since two heroes of one name on a route are not allowed, and a video carries it only while it is still a poster, so a running player is never handed to the flight. A picture the caller says nothing about, a channel's own photo, has no name and fades as before.

The top bar (`ViewerTopBar`) holds the back arrow, the channel and the day on one line each, and then the buttons: on a video the download ring while a download runs and the picture-in-picture button, then Share and the three dots. Everything else is behind the dots (`ViewerMenu`, dark whatever theme the app is in): Download or Cancel download with the file's size, Save to Saved Messages, Save to gallery. The lines are built when the menu opens, so each says what it does at that moment.

Share hands the picture or the video itself to the system sheet (`share`, `share_plus` with the file), not the post's words. A video is shared only once the whole file is in Telegram's cache — the viewer asks TDLib for the file's downloaded prefix, because the post's `FileRef` is as old as the post — and otherwise says "Download the video first to share it." with a Download button on the snackbar. A picture is downloaded first, as Save to gallery does. Sharing a post's words and its link is the timeline's Share, in the row's menu and in the selection bar.

The top bar and the caption go together: a tap on a picture puts both away and brings them back, and on a video they follow the player's controls, which also hide by themselves while it plays. The caption (`ViewerCaption`) stands above the player's bar and scrolls inside at most a third of the screen.

"Save to gallery" goes through the `tf/gallery` method channel: the Kotlin side inserts the file into `MediaStore` under `Pictures/TG Feed` or `Movies/TG Feed` (no permission needed for the app's own file on Android 10 and later) and answers with its uri. The file is downloaded first when the cache does not have it.

### 5.14 Automatic downloads and autoplay

Automatic downloads and autoplay are one setting. `AutoDownloadScope` (`media/auto_download.dart`) sits above the navigator and hands every media widget an `AutoDownloadPolicy`: the `DownloadPreset` of the connection the phone is on, and the two Autoplay switches.

- **Connections.** Mobile data, Wi-Fi and roaming, each with its own preset (`media.download.mobile|wifi|roaming`, JSON, synced like every `media.*` setting). The connection comes from the `tf/network` method channel: metered Wi-Fi counts as mobile data, cellular without `NET_CAPABILITY_NOT_ROAMING` as roaming. It is read again when the app resumes.
- **Presets** follow the official app: a switch for the whole connection, photos (no size limit), videos up to a size, files up to a size, and "Preload larger videos". Telegram's three are built in: Low (photos only), Medium (videos to 10 MB, files to 1 MB) and High (videos to 15 MB, files to 3 MB). A fresh install has Medium on mobile data, High on Wi-Fi and Low while roaming. GIFs and round video messages count as videos; music and voice messages as files.
- **Behaviour.** A photo within the preset loads as soon as its row is built. A video within the limit downloads whole through `VideoDownloads.start(auto: true)`, so its pill shows the progress; a download the user stops by hand does not restart by itself in this run. A larger video with preloading on gets its first 2 MB (`downloadFrom` with a `limit`, TDLib's `downloadFile` limit), so a tap plays it at once. A file within the limit starts in its row; a voice message or a song loads ahead without playing. A size TDLib has not reported yet waits for a tap.
- **Autoplay** follows the download: a video autoplays when it loads by itself and its Autoplay switch (GIFs, videos) is on. Autoplay has no length or size limit of its own.
- Until the settings and the connection are known the policy is `unknown`, nothing starts, and a spinner stands in; when the policy then allows it, the row starts at once. Without a scope (widget tests of a single view) only pictures load.

### 5.15 Telegram links

`telegramTargetOf` (package `core`) parses `t.me/<name>`, `t.me/<name>/<post>`, `t.me/c/<internal id>/<post>`, `tg://resolve` and `tg://privatepost`, with the post as a TDLib message id. A link in a post that names a channel the account follows opens that channel's timeline in the app, at the post. Invite links, sticker sets and web pages go to `launchFirst` and the system. The app does not register as a handler for t.me links from other apps.

`launchFirst` tries each candidate link in turn and survives the exception `url_launcher` throws for `tg://` when no app handles it, so Open in Telegram falls back from `tg://privatepost` to `t.me`. `telegramPostUri` builds `https://t.me/<user>/<id>` for public channels and `tg://privatepost` plus a `t.me/c` fallback for private ones. Share puts the `t.me` link into the system share sheet (`share_plus`); Copy link uses the clipboard.

## 6. Rules and notifications

### 6.1 Rule model

```
rules (id, name, enabled, feed_id, scope_chat_id?,
       condition_json, priority {silent, normal, urgent}, read_aloud,
       schedule_json?, created_at, semantic_prompt?, sync_id, updated_at)
```

Every rule belongs to a feed (`feed_id`) and watches all of its channels, or the one in `scope_chat_id`. Deleting the feed deletes its rules; removing a channel from a feed deletes the feed's rules for that channel. Both leave tombstones for sync.

The rules list (`RuleList`, `rules/rules_screen.dart`) shows the rules of one feed on the Rules tab of its info screen, which the feed row's menu also opens, and all rules under a header per feed behind the Rules button of the home screen (`RulesScreen`). The editor (`RuleEditorScreen`) picks the feed, preset to the feed it was opened from, and then one of that feed's channels or all of them.

Condition AST (package `rules`):

```
Expr = And(List<Expr>) | Or(List<Expr>) | Not(Expr) | Term
Term = { text, wholeWord: bool, caseSensitive: bool }     // multi-word text = phrase match
Schedule = { weekdays: Set<1..7>, from: "HH:mm", to: "HH:mm" }   // local time, may wrap midnight
```

The editor is a visual builder (groups of terms with AND/OR, NOT per term) plus a text form `("bitcoin" OR btc) AND NOT airdrop` that parses to the same AST (`RuleParser`). Terms are bare words or quoted phrases, whole-word and case-insensitive by default; prefix `~` for substring match and `=` for case-sensitive. `AND` binds tighter than `OR`, `NOT` tightest. `RuleParser.format` renders the AST back. Whole-word matching is Unicode-aware: Dart's `\b` is ASCII-only, so boundaries are `(?<![\p{L}\p{N}_])…(?![\p{L}\p{N}_])` with `unicode: true`. CJK text has no inner word boundaries, so `~` is the match to use there. Case-insensitive matching uses the regex engine's Unicode case folding, which covers Cyrillic.

A rule with no condition (`And([])`, which every post satisfies) notifies about every post of its channels. The editor saves it when both keyword editors are left empty, and the rules list shows it as "every post". Scope, priority, schedule, read-aloud and the feed-filter check (section 5.8) apply to it like any other rule. It also matches a post with no text at all; its notification and the dry run show what the post carries instead ("Photo", "Video", the file's name; `postLabel` in `core`). An AI rule never counts as one: there is nothing to send to the model.

### 6.2 Evaluation

`RuleEngine` runs in the core isolate and reads the rules and the feeds, each with its channels and filter (`RuleFeed`), from the database whenever the host signals a change (`refresh`). On every new post of a channel in some feed:

1. Extract the text: message text or media caption, formatting flattened. Nothing else is matched (no forward origin, no URLs beyond their visible text). A post without text only reaches rules with no condition (section 6.1).
2. Candidate rules are the enabled rules of the feeds that hold the channel, for the whole feed or for this channel, whose feed shows the post (section 5.8), filtered by schedule against the local clock.
3. Evaluate each condition and collect matches.
4. If none match, stop. Otherwise priority is the maximum over the matches and read-aloud is true if any match asks for it.
5. Send a `MatchEvent` to the service host, which shows the notification (section 6.3) and, if read-aloud is set, queues the post for speech (section 7).

Edited posts are not evaluated again. A deleted post cancels its notification.

### 6.3 Notifications

`Notifier` (service host) uses `flutter_local_notifications` with one Android notification channel per priority:

| Priority | Android channel importance | Behaviour |
|---|---|---|
| silent | LOW | In the shade, no sound, no heads-up |
| normal | DEFAULT | Sound and vibration as chosen in Settings |
| urgent | HIGH + `bypassDnd` | Heads-up. Bypassing Do Not Disturb needs notification-policy access. The manifest declares `ACCESS_NOTIFICATION_POLICY`, without which Android leaves the app out of its Do Not Disturb access list, and the rule editor opens that list when urgent is picked. Android fixes a channel's DND bypass at creation, so the notifier posts on `posts_urgent` until access exists and then creates `posts_urgent_dnd` (and deletes the other); it checks before every urgent notification |

Sound and vibration are chosen per normal and urgent rules: a sound from Android's own picker (`tf/notifications.pickSound`, an activity result) and a vibration switch; silent rules stay silent. Android fixes a channel's sound when the channel is created, so the choice is part of the channel id: the default sound uses the plain ids (`posts_normal`, `posts_urgent`), any other choice adds a suffix derived from it, and channels of earlier choices are deleted, so the system settings show one row per priority. The service host reads these settings when it starts; `CoreHost` watches them and sends the service `sounds`, on which `Notifier.setSounds` makes the channels of the new choice and deletes the old ones, so a change applies at once. The sound row shows the ringtone's own title (`tf/notifications.soundTitle`).

Each notification shows the channel title, a post excerpt and, as Android's sub-text, the rule that matched, with the actions **Listen** and **Open in Telegram**. A tap opens the post in the feed of the rule that decided (the first of the highest priority, `MatchEvent.feedId`), which the notification's payload carries; in the first feed that holds the channel when that feed is gone. Notifications from the same channel are grouped. The group summary's "N new posts" counts what `getActiveNotifications` still reports for that group plus the post being shown, so posts the user swiped away or opened, and posts deleted in Telegram, stop counting. When a cancellation empties a group, the summary is cancelled with it.

Every notification names its small icon, `ic_stat_feed` (a white glyph on transparency that Android tints). The plugin keeps its default icon in shared preferences, where the isolate that initialises last would decide it, so no notification relies on the default. The service's notification names the icon on every update, because Android restores a running foreground service with the content saved when it was started.

Android 13 and later require `POST_NOTIFICATIONS`. `CoreHost` does **not** ask for it: its start runs before the login screen, on a blank spinner, and Android grants that ask once, so a reflexive refusal there would silence every rule for good. The service starts without it (its own notification is simply not shown) and the app asks where it can give a reason: when a rule is saved (`NotificationPermissionAsk`), and from Notifications and sounds, whose banner also opens Android's own page.

### 6.4 AI semantic rules

A rule may carry a description of what the post should be about (`rules.semantic_prompt`). Its keyword condition is then an optional pre-filter; an empty one (`And([])`) lets every post of the rule's channels through, and the editor warns that all of them are sent to the model.

- The rule engine stays synchronous and offline: it applies scope, schedule and keywords only, and the `MatchEvent` lists every matched rule with its prompt (`MatchedRule`).
- The service host finishes the decision (`SemanticGate`): one request per post to an OpenAI-compatible `chat/completions` endpoint (`SemanticClient`) with all pending descriptions numbered; the model answers with the matching numbers or `NONE`. The request carries only `model` and `messages`, because reasoning models need room before their short answer and some providers reject a custom temperature or token cap. An empty answer counts as a failed check, not as `NONE`. `MatchEvent.withSemanticVerdicts` keeps the keyword rules and the confirmed semantic ones, and priority and read-aloud are recomputed from them.
- When the check cannot be done (no endpoint, offline, bad key, rate limit, unreadable answer), the semantic rules are skipped for that post. Keyword rules on the same post still fire and nothing is retried. The reason is stored in the `ai.lastError` setting, which the rules screen shows as a note until a check succeeds.
- Endpoint and model are settings (`ai.baseUrl`, `ai.model`). The API key is in the Android keystore through `flutter_secure_storage`, never in the database, and is deleted on logout. Plain `http://` endpoints are allowed, with a warning, for models on the user's own network.
- The rule editor's dry run sends the newest 8 posts that pass the keywords to the model.

## 7. Read aloud

- `TtsService` runs in the service host and owns a single FIFO queue over a `Speaker` interface (`FlutterTtsSpeaker` in the app). `flutter_tts.speak` flushes the previous utterance, so the queue waits for `awaitSpeakCompletion` and a new item never interrupts a playing one. The queue never drops items. A Listen request is spoken right after the current utterance instead of at the end of the queue; otherwise Listen and automatic read-aloud share one path.
- Language: `google_mlkit_language_id` (on-device), or the "Language when unknown" setting when detection fails (default English). The language selects the user's voice for it, or the engine's default voice for that language.
- Text preparation (`prepareForSpeech`, package `core`): URLs become "link", whitespace collapses, emoji and formatting markers are dropped, "New post in <channel>" is prepended. Posts over the maximum length are cut at a sentence boundary with "… and more".
- Audio focus: transient focus with ducking, released when the queue drains. Phone calls and other apps taking the focus arrive as `audio_session` interruptions: the queue pauses and the interrupted item is spoken again afterwards. No telephony permission is needed.
- Settings (`ReadAloudScreen`): speed, pitch, maximum length, language when unknown, voice per language, and a preview.

## 8. Android platform notes

- **Foreground service** via `flutter_foreground_task`, service type `specialUse` with `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` describing the persistent Telegram connection. `dataSync` is not usable: Android 15 and later cap it at 6 hours per day. The plugin does not declare the service, so the app manifest declares it with the type and the property. The service shows a permanent "Watching N channels" notification with a Pause action.
- **Background watching** (`service.background`, device-local, not synced) is read by `CoreHost._connect` when the core is brought up. Off keeps the service from starting at all and stops one Android restored on boot, and the UI spawns the core in-process. The stop also holds for later boots, because the plugin's `RebootReceiver` skips `autoRunOnBoot` for a service stopped deliberately. The setting applies at the next app start, because the core cannot move between the service and the app while TDLib runs. Changing it offers "Restart now" (`AppHost.restart`): the host stops the service, or shuts the in-process core down, so TDLib is closed; then `tf/app.restart` starts `RestartActivity` in its own process (`:restart`), which kills the app's process and launches the app, and the new start settles where the core runs. Without the service there is no Telegram connection once the device dozes.
- **The service notification** sits on channel `core` at `LOW`. Android raises a foreground service's channel to `IMPORTANCE_LOW` whatever the app asks for, so no lower importance exists. How a `LOW` notification looks depends on the phone: stock Android puts it in the Silent section without a status-bar icon; Samsung's One UI shows it among the others, with its icon. The user can turn the `core` channel off in Android's settings; the service stays in the foreground and watching goes on, with nothing in the shade or the status bar. The last row of Notifications and sounds (`SystemNotificationSettingsRow`) opens Android's notification settings of the app (`tf/notifications.openAppSettings`, `ACTION_APP_NOTIFICATION_SETTINGS`), where every channel, `core` included, is turned off or changed.
- **Core isolate.** The foreground task runs a Dart callback in its own Flutter engine (`CoreServiceHandler`, the service host). It spawns the core isolate and registers the core's `SendPort` with `IsolateNameServer` under `telegram_feed.core`. The UI engine looks the port up on start and talks over it; both engines run in the same process, so ports work across them.
- **The core isolate is never respawned**, because each isolate would start its own `td_receive` loop. After a logout TDLib closes its client (`AuthClosed`); the core isolate creates a new client and gateway and `CoreServer.replaceGateway` swaps it in behind the same port, so UI clients see the new auth states.
- **Handing TDLib over.** Android restores the foreground service by itself when the process comes back, before Dart runs (`TaskStarter.system`), so the app can find a service core running after a kill. Stopping the service does not take that core down: its `td_receive` pump isolate keeps polling, and a second pump aborts the process ("Receive must not be called simultaneously from two different threads"). A core therefore hands TDLib back on the protocol's `shutdown` call: it closes TDLib's client and waits for `authorizationStateClosed`, so the database lock is free, then kills the receive isolate and waits for its exit (`FfiTransport.stopReceiving`). The service's `onDestroy` waits for `onStart` to finish, shuts its core down, and only then takes the port out of `IsolateNameServer`. `CoreHost` waits for that mapping to disappear, and asks any core still registered to stand down, before spawning its own.
- **Plugins with platform-to-Dart callbacks** (`flutter_tts`, `flutter_local_notifications`) cannot run in the core isolate: Flutter routes platform messages to the root isolate only. The service host owns them; the core sends it match events over the port. Callback-free method-channel calls (for example `path_provider`) work from the core isolate through `BackgroundIsolateBinaryMessenger`.
- **Battery.** Without an exemption from battery optimization Android kills the service after a while. The rules screen shows a banner asking for it until it is granted; the banner checks again when the app resumes and after the system dialog closes.
- **TDLib binaries.** `libtdjson.so` for `arm64-v8a` and `x86_64`, built in Docker (`tool/tdlib`, TDLib's own `example/android` build: NDK 23.2, static OpenSSL and libc++) from the commit pinned in `packages/tdlib_bindings/schema/TDLIB_COMMIT` (TDLib 1.8.67). TDLib has no git tags after v1.8.0, so the pin is a commit. The binaries have 16 KB LOAD alignment. `.github/workflows/tdlib.yml` publishes them as the release `tdlib-<sha7>`; `tool/fetch_tdlib.dart` downloads them into `jniLibs`. They are not committed.
- **Platforms.** Android only. iOS has no persistent foreground service, so on-device rule notifications cannot be delivered in real time there. There is no web build.

## 9. Several accounts

`AccountStore` keeps `accounts.json` in the support directory, outside every per-account database, since it says which of them to open. It holds the accounts (id, label) and the one in use, at most four. `appPaths([accountId])` derives the account's TDLib directory and app database from its id; account 1 uses `tdlib/` and `app.sqlite`. Both hosts call `appPaths()` without an id and so open the active account.

Switching restarts the host instead of running a second core: the root (`main.dart`) disposes the host, which closes the core client, the database and sync, writes the new active id and starts a fresh host; everything under `MaterialApp` rebuilds. An account without a session shows the login screen. `AccountSwitch` sits in `MaterialApp.builder`, above the navigator, so the Accounts screen, a pushed route, can reach it. Removing an account deletes its TDLib directory and its database file. The last account cannot be removed.

## 10. Privacy and security

- **App lock** (`settings/app_lock.dart`): a PIN of at least four digits, kept as a salted SHA-256 hash in the keystore (`PinStore`, the same storage as the AI key), and, where the user allows it, the device's fingerprint or face through `local_auth`, with the PIN always available. `LockGate` sits in the app's builder above the navigator, so no screen and no notification tap bypasses it, and locks again when the app has been in the background longer than `lock.timeoutSeconds` (at once, a minute, five minutes, an hour; an hour while unset). `AppLockScreen` shows `LockScreen` first when a PIN exists, so the lock cannot be changed or removed without it.
- The TDLib database and files are in the app's private storage. They are not encrypted: `database_encryption_key` is empty, and the app lock does not change that.
- Nothing leaves the device except Telegram traffic, with two exceptions the user turns on: Google Drive sync (section 5.5) stores feeds, rules and some settings in the user's own Drive, in a folder only this app can read; AI semantic rules (section 6.4) send the text of the posts they check to the endpoint the user configured.
- No analytics and no crash reporting.
- Logout turns sync off, deletes the AI key, wipes the app database and logs out of TDLib, which deletes its database and files directory.
- The manifest declares `INTERNET`, `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `WAKE_LOCK` and `VIBRATE`; plugins add their own (`local_auth` adds `USE_BIOMETRIC`).
- TDLib is built from pinned sources in Docker (`tool/tdlib`), never downloaded prebuilt from third parties.

## 11. Testing

- `rules`: unit tests for the parser and evaluator, including Unicode word boundaries, Cyrillic case folding and schedules that wrap past midnight.
- `core`: timeline merge, search, filters, rule engine and sync merge, tested against a fake `TelegramGateway` with scripted histories and update streams.
- `telegram_gateway`: tested against a scripted fake transport.
- `app_db`: a migration test for every schema version, against the dumps in `drift_schemas/`.
- `app`: fixture data for every widget test is in `app/test/fixtures.dart`: the fake gateway (channels, histories that page, live post events, `arrive` for a post that comes in now and `arrivedUnseen` for one that came in while the app was down), fixture channels and posts, and the pump helpers. No test needs a real account, channel or post.
- `app`: where a feed opens is tested in `app/test/feed_positioning_test.dart`: every read state (nothing read, read to a point, read through, one channel of two unread, one read position shared by two feeds, a channel timeline), reading that moves Telegram's read positions, the last post reading every channel of the feed, the button going to the divider, back to a tapped reply and to the end, the position kept across a restart and forgotten at the newest post, the app resting in the background and coming back without moving the reader, posts arriving while it rested or while the reader reads, and posts that came in while the app was down. The database is a file there, so closing and reopening it is a restart of the app.
- `app`: golden tests for the main screens (`tool/update_goldens.sh` regenerates them on Linux in Docker).
- `app/integration_test`: runs the real app on an emulator. The feed flow runs only when the emulator's account is logged in.
- Manual testing runs on Android emulators with x86_64 system images, never on personal devices. Telegram's test-DC test numbers (`99966XYYYY`) no longer work: Telegram disabled them ([tdlib/td#3083](https://github.com/tdlib/td/issues/3083)). The emulator therefore logs in with a spare real account on the production DC; the owner of that account types the phone number and code, and the TDLib session is reused between runs.
- `tool/ci.sh` runs what CI runs: analyze, format check, package tests and app tests.
