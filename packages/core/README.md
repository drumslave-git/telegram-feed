# core

The core isolate and the pure-Dart logic above the gateway (ARCHITECTURE.md sections 1, 5 and 8).

- `CoreServer`: serves a `TelegramGateway` over `SendPort`s to any number of clients and pushes
  auth, post, membership, connection, file-progress and rule-match events. Runs in the core isolate.
- `CoreClient`: the client-side handle. It implements `TelegramGateway`, so screens do not care
  where the core runs. Wire format in `src/protocol.dart` (plain maps, which cross engine boundaries).
- `native_isolate.dart`: `coreIsolateMain` and `spawnCoreIsolate`. The foreground service spawns
  the core, or the UI does when background watching is off. The host registers the returned port
  with `IsolateNameServer` under `corePortName`.
- `FeedTimeline` (merged timeline), `FeedSearch` (merged search and shared media), `FeedFilter`.
- `RuleEngine`: evaluates rules on new posts and emits `MatchEvent`s.
- `SyncSnapshot` and `SyncEngine`: Google Drive sync merge and run.
- `prepareForSpeech`, `SemanticClient`, `telegramTargetOf`, `postLabel`.
