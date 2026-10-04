# telegram-feed — Plan

Open work only. A task leaves this file in the commit that finishes it; `git log` records finished work.

Legend: `[ ]` not started, `[~]` in progress (name the branch).

**Current phase:** Parity with the official app. **Next task:** Q-56.

## Differences from the official app

Each task makes the app behave as the official Android app does. SPEC.md and ARCHITECTURE.md change in the same commit where a task reverses a decision recorded there.

### Media

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
- [ ] Q-71 Turning background watching on or off applies without restarting the app.

## Hands-on checks

Built and covered by tests, not yet used on the emulator.

- [ ] V-1 Shared media: pinch the grid from two to nine columns, drag the date scroller, search Files, and "Show in chat" from a channel's info, from the home screen and from a feed's info.
- [ ] V-2 Run the Maestro flows (all nine) against the newest build.
- [ ] V-4 App lock: set a four-digit PIN and unlock on the keypad, set a password and unlock with it, lock from the home screen's header, pick "After five hours"; light, dark and Ukrainian.
- [ ] V-5 Automatic downloads: a voice message loads with files switched off, the size slider moves without steps and names its size, "Preload larger videos" rests at 2 MB or less; light, dark and Ukrainian.
- [ ] V-6 Accounts in Settings: add a second account, back out of its login and see no row; log in to a second account and see the first as a row with photo, name, phone and unread count; switch by a tap, remove by a long press; run `settings.yaml`; light, dark and Ukrainian.
- [ ] V-7 Storage usage on the real account: the chart and the rows by kind match what Telegram stores, clearing one kind leaves the others, "Keep media" and the size stops save; after a day with a short time set, old media is gone and loads again on opening; run `settings.yaml`; light, dark and Ukrainian.
- [ ] V-8 Video in the viewer: a long video opens where it was left, also after the app was closed and from an autoplaying row; a video of up to thirty seconds loops; a longer one returns to its start at its end with the controls shown.
- [ ] V-9 Viewer: "Show in chat" from a feed, from shared media and from search; "Open in…" for a photo and a downloaded video; the rotate button on a landscape video and the orientation after leaving; the picture following the seek bar on a downloaded video; edge taps in a feed and in an album; a caption with bold, a link to a channel and a web link; light, dark and Ukrainian.
- [ ] V-3 Chat settings: drag the text size slider from 12 to 30 and watch the post under it, in light and dark and in Ukrainian.

## Phase 4 — Extras

- [ ] P4-3 AI-generated podcast from a feed.
- [ ] P4-4 Optional cloud voices for read-aloud.
