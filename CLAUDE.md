# telegram-feed — instructions for Claude sessions

Custom Telegram client (Flutter + TDLib) for combining channels into feeds, keyword-rule notifications, and read-aloud. Open source, GPL-3.0.

## Session start (mandatory)

1. Read `docs/PLAN.md`. Find the **Current phase** and **Next task** lines and any `[~]` tasks.
2. Run `git log --oneline -20` to see what the last sessions did.
3. Only then start work, on the task the user names or on **Next task** if they did not name one.

## Session end (mandatory)

1. Update `docs/PLAN.md`: remove the finished task, add new ones, update **Current phase** and **Next task**. PLAN.md holds open work only.
2. Commit with a conventional message (`feat:`, `fix:`, `docs:`, `chore:`, `spike:`), one commit per task. Include the task id, e.g. `feat(P1-8): feeds list screen`.
3. Never leave work uncommitted at the end of a session.

## Rules

- Decisions are asked, never deferred. If something is undecided, ask the user with the question tool right away. Do not write "open question", "TBD", or "decide later" anywhere.
- Emulator only. Never propose or attempt running on the user's personal phone. Android emulator with an x86_64 image; TDLib binaries must include x86_64.
- Telegram login on the emulator uses a spare real account on the production DC, never the user's main account. Telegram's test-DC test numbers are dead (see `docs/ARCHITECTURE.md` section 11). The user types the phone number and SMS code into the emulator; Claude never enters them.
- `api_id` / `api_hash` are never committed. They come from `--dart-define=TG_API_ID` and `--dart-define=TG_API_HASH`.
- Spec and architecture live in `docs/SPEC.md` and `docs/ARCHITECTURE.md` and describe the app as it is now. When a decision changes, update SPEC.md's decision table and the relevant sections of both files in the same commit.
- Docs and READMEs hold clear factual statements only: no history, dates, task ids, "founder decision" notes, verification narratives or reasoning trails. `git log` is the history.
- Spikes go on `spike/<name>` branches. Their lasting findings go into `docs/ARCHITECTURE.md`.
- Android only. iOS and web are dropped (web was built in P3-4 and dropped on 2026-09-17; the code is in history at 87e10f3).
