# core

The always-on part of the app (ARCHITECTURE.md sections 1 and 8).

- `CoreServer`: serves a `TelegramGateway` over `SendPort`s to any number of clients; pushes
  auth, post, membership and file-progress events. Runs in the core isolate.
- `CoreClient`: UI-side handle that itself implements `TelegramGateway`, so screens never care
  where the core runs. Wire format in `src/protocol.dart` (plain maps, survive engine boundaries).
- `native_isolate.dart`: `coreIsolateMain` + `spawnCoreIsolate` for native platforms (TDLib over
  FFI). Phase 1 spawns it from the UI; phase 2 spawns it from the foreground service. The host
  registers the returned port with `IsolateNameServer` under `corePortName`.

Later phases add `FeedService`, `RuleEngine`, `TtsService` and `Notifier` proxies here.
