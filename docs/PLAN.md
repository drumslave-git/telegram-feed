# telegram-feed — Plan

Open work only. A task leaves this file in the commit that finishes it; `git log` records finished work.

Legend: `[ ]` not started, `[~]` in progress (name the branch).

**Current phase:** Phase 4, extras. **Next task:** N-35.

## Fake Telegram and UI tests

- [ ] N-35 Maestro flows in `app/maestro/` against the fake build: login, home and folders, feed reading and post menu, channel info, search, media viewer and video, feed editor and filters, rules and the pause switch, a rule firing into a notification, every settings screen. `tool/maestro.sh` runs them locally; `ci.yml` runs them on an emulator.

## Phase 4 — Extras

- [ ] P4-3 AI-generated podcast from a feed.
- [ ] P4-4 Optional cloud voices for read-aloud.
