# telegram-feed — Plan

Open work only. A task leaves this file in the commit that finishes it; `git log` records finished work.

Legend: `[ ]` not started, `[~]` in progress (name the branch).

**Current phase:** Phase 5 — Push. **Next task:** P5-4.

## Phase 5 — Push

Rules notify through Telegram's push (FCM) while the app is closed, and through a connection kept open while a rule is instant.

- [ ] P5-4 Muted channels wake the app: TDLib is built with `no_muted` off, so Telegram sends its silent pushes for muted chats; first proven on the emulator.

## Hands-on checks

Built and covered by tests; what is listed here has not been used on an emulator yet.

- [ ] V-14 Real Telegram: a second real account notifying while the first is in use (needs a second account logged in on the emulator).
- [ ] V-15 The number on the app's icon on a home screen that shows numbers (Samsung); the emulator's shows none.

## Phase 4 — Extras

- [ ] P4-3 AI-generated podcast from a feed.
- [ ] P4-4 Optional cloud voices for read-aloud.
