# Spike P0-2: core isolate under the foreground service

Date: 2026-09-17. Branch: `spike/core-isolate-service` (extends the P0-1 app in `spikes/tdlib_ffi`).

## Outcome

**Met.** On the x86_64 emulator (Android 16, API 36):

- `flutter_foreground_task` starts a foreground service; its task handler spawns the **core isolate**,
  which opens TDLib (reusing the P0-1 session, `authorizationStateReady` 60 ms after spawn) and
  registers a `SendPort` with `IsolateNameServer` under `tf.core`.
- The UI engine finds that port and subscribes; log lines and commands flow both ways across the
  two Flutter engines.
- `finishAndRemoveTask()` kills the activity (0 activity records). The process, the service
  (`isForeground=true`) and the TDLib connection survive; heartbeats continue every 30 s.
- With no activity, incoming channel posts (`updateNewMessage`) produce a local notification
  (`dumpsys notification` shows them) and a `flutter_tts` utterance.
- With the screen off (`mWakefulness=Asleep`), TTS still runs to completion: `tts: start` at
  17:51:31.7, `tts: completion` at 17:51:42.3 for a 160-character post.

## Findings that change the architecture

1. **Plugins with platform-to-Dart callbacks cannot live in the core isolate.** `FlutterTts()` in
   the spawned isolate fails (no binding, and `BackgroundIsolateBinaryMessenger` throws
   `UnsupportedError` for `setMessageHandler`: "Messages from the host platform always go to the
   root isolate"). `flutter_local_notifications.initialize` has the same constraint. So the service
   engine's root isolate (the `TaskHandler`) hosts those plugins, and the core isolate sends it
   `{'type': 'notify' | 'speak', ...}` over a port. Plain method-channel calls without callbacks
   (e.g. `path_provider`) do work from the core isolate with `BackgroundIsolateBinaryMessenger`.
   Consequence: `Notifier` and `TtsService` in `core` are thin proxies; the real plugin calls live in
   the service host. Keeping the core in a separate isolate still pays off: TDLib parsing and rule
   evaluation never block the host isolate's plugin callbacks, and the core has no plugin imports.
2. **Service type is `specialUse`, not `dataSync`.** Android 15+ caps `dataSync` foreground services
   at 6 hours per day, which kills an always-on watcher. `specialUse` has no cap but needs
   `FOREGROUND_SERVICE_SPECIAL_USE` and a `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` explanation for Play
   review. Verified: `dumpsys activity services` shows `types=0x40000000` (specialUse).
3. **The plugin does not declare the service.** The app manifest must declare
   `com.pravera.flutter_foreground_task.service.ForegroundService` with the type and the property.
4. `flutter_tts.speak` flushes the previous utterance (`tts: cancel` when two posts arrive within a
   second). The FIFO queue in section 7 of ARCHITECTURE.md is required, not optional; `awaitSpeakCompletion(true)`
   plus a Dart-side queue in the host isolate is the simplest form.
5. `flutter_local_notifications` 22 needs core library desugaring (`isCoreLibraryDesugaringEnabled`
   plus `desugar_jdk_libs:2.1.4`). `flutter_tts` 4.2.5 still applies the Kotlin Gradle plugin,
   which Flutter 3.47 warns will stop building in a future release; watch for an update or replace it.
6. Kotlin incremental compilation produced a stale-cache failure once on Windows; the spike sets
   `kotlin.incremental=false` in `gradle.properties`.

## Layout

```
lib/main.dart           UI: starts/stops the service, finds tf.core, sends commands, shows log
lib/service.dart        startCallback + CoreHostHandler: spawns the core, hosts notifications + TTS
lib/core_isolate.dart   coreMain: TDLib, IsolateNameServer registration, command loop, heartbeat
lib/account.dart        Account (auth state machine, chats, sendMessage) shared with P0-1
lib/td_json.dart        dart:ffi binding (P0-1)
MainActivity.kt         MethodChannel tf/spike: finishAndRemoveTask (simulates swipe-away)
```

Test sequence used: `adb shell input tap` on Start service, tap Kill activity, `dumpsys activity
activities | grep MainActivity` = 0, `pidof` unchanged, wait for `updateNewMessage`, `dumpsys
notification`, `input keyevent KEYCODE_SLEEP`, wait for `tts: completion` in logcat.

## Run

```bash
cd spikes/tdlib_ffi
flutter build apk --debug --target-platform android-x64 --dart-define=TG_API_ID=... --dart-define=TG_API_HASH=... --dart-define=TG_TEST_DC=false
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell pm grant dev.telegramfeed.tdlib_ffi_spike android.permission.POST_NOTIFICATIONS
adb logcat -s flutter:I | grep -E 'HOST|CORE'
```

The service repeat event (every 60 s) asks the core to send a message to Saved Messages, so a
notification and an utterance are produced even when no channel posts.
