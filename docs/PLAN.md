# telegram-feed — Plan

Open work only. A task leaves this file in the commit that finishes it; `git log` records finished work.

Legend: `[ ]` not started, `[~]` in progress (name the branch).

**Current phase:** Parity with the official app. **Next task:** Q-5.

## Defects

- [ ] Q-5 Custom-emoji and paid reactions are drawn on posts, and the picker offers the channel's custom emoji.
- [ ] Q-6 Comments show their media: photos, videos, stickers, voice and files.
- [ ] Q-7 An album raises one rule notification, and sharing an album carries its caption whichever part holds it.
- [ ] Q-8 The app lock is one lock for every account on the device and survives a logout; the recents switcher shows no content while a lock is set; wrong PINs are delayed as in the official app (from the third try: 5, 10, 15, 20, 25, 30 s). Check on the emulator whether switching accounts skips the PIN.
- [ ] Q-9 Login with an email code works.
- [ ] Q-10 Recent searches keep only the queries whose result was opened.
- [ ] Q-11 The search over all channels includes archived channels, and the "Archive" row is shown when the list is empty or the channel search finds nothing.
- [ ] Q-12 Every post that comes on the screen counts a view and refreshes its counter, older posts included.
- [ ] Q-13 Channels with protected content: Copy text, Share, Save to Saved Messages and Save to gallery are hidden, and the viewer blocks screenshots.
- [ ] Q-14 A rule notification goes away when its post is read here or in the official app, and "N new posts" is recounted when a notification is swiped away or tapped.
- [ ] Q-15 The screen stays on while a video plays, and a voice message or track that has ended leaves the audio bar.
- [ ] Q-16 Saved Messages: Share, Copy link and Save to Saved Messages are not offered there, and a post saved elsewhere appears without reopening the screen.
- [ ] Q-17 Check on the real account whether an album post shows its reactions and comments bar; read them from the album's primary message as the official app does.
- [ ] Q-18 "Clear cache" frees what it says: check what `optimizeStorage` removes with default limits and pass explicit ones.
- [ ] Q-19 Code comments and docs that state official behaviour wrongly are corrected: `post_card.dart` (long press), `unread_badge.dart` ("999+"), `accounts.dart` (account limit), `thread_screen.dart` (opening position), `audio_bar.dart` (bar position), `home_screen.dart` (tab counting, the `+` in the tab bar), `timeline_search.dart` (row dates), `data_storage_screen.dart` (slider steps), `notification_launch.dart` (feed opened), `models.dart` and `mapping.dart` (stickers, custom emoji); ARCHITECTURE §5.9 (menu order, album layout source), §5.4 (`markViewed`), §5.10 (recents in the comment search), §6.3 (where the permission is asked); SPEC §3 (accounts are listed by name and phone only after Accounts was opened on each, "swipe down to close" closes both ways, the download button on album cells and round videos, the calendar in the home search).

## Differences from the official app

Each task makes the app behave as the official Android app does. SPEC.md and ARCHITECTURE.md change in the same commit where a task reverses a decision recorded there.

### Timeline

- [ ] Q-20 A tap on a post opens the menu as a popup at the touch point, with the reactions strip above it; a long press starts selection and a drag extends it; selection stops at 100 posts.
- [ ] Q-21 A swipe to the right from anywhere on the screen goes back.
- [ ] Q-22 Links: a link hidden behind text asks "Do you want to open …?" first; a long press on a link offers Open and Copy link; a hashtag opens a search for it; a phone number offers call and copy; a tap on inline code copies it.
- [ ] Q-23 The button to the newest posts appears after 100 dp of scrolling towards the newest posts and hides after 100 dp the other way, animated; it is always shown after opening at unread posts, after a jump and when a post arrives.
- [ ] Q-24 A jump to a post scrolls there animated when the post is loaded and puts it in the middle of the screen with its top visible; a link to a post of the channel on screen scrolls in place; the highlight lasts 1 s and ends when the list is dragged.
- [ ] Q-25 The pinned bar holds every pinned post: a tap goes to the current one and moves on to the next older, a button opens the list of pinned posts, and hiding the bar is remembered.
- [ ] Q-26 Posts that arrive while the app is in the background get a new "Unread posts" divider, and the list returns to it.
- [ ] Q-27 Day separators always read "October 3", with the year only for posts older than a year; a tap on the floating date jumps to the start of that day; a tap on a day separator opens a month calendar with a media thumbnail per day.
- [ ] Q-28 Haptic feedback on a long press, on a reaction and at the selection limit.
- [ ] Q-29 A timeline with more than 300 unread rows opens at the first unread post.

### Posts

- [ ] Q-30 Inline URL buttons under a post.
- [ ] Q-31 Quotes are drawn as quote blocks; expandable quotes are collapsed to three lines until tapped; code blocks show their language.
- [ ] Q-32 Media under a spoiler is blurred until tapped, and sensitive media is covered.
- [ ] Q-33 A photo or video shows its blurred miniature while it loads, with the loaded size and a cancel.
- [ ] Q-34 The author's signature stands before the time, a pinned post has the pin icon in its footer, and posts with only emoji are drawn large.
- [ ] Q-35 The comments bar shows the photos of up to three recent commenters, the exact count and a dot for unread comments.
- [ ] Q-36 The link card shows the author, up to six lines of description and its button ("Open channel", "Open message" and the like); a caption can stand above its media.
- [ ] Q-37 Views and reaction counts are cut, not rounded ("1.9K"); a file row shows its thumbnail and opens the file; a mention opens the channel in the app.
- [ ] Q-38 Location, venue, contact, dice, game and checklist posts are drawn.

### Reactions, menu and comments

- [ ] Q-39 The reaction picker opens to the full list with an arrow, and a reaction animates. The quick reaction is chosen in Settings and stays as chosen; a double tap anywhere on the post sends it, and does nothing when the channel does not allow it.
- [ ] Q-40 The post menu offers Save to gallery, Save to downloads and Save to music by the post's media, and Report.
- [ ] Q-41 A comment thread opens at the first unread comment under a divider, marks comments read, loads older comments on scroll, and is titled "N comments".
- [ ] Q-42 Comments are replied to one by one and show reply quotes, reactions and a menu (Reply, Copy, edit and delete of my own); a comment that failed to send offers Retry and Delete; a discussion that needs joining, restricts me or runs slow mode says so in place of the field.
- [ ] Q-43 The search in comments has the arrows, the "N of M" counter and paging of the timeline's search, and lands on the comment itself.

### Search

- [ ] Q-44 A search in a feed or channel runs when it is submitted, jumps to the newest match at once and marks the found words inside the posts; "Show as list" switches to the result list and back, and Back leaves the list before it closes the search.
- [ ] Q-45 Result rows mark every word of the query and show the time today, the weekday within a week, "Sep 12" within a year, and "12.09.25" before that.
- [ ] Q-46 The search over all channels takes typed dates ("yesterday", "12 sep", a month) as a date filter, and shows media, files, links and music in their own layouts.
- [ ] Q-47 A recent search is removed singly, and "Clear" asks first.

### Home, channel info and shared media

- [ ] Q-48 "All channels" is the first tab; a tab's counter counts channels with unread posts; a tap on the active tab scrolls its list to the top; a long press on "All channels" marks everything read.
- [ ] Q-49 A channel row shows up to three thumbnails of its newest post and "N photos" for an album, with the media label in the accent colour; a muted channel's counter is grey; counters print the whole number.
- [ ] Q-50 A channel row is 70 dp high with a 52 dp photo and a divider, shows the verified mark, and dates as in Q-45; a new post moves its row at once, animated.
- [ ] Q-51 A long press on a channel row also offers "Mark as unread".
- [ ] Q-52 Channel info: the photo pulls down to a full-width gallery of every channel photo, links in the description open, the subscriber count is written in full, and the link row opens the share sheet.
- [ ] Q-53 Shared media: the grid pinches from two to nine columns, has a date scroller and a photo/video filter; Files, Links and Music can be searched; a long press on an item offers "Show in chat"; empty tabs are left out and GIFs have their own.

### Media

- [ ] Q-54 A video of 10 seconds or more reopens where it was left; a video of up to 30 seconds loops, a longer one returns to its start with the controls shown.
- [ ] Q-55 The viewer's menu has "Show in chat" and "Open in…"; a landscape video has a rotate button; dragging the seek bar shows the frame; a tap near a side edge turns the page; the caption keeps its formatting and every link in it opens.
- [ ] Q-56 Holding a finger on a video starts at 2× and a sideways slide changes the speed; on a video longer than three minutes the left third rewinds and the right third speeds up in steps. The speed menu adds 0.2× and a slider up to 3×.
- [ ] Q-57 The floating player is resized with a pinch, thrown off a side to close, shows its controls on a tap and seeks on a double tap, and remembers its place; Android's picture-in-picture window has play and pause.
- [ ] Q-58 Voice messages and music play on to the next one, with repeat and shuffle for music; they show on the lock screen and in a notification, and answer the headset's buttons; closing a video resumes what it paused.
- [ ] Q-59 The audio bar sits under the header; a tap opens a player (seek, speed, previous and next, the playlist) for music and goes to the post for a voice message; a long press on the speed offers 0.5× to 2× and a slider; voice and music keep separate speeds.
- [ ] Q-60 Save to gallery takes the whole album; a round video that scrolls away keeps playing in a floating window.

### Notifications

- [ ] Q-61 One notification per channel that lists its matched posts as a conversation, with the channel's photo and the post's picture; captioned media is marked with 🖼, 📹, 🎬 or 📎.
- [ ] Q-62 A channel sounds at most twice in three minutes, further posts arrive silently; a post the channel sent silently makes no sound; an edited post updates its notification.
- [ ] Q-63 While the app is open, a matching post pops up, except for the feed or channel on screen, which only plays the in-app sound.
- [ ] Q-64 With the app locked, a notification says only that there is a new post.
- [ ] Q-65 The launcher icon shows the number of unread posts, with the official app's three badge switches.
- [ ] Q-66 Every logged-in account notifies, with the account's name on the notification.

### Login, accounts and settings

- [ ] Q-67 Login: a country picker with the code and number in separate, formatted fields; "Is this the correct number?"; one box per digit of the code, sent when full; a countdown before the code can be sent again; a flood wait says how long.
- [ ] Q-68 Accounts are listed in Settings with photo, name and unread count, and an account that was added but never logged in leaves no row.
- [ ] Q-69 Cached media is removed after a set time (channels: one week until changed) and above a set cache size; storage usage shows a chart by kind of file and clears by kind.
- [ ] Q-70 Text size runs from 12 to 30 with 16 as the start, and its preview is a post bubble that changes while the slider moves.
- [ ] Q-71 Turning background watching on or off applies without restarting the app.
- [ ] Q-72 Voice messages load by themselves whenever automatic downloads are on for the connection; "preload larger videos" applies only above 2 MB; the size limit is a continuous slider.
- [ ] Q-73 The app lock takes a four-digit PIN that unlocks when complete, or a password; the header of the home screen has a lock button; "5 hours" is among the timeouts.

## Phase 4 — Extras

- [ ] P4-3 AI-generated podcast from a feed.
- [ ] P4-4 Optional cloud voices for read-aloud.
