# Spike P0-3: merged timeline performance

Date: 2026-09-17. Branch: `spike/timeline-perf` (extends the P0-1 app; `lib/timeline.dart`, `lib/perf.dart`).

## Outcome

**Met.** A k-way merge over 50 channels serving 2 010 posts in pages of 30 from TDLib's local
database (`getChatHistory` with `only_local = true`) on the x86_64 emulator, debug build:

| Pass | Pages | Total | p50 | p95 | max (first page) | `getChatHistory` calls |
|---|---|---|---|---|---|---|
| 1 (DB cold after warm-up) | 67 | 453 ms | 2.7 ms | 16.5 ms | 154 ms | 142 |
| 2 (same process, again) | 67 | 355 ms | 2.7 ms | 16.2 ms | 112 ms | 137 |

Only the first page of each pass exceeds 100 ms, because it issues one history request per source
(50 requests) before it can emit anything. Every later page is far below the budget. Process RSS
went from 431 MB after the warm-up to 463 MB after two passes (debug build with JIT, TDLib
holding ~5 000 messages in its cache; not a release number).

Warm-up: 5 037 posts were pulled from the network for 50 channels in 62 s (about 100 posts per
channel, `limit: 100`, one to two requests each) without hitting a flood wait.

## Design notes confirmed

- `FeedTimeline` keeps one cursor per source (`from_message_id` of the oldest loaded message) and
  a small buffer; a page fills empty buffers in parallel (`Future.wait`), then pops the newest
  item across buffers by `(date, chat_id, message_id)`. Album parts (`media_album_id`) collapse
  into the head item.
- `getChatHistory` with `only_local` can return fewer messages than `limit`, and sometimes none
  even when more exist locally; the spike retries up to 3 times per fill and had 5 empty results
  per pass across 50 sources. Phase 1 should treat an empty local result as "fetch from network"
  rather than "exhausted".
- Sending 50 requests at once is fine: TDLib answers them serially in about 2 ms each.

## Recommendations for P1-10

1. Seed the first page from `chat.last_message` (already in memory from `getChat`) so the first
   paint does not wait for 50 history calls; fill buffers in the background.
2. Keep `historyLimit` around 30: larger pages did not matter for latency, and 30 keeps memory
   per source small.
3. Do not persist anything for the timeline; TDLib's database is fast enough (matches
   ARCHITECTURE.md section 5.3).

## Side finding: doze kills a plain background app

Between P0-2 and P0-3 the emulator screen stayed off. The P0-3 app, started without the foreground
service, lost network at 17:55 (`connectionStateConnecting` forever, no updates, all requests
pending) until the screen was woken. The P0-2 run under the foreground service had survived the
same state. This confirms the phase-2 design: without the foreground service there is no Telegram
connection once the device dozes.

## Run

```bash
cd spikes/tdlib_ffi
flutter build apk --debug --target-platform android-x64 --dart-define=TG_API_ID=... --dart-define=TG_API_HASH=... \
  --dart-define=TG_TEST_DC=false --dart-define=SPIKE_AUTORUN=true --dart-define=SPIKE_PERF=true
adb install -r build/app/outputs/flutter-apk/app-debug.apk && adb shell svc power stayon true
adb logcat -s flutter:I | grep perf
```

`PERF_CHANNELS` (default 50) and `PERF_POSTS` (default 2000) are also dart-defines.
