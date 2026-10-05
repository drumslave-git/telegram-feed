# telegram-feed — Plan

Open work only. A task leaves this file in the commit that finishes it; `git log` records finished work.

Legend: `[ ]` not started, `[~]` in progress (name the branch).

**Current phase:** Phase 5 — Push. **Next task:** P5-2.

## Phase 5 — Push

Rules notify through Telegram's push (FCM) instead of a permanent foreground service.

- [ ] P5-2 The foreground service goes: the core always runs in the app's process; the background watching switch, the permanent notification with its Pause and the `flutter_foreground_task` plugin are removed; the battery exemption goes through the app's own channel.
- [ ] P5-3 Push: every logged-in account registers the FCM token with TDLib (`registerDevice`); an FCM message schedules an expedited WorkManager job that starts a headless engine with the core, the alerts and the badge, hands TDLib the push, catches up and ends when nothing is left to do; the app takes such a core over when it opens; Listen on a notification starts a run when nothing runs. The native side is a local plugin (FCM service, worker, token), so every engine has its channel.
- [ ] V-16 Real Telegram: a push from Telegram wakes the app on the emulator and a rule notifies (needs a build on the founder's api_id with FCM credentials uploaded at my.telegram.org, and a Firebase project for the app).

## Hands-on checks

Built and covered by tests; what is listed here has not been used on an emulator yet.

- [ ] V-14 Real Telegram: a second real account notifying while the first is in use (needs a second account logged in on the emulator).
- [ ] V-15 The number on the app's icon on a home screen that shows numbers (Samsung); the emulator's shows none.

## Phase 4 — Extras

- [ ] P4-3 AI-generated podcast from a feed.
- [ ] P4-4 Optional cloud voices for read-aloud.
