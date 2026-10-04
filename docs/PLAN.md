# telegram-feed — Plan

Open work only. A task leaves this file in the commit that finishes it; `git log` records finished work.

Legend: `[ ]` not started, `[~]` in progress (name the branch).

**Current phase:** Parity with the official app. **Next task:** Q-74.

## Differences from the official app

Each task makes the app behave as the official Android app does. SPEC.md and ARCHITECTURE.md change in the same commit where a task reverses a decision recorded there.

### Media

- [ ] Q-74 Voice messages and music show on the lock screen and in a notification, and answer the headset's buttons.

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

Built and covered by tests; what is listed here has not been used on the emulator yet. Real Telegram (the spare account) has seen none of the tasks from Q-42 on.

- [ ] V-1 Shared media: pinch the grid from two to nine columns, drag the date scroller, search Files, and "Show in chat" from a channel's info, from the home screen and from a feed's info.
- [ ] V-9 Viewer: "Show in chat" from a feed, from shared media and from search; the picture following the seek bar on a downloaded video; edge taps in a feed and in an album; a caption link to a channel; dark and Ukrainian.
- [ ] V-11 Floating player: pinch (two fingers, not possible with adb), double tap on each half, the place and size after reopening; Android's picture-in-picture button on an image older than Android 12.
- [ ] V-12 Sound: a video pauses a playing track and closing the viewer, and closing the floating player, plays it on; a track paused by hand stays paused.
- [ ] V-13 Audio bar: the tap to the post of a voice message from another screen; previous, next, repeat and shuffle in the player with real music; the long press on the speed; a voice message at 2× followed by music at 1×; dark and Ukrainian.

## Phase 4 — Extras

- [ ] P4-3 AI-generated podcast from a feed.
- [ ] P4-4 Optional cloud voices for read-aloud.
