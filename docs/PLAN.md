# telegram-feed — Plan

Open work only. A task leaves this file in the commit that finishes it; `git log` records finished work.

Legend: `[ ]` not started, `[~]` in progress (name the branch).

**Current phase:** Round L, UI and UX fixes from the full review. **Next task:** L-6.

## Round L — UI and UX fixes

- [ ] L-6 The + on the Feeds tab offers "Empty feed" and "From a folder…".
- [ ] L-7 Rule editor: condition first, AI meaning below behind a switch; term options as labelled chips; rows keep their own text after a term is removed; switching Builder and Text never strands the user; leaving with changes asks; the test shows progress and how many posts and channels it checked.
- [ ] L-8 A tap on the channel name or photo of a post in a feed opens the channel's info.
- [ ] L-9 Notifications settings: background watching and sounds apply at once; a picked sound shows its name; a warning row when Android blocks the app's notifications.
- [ ] L-10 Privacy and storage: app-lock settings ask for the PIN first, the lock timeout defaults to one hour; clearing the cache asks first; accounts show their names; sync says when it last synced with the day.
- [ ] L-11 Read aloud: voices listed by language name, only languages with a chosen voice, an "Add language" picker; the preview uses one speaker and stops when the screen closes.
- [ ] L-12 Timeline: reactions change at once; the post text size multiplies the phone's text size; the button to the newest posts stays above the gesture bar; the calendar keeps the search open when cancelled.
- [ ] L-13 Media: the audio bar hides under the full-screen viewer; the viewer shows the photo the timeline already has while the full one loads; the mini player returns to the viewer with caption and actions; voice and music seek once when the finger lifts; the "N of M" counter only for one post's album; a round video plays in its circle.
- [ ] L-14 Login: the code screen can change the number.

## Phase 4 — Extras

- [ ] P4-3 AI-generated podcast from a feed.
- [ ] P4-4 Optional cloud voices for read-aloud.
