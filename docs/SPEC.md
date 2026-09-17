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
| Feed view | Single chronological timeline, newest first |
| Read state | Per feed with unread counter, mark on scroll, "jump to first unread", badge. Reading here marks the post read in official Telegram too; setting to turn off. |
| Media | Full in-app playback: photos, video, voice and audio |
| Interactions | Open in Telegram, share / copy link, react, comment (later phase) |
| Rule expressiveness | Boolean (AND / OR / NOT, phrase, whole word, case sensitivity); AI semantic matching in a later phase |
| Rule scope | Per channel, global, with optional schedules. Not per feed. |
| Rule actions | Priority level (silent / normal / urgent) and read aloud |
| Rule text source | Post text and media captions only. Forward origin, edits, and link domains are not matched. |
| Read aloud triggers | Automatic when a rule with read-aloud fires; "Listen" action on a notification. AI-generated podcast later. |
| TTS engine | Device TTS with per-post language auto-detection |
| Background strategy (Android) | Persistent foreground service keeping TDLib connected |
| Cross-device sync | Local only for MVP |
| MVP | Login, feeds CRUD, combined timeline with media and read state |

## 3. Users and core stories

Primary persona: someone who follows 20 to 200 Telegram channels (news, niche communities, alerts, deals) and is drowning in the official app's flat chat list and all-or-nothing notifications.

### Feeds
- As a user I can log in with my Telegram account so the app sees the channels I already follow.
- I can create, rename, reorder, and delete feeds.
- I can add channels to a feed by picking from the channels I am a member of, with a search box over that list. Channels I have not joined cannot be added; joining happens in the official Telegram app.
- I can add the same channel to several feeds.
- I can remove a channel from a feed without leaving the channel in Telegram.
- I can open a feed and see posts from all its channels in one chronological list, newest first, with the channel name and avatar on every post.
- I can scroll back indefinitely; older posts load as I scroll.
- I can view photos inline, play video, voice, and audio without leaving the app.
- Each feed shows an unread count. Posts are marked read as I scroll past them. I can jump to the first unread post.
- Reading a post here also marks it read in the official Telegram app. A setting turns this off.
- I can open the original post in the official Telegram app.

### Notification rules
- I can create a rule scoped to one channel or to all channels the app watches.
- A rule has a condition built from terms combined with AND / OR / NOT. Each term is a word or phrase with options: whole word, case sensitive.
- A rule has a priority: silent (shows in tray only), normal, urgent (breaks through Do Not Disturb where the OS permits).
- A rule can request read-aloud.
- A rule can have a schedule: active only on selected weekdays between two times.
- A rule can be enabled or disabled without deleting it.
- When a new post matches, I get a notification that opens the post in its feed. If several rules match, the highest priority wins, and read-aloud happens if any matching rule asks for it.
- Posts that match no rule produce no notification. The app does not replicate Telegram's own per-chat notifications.
- Rules are evaluated on post text and media captions. Edited posts are not re-evaluated.
- I can test a rule against recent posts of a channel to see what it would have matched.

### Read aloud
- When a rule with read-aloud fires, the app speaks "New post in <channel>" followed by the post text, even with the screen off.
- Every rule-triggered notification carries a "Listen" action that speaks the post on demand.
- The app detects the post's language and picks a matching device voice.
- Playback can be stopped from the notification. If several posts arrive at once they are queued, not overlapped.
- Settings: speech rate, preferred voice per language, whether to read aloud while on a call or while other audio is playing (default: duck other audio, never interrupt calls).

### Interactions (later phase)
- I can react to a post with the reactions the channel allows.
- I can open the discussion thread of a post and reply if the channel has one.
- I can share a post or copy its link through the system share sheet.

## 4. Screens (Android MVP)

1. **Onboarding / Login**: phone number, code, 2FA password, QR-code login as an alternative. Explains what the app can and cannot see.
2. **Feeds list**: cards with feed name, channel avatars, unread badge. Floating action to create a feed.
3. **Feed editor**: name, ordered list of channels, add-channel sheet listing my joined channels with a search box.
4. **Feed timeline**: infinite list of posts, "jump to unread" pill, pull to refresh.
5. **Post view**: full post with media viewer, open in Telegram, share.
6. **Settings**: account, logout, appearance, storage usage and cache clearing, about and licenses.

Phase 2 adds **Rules list**, **Rule editor**, and **Read-aloud settings**.

## 5. Out of scope (explicit non-goals)

- Sending messages in private chats or groups. Commenting in discussion threads is the only write path besides reactions.
- Stories, calls, secret chats, Telegram Premium features.
- Server-side session storage. The app never uploads the user's Telegram session anywhere.
- Algorithmic ranking of the feed.
- Per-feed rules. Rules attach to channels or to everything; feeds are only for reading.

## 6. Phases

**Phase 0, spikes (1 to 2 weeks).** Prove TDLib runs inside Flutter on Android via FFI, that the TDLib client can live in a foreground-service isolate that the UI talks to, and that tdweb is viable for the later web target. See ARCHITECTURE.md section 9.

**Phase 1, Android MVP.** Login, feeds CRUD, add channels, merged timeline, media playback, read state, open in Telegram. No notifications, no rules, no TTS. Ships to a closed beta.

**Phase 2, rules and voice.** Foreground service, boolean rules with schedules, priority notifications, device TTS with language detection, "Listen" action.

**Phase 3, interactions and web.** Reactions, comments, share. Flutter web build on tdweb (built, then dropped; see the decision log).

**Phase 4, extras.** Optional sync backend for feeds and rules. AI semantic rules, AI-generated podcast from a feed, optional cloud voices.

## 7. Resolved decisions (2026-09-17)

- Only channels the user is already a member of can be added to feeds. The app never joins or leaves channels. See ARCHITECTURE.md section 5.2.
- Reading a post in the app marks it read in the official Telegram app. On by default, toggle in settings.
- Name stays `telegram-feed` until a public release.
- License: GPL-3.0.
- Development and testing log in with a spare real Telegram account on the production DC, never the founder's main account. Telegram's test-DC test numbers no longer work (spike P0-1).
- Telegram `api_id` / `api_hash` are never committed. Each build supplies its own via `--dart-define`; the README explains how to obtain them at my.telegram.org.
