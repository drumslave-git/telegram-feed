# telegram-feed — Plan

Open work only. A task leaves this file in the commit that finishes it; `git log` records finished work.

Legend: `[ ]` not started, `[~]` in progress (name the branch).

**Current phase:** Phase 4, extras. **Next task:** N-33.

## Fake Telegram and UI tests

- [~] N-33 (main) `packages/fake_telegram`: one scripted `TelegramGateway` for every test. The widget tests' `ChannelsGateway` / `TimelineGateway` and fixture helpers move there; `FakeTelegram` adds a scripted login, channels with photos and folders, histories with every kind of post, sample media served from a directory, a discussion thread, and a post that arrives every 30 s.
- [ ] N-34 Fake build: `--dart-define=TG_FAKE=true` puts `FakeTelegram` into the core isolate (app and service alike); the sample media under `app/assets/fake/` is copied to the support directory at start. The integration test runs against it.
- [ ] N-35 Maestro flows in `app/maestro/` against the fake build: login, home and folders, feed reading and post menu, channel info, search, media viewer and video, feed editor and filters, rules and the pause switch, a rule firing into a notification, every settings screen. `tool/maestro.sh` runs them locally; `ci.yml` runs them on an emulator.

## Phase 4 — Extras

- [ ] P4-3 AI-generated podcast from a feed.
- [ ] P4-4 Optional cloud voices for read-aloud.
