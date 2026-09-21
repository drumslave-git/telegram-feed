# telegram-feed — Product specification

## 1. Purpose

A Telegram client for reading channels, not for chatting. Users combine channels into feeds, get notifications from keyword rules instead of a per-chat on/off switch, and can have posts read aloud.

It does not replace the official Telegram app. Chats, calls, stories and account management stay there, and this app links to it where needed.

## 2. Decisions

| Topic | Decision |
|---|---|
| Name | "Unofficial Telegram Feed" in the app and its notifications, "TG Feed" under the launcher icon: Telegram's API terms allow "Telegram" in an app's title only after "Unofficial". The repository and the package are `telegram-feed`. |
| Platform | Android only. iOS cannot run a persistent background service, so real-time on-device rule notifications are impossible there. No web build. |
| Telegram access | User account through TDLib (MTProto). The session lives on the device. Up to four accounts per device, each with its own session, feeds and rules. |
| UI framework | Flutter |
| Audience | Public product, open source |
| License and money | GPL-3.0. No monetization. |
| Feed sources | Only channels the account has joined, public or private. The app never joins, leaves or searches for channels. |
| Feed view | One chronological timeline laid out like a Telegram chat: oldest on top, newest at the bottom |
| Main screen | Tabs: "Feeds", one tab per Telegram chat folder, and "All channels". Channels only: groups, bots and private chats are not shown. |
| Feed filters | Each feed can limit what it shows. A post hidden by every feed that contains its channel raises no rule notification. |
| Read state | Telegram's own: one read position per channel, shared by every feed, the channel's own timeline and the official app. Reading, opening, the unread divider, the counters and the button to the newest posts work as in the official app. |
| Media | Photos, video, voice and audio play in the app |
| Interactions | Open in Telegram, share, copy link, react, comment, save to Saved Messages |
| Rules | Boolean conditions (AND / OR / NOT, phrases, whole word, case sensitivity), scoped per channel or global, with optional schedules. Never per feed. AI semantic rules check a description in the user's words through an OpenAI-compatible endpoint the user configures. |
| Rule text | Post text and media captions only. Forward origin, edits and link targets are not matched. |
| Rule actions | Priority (silent, normal, urgent) and read-aloud |
| Read aloud | Device text-to-speech with per-post language detection |
| Background | A persistent foreground service keeps TDLib connected. It can be turned off. |
| Sync | Feeds, rules and some settings sync through the user's own Google Drive. No backend. |
| API credentials | `api_id` and `api_hash` are never committed; every build supplies its own |

## 3. User stories

The primary user follows 20 to 200 Telegram channels (news, niche communities, alerts, deals) and is overwhelmed by the official app's flat chat list and all-or-nothing notifications.

### Feeds and channels

- I log in with my Telegram account so the app sees the channels I already follow.
- I create, rename, reorder and delete feeds on the "Feeds" tab. Its floating button creates one, dragging reorders, and a row's menu edits its channels, renames, marks it read or deletes it.
- My Telegram chat folders appear as tabs, each listing the folder's channels the way Telegram lists chats (photo, newest post, time, unread count), including channels I joined through a folder invite link.
- "All channels" lists every joined channel with a search box. Channels I archived in Telegram are left out of it and appear behind an "Archive" row at its top.
- A long press on a folder tab creates a feed from the folder's channels (a one-time copy) or marks the folder read.
- Every list of channels tags each channel with the feeds it belongs to.
- A long press on a channel row offers to mark it read, open its info, or add it to one of my feeds.
- I add channels to a feed from the channels I have joined, with a search box; I tick as many as I want and add them with one press. A checkbox hides the channels that are already in a feed, and the picker remembers it. Joining happens in the official app.
- A channel can be in several feeds. Removing it from a feed does not leave the channel in Telegram.
- I set what a feed shows: all posts, only posts with media or only text; which media types; videos from a minimum length; text posts from a minimum length. A post is shown whole: one picture or video that passes brings the rest of the album and its caption, unless the feed's "Show the whole post" box is off. Hidden posts are read along with the posts around them, and my rules stay quiet about them unless another feed with the same channel shows them.

### Reading

- A feed shows the posts of all its channels in one chronological list, oldest on top and newest at the bottom, with the channel name on every post. A channel opens the same way, with its pinned post in a bar on top and Telegram's own read position.
- A feed or a channel opens where I left it scrolled up, also after the app was closed; otherwise at the first unread post under an "Unread posts" divider, or at the newest post when everything is read. Nothing is kept when I left at the newest post, or on a post still unread.
- I scroll up without end; older posts load as I go. Posts that arrive while I read older ones wait behind a button with their count.
- Each feed shows an unread count as Telegram counts it (every part of an album is a post): posts, or channels with unread posts, as the "Count unread posts" switch says. A feed counts only the posts it shows. Folder tabs count the same way.
- A post is read once 80 % of it has been on the screen, an album once all of it has. A feed reads like one chat: everything older than the newest post read is read too, in every channel of the feed, so at the last post the whole feed is read. Reading here moves Telegram's read position, so the channel is read in every feed, in its own timeline and in the official app.
- The button to the newest posts counts the unread posts. A tap goes to the "Unread posts" divider while I have not seen it in this visit, then back to the post whose reply quote I tapped, then to the very end.
- I mark a feed, a folder or a channel read in one action.
- A post that answers an earlier post shows that post above its text (the quote the author picked, or the beginning of it); a tap takes me there.
- A forwarded post names the channel it came from; a tap opens the original post when I follow that channel.
- A post with a link shows the site's card (site, title, description, picture, with a play badge for a video); a tap opens the link.
- A Telegram link in a post that leads to a channel I follow opens here, at that post. Other links open in the app that handles them.
- A double tap on a post sends my quick reaction.
- I copy a post's text from its menu, and a block of code with the button at its end.
- I select several posts and copy, share or save them together.
- I open the original post in the official Telegram app.
- The day of the topmost post floats over the list while I scroll.
- I set the text size of posts.
- I close any screen with a swipe from the left edge.
- When the app cannot reach Telegram, the title says so.

### Media

- Photos show inline. Video, voice and audio play in the app. Albums show as a mosaic.
- Stickers are drawn, animated ones included, and a round video message plays in place.
- Voice and music can be dragged to seek and played at 1×, 1.5× or 2×. A bar at the bottom keeps them playing while I scroll or open another screen.
- A tap on a video plays it full screen at once, in the orientation I hold the phone, from the beginning. There I seek, zoom with a double tap or a pinch and move the zoomed picture, hold a finger down for 2× speed, and swipe down to close.
- The viewer pages sideways through the pictures and videos of the whole feed, loading older ones as I go. It shows which channel a picture came from, its day and caption, and lets me share it, save it to Saved Messages, save it to the phone's gallery, or shrink the video to a floating player. Leaving the app while a video plays moves it into Android's picture-in-picture window.
- Leaving full screen stops the video and its download, unless the video loads by itself; a video that autoplays in the timeline goes on playing there without sound.
- Every video has a download button in its top left corner that keeps the whole file in Telegram's cache, with progress and cancel.
- Automatic downloads are set per connection (mobile data, Wi-Fi, roaming) as in the official app: a switch, Telegram's Low, Medium and High presets, and photos, videos and files with size limits. Larger videos can have their first seconds loaded ahead. A video autoplays when it loads by itself and autoplay for GIFs or videos is on.

### Search

- The magnifier on the home screen searches the posts of every channel I follow.
- The magnifier in a feed or a channel searches all of its channels at once; what the feed hides is not found. Results name the channel, show the text and the date; a tap opens the timeline at that post, with arrows and a counter to step through the matches.
- Chips pick the kind of post: media, links, files, music, voice. A chip works without words.
- A calendar, and a tap on any day label, jumps to a date.
- An open search bar offers the words I looked for last.
- The comments of a post can be searched.

### Notification rules

- A rule is scoped to one channel or to all channels in my feeds.
- A rule's condition is built from terms combined with AND / OR / NOT. A term is a word or phrase with options: whole word, case sensitive.
- A rule with an empty condition notifies about every post of its channels, including posts without text; the notification then says what the post is (a photo, a video, a file). It still takes a priority, a schedule and read-aloud.
- A rule has a priority: silent (tray only), normal, urgent (breaks through Do Not Disturb where Android permits).
- I choose the sound and the vibration of normal and urgent notifications; silent ones stay silent. A change applies at the next start of the app.
- A rule can request read-aloud.
- A rule can have a schedule: active on selected weekdays between two times.
- A rule can be switched off without deleting it.
- A matching new post raises a notification that opens the post in its feed. When several rules match, the highest priority wins, and read-aloud happens if any matching rule asks for it.
- Posts that match no rule raise no notification. The app does not replicate Telegram's own per-chat notifications.
- Rules match post text and media captions. Edited posts are not matched again.
- I test a rule against recent posts of a channel to see what it would have matched.
- Posts from the same channel collapse into one group whose "N new posts" counts only the ones still in the shade. A post deleted in Telegram takes its notification with it.

### Background watching

- While the app watches channels for me it keeps a permanent "Watching N channels" notification with a Pause action. That is what lets rules notify me when the app is closed.
- That notification makes no sound. Whether it has a status-bar icon, and where it sits in the shade, depends on the phone.
- Notifications and sounds has a row that opens Android's notification settings of the app, where I can turn that notification off. Watching goes on without it.
- I can turn background watching off. The permanent notification then goes away and rules only notify me while the app is open. The choice applies at the next start of the app and stays on this device.

### Read aloud

- When a rule with read-aloud fires, the app speaks "New post in <channel>" followed by the post text, also with the screen off.
- Every rule notification carries a "Listen" action that speaks the post on demand.
- The app detects the post's language and picks a matching voice.
- Posts are queued, never spoken over each other and never dropped. Other audio is ducked, and a phone call pauses speech.
- Settings: speed, pitch, maximum length, language when detection fails, voice per language, and a preview.

### Interactions

- I react to a post with the reactions the channel allows.
- I open the comments of a post and reply, when the channel has a discussion group.
- I share a post or copy its link.
- I save a post, with its whole album, to my Saved Messages, and read Saved Messages in the app from Settings.

### Accounts and security

- I use up to four Telegram accounts and switch between them in Settings.
- I lock the app with a PIN, and with my fingerprint or face where I allow it, with a timeout.
- My settings, feeds and rules sync between my devices through my own Google Drive when I turn it on.

## 4. Screens

1. **Login**: phone number, code, two-step password, new-account name, or QR-code login. States that the app reads the channels the account has joined.
2. **Home**: search over all channels, Rules and Settings in the app bar; tabs Feeds (list of feeds with counts, and a button that creates one), one per folder, All channels.
3. **Feed editor**, the feed's info screen: the ordered channels with the add-channel sheet and the filter row, and tabs with the shared media of all the feed's channels: Media, Files, Links, Music, Voice.
4. **Timeline** of a feed or a channel: posts drawn like the official app, with full-width bubbles (coloured channel name and the channel's photo at the right end of that line, albums as a mosaic, formatted text, views and time in the corner, reactions, comments bar, link cards, day labels, the floating day), the "Unread posts" divider, and the button to the newest posts with the number of unread posts. A long press opens the post menu: reactions, Open in Telegram, Comments, Share, Copy text, Copy link, Save to Saved Messages, Select, and on video posts the autoplay and download settings.
5. **Search** in a feed, a channel or all channels: results with channel, text and date, filter chips, recent queries, a calendar.
6. **Channel info**, opened from the channel's title: photo (a tap opens it full screen), name, subscribers, description, link, QR code, similar channels (a tap opens one in the official app), and the shared media tabs. No mute and no leave.
7. **Comments** of a post: the post on top, comments as bubbles, a reply field and a search.
8. **Media viewer**: photos and videos full screen, with the mini player and picture-in-picture.
9. **Rules list** and **rule editor** (visual builder and text form, scope, priority, read-aloud, schedule, AI description, dry run).
10. **Settings**, laid out like the official app's: the account profile (photo, name, username, phone, bio, Telegram ID), Accounts, Saved Messages; Chat settings (post text size, theme); Privacy and security (app lock); Notifications and sounds (rule sounds and vibration, badge counting, background watching, a row that opens Android's notification settings); Data and storage (storage usage and cache clearing, automatic downloads per connection, autoplay); Read aloud; AI rules; Google Drive sync; About and licenses, with the version at the bottom. Log out is in the menu.

## 5. Out of scope

- Sending messages in private chats or groups. Comments and reactions are the only writes.
- Stories, calls, secret chats, Telegram Premium features.
- Joining or leaving channels, adding channels the account has not joined, editing Telegram's chat folders, muting a channel (rules take that place).
- Server-side session storage. The app never uploads the Telegram session.
- Algorithmic ranking of the feed. Per-feed rules.
- Polls, quizzes, giveaways, invoices and paid media; they show as unsupported content.
- Selecting part of a post's text (the whole text can be copied).
- Translating posts, transcribing voice messages, voice-message waveforms.
- Swiping a channel row to mark it read (the row's menu does it).
- An in-app browser and Instant View. Registering the app as a handler for t.me links from other apps.
- Chat wallpapers and bubble colours. Night mode on a schedule. Interface languages other than English.
- Notification actions other than Listen and Open in Telegram. An in-app banner for new posts.
- Sharing into the app from other apps. A home-screen widget.
- Active sessions and two-step verification management (they stay in the official app).
- Per-channel cache size. Channel statistics.
- Sponsored posts.
