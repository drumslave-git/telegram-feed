# telegram-feed — Plan

Open work only. A task leaves this file in the commit that finishes it; `git log` records finished work.

Legend: `[ ]` not started, `[~]` in progress (name the branch).

**Current phase:** Phase 5 — Push. **Next task:** P5-4.

## Phase 5 — Push

Rules notify through Telegram's push (FCM) instead of a permanent foreground service.

- [ ] P5-4 Muted channels wake the app: TDLib is built with `no_muted` off, so Telegram sends its silent pushes for muted chats; first proven on the emulator.
- [ ] P5-5 Instant rules: a rule gets an "Instant" switch; while any rule has it on, the always-on connection runs (the foreground service with its permanent notification), so its posts notify at once even on muted channels. Push stays for everything else.
- [ ] V-16 Real Telegram: a push from Telegram wakes the closed app on the emulator and a rule notifies. Needs the app's Firebase project (its `google-services.json` in `app/android/app/`), that project's FCM credentials uploaded at my.telegram.org for the founder's `api_id`, and a build on that `api_id`.

## Hands-on checks

Built and covered by tests; what is listed here has not been used on an emulator yet.

- [ ] V-14 Real Telegram: a second real account notifying while the first is in use (needs a second account logged in on the emulator).
- [ ] V-15 The number on the app's icon on a home screen that shows numbers (Samsung); the emulator's shows none.

## Phase 4 — Extras

- [ ] P4-3 AI-generated podcast from a feed.
- [ ] P4-4 Optional cloud voices for read-aloud.
