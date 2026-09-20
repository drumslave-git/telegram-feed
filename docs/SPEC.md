# telegram-feed — Product Specification

Working name: **telegram-feed** (rename later).
Status: draft v0.1, 2026-09-17. Derived from the founder Q&A; every decision below can be revisited, but changes should be recorded here.

## 1. Vision

A custom Telegram client focused on *consumption* of channels rather than chatting. Users combine many channels into feeds, get notifications driven by flexible keyword rules instead of a per-chat on/off switch, and can have posts read aloud.

Not a replacement for the official Telegram app. Chats, calls, stories, and account management stay in the official client. This app deep-links to it when needed.

## 2. Decisions at a glance

| Topic | Decision |
|---|---|
| Platforms | Android. iOS is not on the roadmap: without a persistent background service it cannot deliver real-time rule notifications on-device. A web build was completed in phase 3 and dropped on 2026-09-17 (ARCHITECTURE.md decision log). |
| Telegram access | User account via MTProto (TDLib), session lives on-device |
| UI framework | Flutter |
| Audience | Public product, open source |
| Monetization | None; open source under GPL-3.0, maybe donations later |
| Feed sources | Only channels the user is a member of (public or private). No search-and-join of unjoined channels. |
| Feed view | Single chronological timeline laid out like a Telegram chat: oldest on top, newest at the bottom. Opens where the user left it earlier in the session, else at the first unread post, else at the newest |
| Main screen | Tabs: `+` (new feed), "Feeds" with the list of feeds, one tab per Telegram chat folder listing the folder's channels, and "All channels". A feed or a channel opens as its own timeline. Channels only: groups, bots and private chats of a folder are not shown. |
| Feed filters | Each feed can limit what it shows: posts with media, text only or both; media types; minimum video length; minimum length of text posts. A post is shown whole: one picture or video that passes brings the rest of the album and the caption with it, unless the feed's "Show the whole post" checkbox is off. A post hidden by every feed that contains its channel raises no rule notification either, and is not a search result there. |
| Read state | Per feed with unread counter and badge; a post is read once it has been on screen down to its end; the feed opens at the first unread post under an "Unread posts" divider. Reading here marks the post read in official Telegram too; setting to turn off. |
| Media | Full in-app playback: photos, video, voice and audio |
| Interactions | Open in Telegram, share / copy link, react, comment (later phase) |
| Rule expressiveness | Boolean (AND / OR / NOT, phrase, whole word, case sensitivity). AI semantic rules: a description in the user's words, checked by a model behind an OpenAI-compatible endpoint the user configures, with an optional keyword pre-filter |
| Rule scope | Per channel, global, with optional schedules. Not per feed; but a post that every feed with its channel filters out does not notify. |
| Rule actions | Priority level (silent / normal / urgent) and read aloud |
| Rule text source | Post text and media captions only. Forward origin, edits, and link domains are not matched. |
| Read aloud triggers | Automatic when a rule with read-aloud fires; "Listen" action on a notification. AI-generated podcast later. |
| TTS engine | Device TTS with per-post language auto-detection |
| Background strategy (Android) | Persistent foreground service keeping TDLib connected |
| Cross-device sync | Local only for MVP; phase 4 syncs feeds and rules through the user's own Google Drive, with no backend of ours |
| MVP | Login, feeds CRUD, combined timeline with media and read state |

## 3. Users and core stories

Primary persona: someone who follows 20 to 200 Telegram channels (news, niche communities, alerts, deals) and is drowning in the official app's flat chat list and all-or-nothing notifications.

### Feeds
- As a user I can log in with my Telegram account so the app sees the channels I already follow.
- I can create, rename, reorder, and delete feeds. They are listed on the "Feeds" tab of the main screen; `+` creates one, dragging reorders, the row's menu edits its channels, renames or deletes it.
- My Telegram chat folders appear as tabs too, each listing the folder's channels the way Telegram lists chats (photo, newest post, time, unread count), including channels I joined through a folder invite link, which Telegram keeps in that folder's list alone. "All channels" lists every joined channel with a search box; channels I archived in Telegram stay out of it and live behind an "Archive" row at its top. Tapping a channel opens its posts as a timeline, with the channel's pinned post in a bar on top; its read position is Telegram's own.
- Every list of channels tags each channel with the feeds it belongs to.
- A long press on a channel row offers to mark it read, to open its info, or to add it to one
  of my feeds.
- I can add channels to a feed by picking from the channels I am a member of, with a search box over that list. Channels I have not joined cannot be added; joining happens in the official Telegram app.
- I can add the same channel to several feeds.
- I can remove a channel from a feed without leaving the channel in Telegram.
- I can set what a feed shows: all posts, only posts with media or only text; which media types; videos from a minimum length; text posts from a minimum length. Hidden posts count as read, and my rules stay quiet about them unless another feed with the same channel shows them.
- I can open a feed and see posts from all its channels in one chronological list, oldest on top and newest at the bottom as in a Telegram chat, with the channel name on every post.
- The feed opens where I left it earlier in the session; otherwise at the first unread post, and at the newest post when everything is read.
- I can scroll up indefinitely; older posts load as I scroll. Posts that arrive while I read older ones wait behind a button with their count.
- A post that answers an earlier post shows that post above its text — the quote the author
  picked, or the beginning of what it said — and a tap takes me to it.
- A post one channel forwarded from another says so above its text, with the original
  channel's name; a tap opens the original post when I follow that channel too.
- A post whose text carries a link shows the site's card under it (or over it, as Telegram says): the site, the title, the description and the picture, with a play badge when the link is a video. A tap on the card opens the link in the browser or in the app that handles it.
- I can say whether pictures load by themselves on Wi-Fi and on mobile data, and up to what
  size; anything bigger, or on a connection I excluded, waits for a tap.
- I can view photos inline, play video, voice, and audio without leaving the app. Voice and
  music can be dragged to seek and played faster (1x, 1.5x, 2x), and a bar at the bottom keeps
  them playing while I scroll on or open another screen.
- Stickers are drawn, animated ones included, and a round video message plays where it is.
- A tap on a video plays it full screen at once, in the orientation I hold the phone, from the beginning when the timeline was autoplaying it. There I can seek, zoom with a double tap or a pinch and move the zoomed picture, hold a finger down for 2× speed, swipe down to close, swipe sideways through the pictures and videos of the whole feed (older ones load as I go), see which channel a picture came from with its day and caption, share it, save it to Saved Messages or into the phone's gallery, and shrink the video to a floating player. Leaving full screen stops the video and its download; short videos that autoplay in the timeline go on playing there without sound.
- Every video has a download button in its top left corner that keeps the whole file in Telegram's cache, with progress and cancel. Saving a photo or a video into the phone's gallery is decided and planned (PLAN.md H-23).
- I can mark a feed, a folder or a channel read in one action, without scrolling through it.
- Each feed shows an unread count. Posts are marked read once I have seen them down to their end.
- Reading a post here also marks it read in the official Telegram app. A setting turns this off.
- I can close any screen with a swipe from the left edge.
- When the app cannot reach Telegram it says so under the title, instead of looking empty.
- I can copy a post's text from its menu, and a block of code with the button at its end.
- A Telegram link in a post that leads to a channel I follow opens here, at that post;
  everything else opens in the app that handles it.
- I can open the original post in the official Telegram app.

### Notification rules
- I can create a rule scoped to one channel or to all channels the app watches.
- A rule has a condition built from terms combined with AND / OR / NOT. Each term is a word or phrase with options: whole word, case sensitive.
- I can leave the condition empty, and then the rule notifies me about every post of its channels. That is how I follow a channel completely, and it still takes a priority, a schedule and read-aloud.
- A rule has a priority: silent (shows in tray only), normal, urgent (breaks through Do Not Disturb where the OS permits).
- A rule can request read-aloud.
- A rule can have a schedule: active only on selected weekdays between two times.
- A rule can be enabled or disabled without deleting it.
- When a new post matches, I get a notification that opens the post in its feed. If several rules match, the highest priority wins, and read-aloud happens if any matching rule asks for it.
- Posts that match no rule produce no notification. The app does not replicate Telegram's own per-chat notifications.
- Rules are evaluated on post text and media captions. Edited posts are not re-evaluated. A rule with no condition ("every post") also notifies about posts that carry no text at all; the notification then says what the post is — a photo, a video, a file.
- I can test a rule against recent posts of a channel to see what it would have matched.
- Several posts from the same channel collapse into one row, and its "N new posts" counts only the ones still in the shade: what I swipe away or open stops counting, and a post deleted in Telegram takes its notification with it.

### Background watching
- The app keeps a permanent "Watching N channels" notification while it watches channels for me, with a Pause action; that is what lets rules notify me when the app is closed.
- That notification is as quiet as Android allows: silent, at the bottom of the shade, without a status bar icon. Android does not allow hiding it altogether or making it quieter.
- I can turn background watching off entirely. The permanent notification then goes away, and rules only notify me while the app is open.
- That choice applies the next time the app starts, and it stays on this device instead of syncing to my others.

### Read aloud
- When a rule with read-aloud fires, the app speaks "New post in <channel>" followed by the post text, even with the screen off.
- Every rule-triggered notification carries a "Listen" action that speaks the post on demand.
- The app detects the post's language and picks a matching device voice.
- Playback can be stopped from the notification. If several posts arrive at once they are queued, not overlapped.
- Settings: speech rate, preferred voice per language, whether to read aloud while on a call or while other audio is playing (default: duck other audio, never interrupt calls).

### Interactions (later phase)
- I can react to a post with the reactions the channel allows.
- I can open the discussion thread of a post and reply if the channel has one, and search the comments in it.
- I can share a post or copy its link through the system share sheet.
- I can save a post, and with it its whole album, to my Telegram Saved Messages, and read Saved Messages in the app from Settings.

## 4. Screens (Android MVP)

1. **Onboarding / Login**: phone number, code, 2FA password, QR-code login as an alternative. Explains what the app can and cannot see.
2. **Home**: a magnifier that searches the posts of every channel at once, and a tab bar with `+`, Feeds (list of feeds, each with the number of channels that have new posts), folder tabs, All channels; every channel row carries the tags of the feeds it is in. Rules and Settings in the app bar. A long press on a folder tab creates a feed from the folder's channels (a one-time copy).
3. **Feed editor** (the feed's info screen): the ordered list of channels with the add-channel sheet and the filter row, and beside it tabs with the shared media of all the feed's channels at once: Media, Files, Links, Music, Voice.
4. **Feed timeline**: infinite list of posts in chat order, drawn like the official app but with full-width bubbles (coloured channel name with the channel's avatar at the right end of that line, albums as a mosaic, formatted text with links, views and time in the corner with the unread dot beside the time, reactions, comments bar, link preview cards, day labels, and the day of the topmost post floating over the list while it is scrolled), "Unread posts" divider, button to the newest posts with the number of unread posts still below the reader. A long press on a post opens its menu: reactions, Open in Telegram, Comments, Share, Copy text, Copy link, Save to Saved Messages, and on video posts the autoplay settings. A double tap sends the quick reaction. "Select" starts picking several posts: the bar then says how many, and copies, shares or saves all of them at once.
5. **Search in a feed or a channel**: the magnifier in the app bar searches the posts of every channel of the feed at once, with chips for the kind of post to look for (media, links, files, music, voice), as one list of matches with the channel, the text and the date; a tap opens the timeline at that post, with arrows and a counter to step through the matches. What the feed hides is not found either. A calendar in the search bar, and a tap on any day label between the posts, jumps to a date. An open search bar offers the words I looked for last.
6. **Channel info**: opened from the channel's title — photo (a tap opens it on the whole screen), name, subscribers, description, link, and tabs with the shared media of the channel: Media, Files, Links, Music, Voice. No mute and no leave: notifications are the app's own rules and the app never joins or leaves a channel.
7. **Post view**: full post with media viewer, open in Telegram, share.
8. **Settings**: account as a profile (photo, name, username, phone, bio, Telegram ID), logout, media autoplay, background watching, appearance (theme and the text size of posts), storage usage and cache clearing, about and licenses.

Phase 2 adds **Rules list**, **Rule editor**, and **Read-aloud settings**.

## 5. Out of scope (explicit non-goals)

- Sending messages in private chats or groups. Commenting in discussion threads is the only write path besides reactions.
- Stories, calls, secret chats, Telegram Premium features.
- Server-side session storage. The app never uploads the user's Telegram session anywhere.
- Algorithmic ranking of the feed.
- Per-feed rules. Rules attach to channels or to everything. Feeds are for reading; their filters only keep rules quiet about posts no feed shows.

## 6. Phases

**Phase 0, spikes (1 to 2 weeks).** Prove TDLib runs inside Flutter on Android via FFI, that the TDLib client can live in a foreground-service isolate that the UI talks to, and that tdweb is viable for the later web target. See ARCHITECTURE.md section 9.

**Phase 1, Android MVP.** Login, feeds CRUD, add channels, merged timeline, media playback, read state, open in Telegram. No notifications, no rules, no TTS. Ships to a closed beta.

**Phase 2, rules and voice.** Foreground service, boolean rules with schedules, priority notifications, device TTS with language detection, "Listen" action.

**Phase 3, interactions and web.** Reactions, comments, share. Flutter web build on tdweb (built, then dropped; see the decision log).

**Phase 4, extras.** Sync of feeds and rules through the user's Google Drive (no backend). AI semantic rules, AI-generated podcast from a feed, optional cloud voices.

## 7. Resolved decisions (2026-09-17)

- Only channels the user is already a member of can be added to feeds. The app never joins or leaves channels. See ARCHITECTURE.md section 5.2.
- Reading a post in the app marks it read in the official Telegram app. On by default, toggle in settings.
- Name stays `telegram-feed` until a public release.
- License: GPL-3.0.
- Development and testing log in with a spare real Telegram account on the production DC, never the founder's main account. Telegram's test-DC test numbers no longer work (spike P0-1).
- Telegram `api_id` / `api_hash` are never committed. Each build supplies its own via `--dart-define`; the README explains how to obtain them at my.telegram.org.
