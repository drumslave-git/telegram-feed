# Spike P0-1: TDLib FFI on the Android emulator

Date: 2026-09-17. Branch: `spike/tdlib-ffi` (app under `spikes/tdlib_ffi`, build under `tool/tdlib`).

## Outcome

**Partially met.** Everything up to the network login works from a Flutter app on the x86_64 emulator:
the library builds, loads through `dart:ffi`, the receive loop runs in its own isolate, and the client
connects to both the test and the production datacenters and reaches `authorizationStateWaitCode`.
Logging in, listing chats and receiving `updateNewMessage` are blocked because Telegram has disabled
the test-phone-number shortcut (see "Blocker"). Those three steps need a real account and were not run.

## What was built

- `tool/tdlib/Dockerfile`: TDLib's own `example/android` build (Ubuntu 24.04, NDK 23.2, OpenSSL 1.1.1w
  static, libc++ static, JSON interface) restricted to `arm64-v8a` and `x86_64`. Pinned to TDLib
  commit `d1085f9cebc5a62379991ae1652673954f229c1f` (version 1.8.67, 2026-08-24). TDLib has no git
  tags after `v1.8.0`, so "pinned tag" in the plan means a pinned commit.
- `tool/tdlib/install-jnilibs.sh`: unpacks `tdlib.zip` into an app's `jniLibs`.
- `spikes/tdlib_ffi`: Flutter app. `lib/td_json.dart` binds `td_create_client_id`, `td_send`,
  `td_receive`, `td_execute` via `dart:ffi`; `td_receive` is polled from one background isolate and
  events are demultiplexed by `@client_id`; requests are matched to responses via `@extra`.
  `lib/main.dart` drives the auth state machine, lists chats, and can log in a second account to send
  an incoming message to the first (all via `--dart-define`, nothing hard-coded).

## Measurements

| Item | Value |
|---|---|
| Docker build, both ABIs, 24 cores | 6.5 min (OpenSSL + TDLib), image cache cold |
| `libtdjson.so` size, stripped | x86_64 24 MB, arm64-v8a 21 MB |
| `DynamicLibrary.open` on emulator | 118 to 227 ms |
| Cold start to `connectionStateReady` | about 3 s on test DC and on production DC |
| ELF LOAD alignment | 0x4000 on both ABIs (16 KB page size compatible) |
| Shared deps | only `libc`, `libm`, `libdl`, `libz`, `liblog` |

## Blocker: test accounts no longer exist

Test numbers `99966XYYYY` with code `XXXXX` return `PHONE_CODE_INVALID` on every test DC (tried DC 2
and DC 3 with the code length TDLib reports, 5). The TDLib maintainer stated in
[tdlib/td#3083](https://github.com/tdlib/td/issues/3083) (2026-01-05) that test accounts were disabled
for abuse, a real phone number is now required on the test DC, and the account must first be created
with an official mobile app (iOS debug menu or Android beta). The docs at core.telegram.org/api/auth
are out of date. This affects `ARCHITECTURE.md` section 11, which assumes a test DC login for the
emulator integration test.

The two viable routes, both needing a real phone number that is not the founder's main one:

1. Spare number on the **test DC**: create the account once with the official Android beta app
   (switchable to the test DC), then log in from our app with `use_test_dc = true`. Isolated from real
   data, no risk to a production account, but the test DC has no real channels to read.
2. Spare number on the **production DC**: a second real account that joins some public channels.
   Realistic data for P0-3 and later phases; small risk of the account being limited if it behaves
   like a bot.

The choice was put to the founder on 2026-09-17 (see PLAN.md).

## How to run

```bash
# build libtdjson.so (once)
docker build --build-arg COMMIT_HASH=d1085f9cebc5a62379991ae1652673954f229c1f --output build/tdlib-out -f tool/tdlib/Dockerfile tool/tdlib
tool/tdlib/install-jnilibs.sh build/tdlib-out/tdlib.zip spikes/tdlib_ffi/android/app/src/main/jniLibs

# run on the emulator (manual login through the on-screen fields)
cd spikes/tdlib_ffi
flutter run -d emulator-5554 --dart-define=TG_API_ID=... --dart-define=TG_API_HASH=... --dart-define=TG_TEST_DC=false
```

Defines: `TG_TEST_DC` (default true), `TG_TEST_PHONE` / `TG_TEST_PHONE2` (auto-submit phone; the code
is auto-derived only for `99966` numbers), `SPIKE_AUTORUN` (after login: list chats, send to Saved
Messages, log in account 2 and send to account 1). The spike used TDLib's public example credentials
(`example/cpp/td_example.cpp`) via `--dart-define`; the product needs its own from my.telegram.org.

## Notes for phase 1

- The FFI approach is sound: no platform channel, no Kotlin, one `.so` per ABI in `jniLibs`.
- `td_receive` must be called from a single thread. One isolate for all clients is enough.
- TDLib emits a burst of `updateOption`, `updateUser`, `updateNewChat` and similar updates on start;
  the gateway should route by `@type` early and drop what it does not use.
- Because `getOption version` before `setTdlibParameters` works, the client can be probed cheaply.
- P1-4 should reuse `tool/tdlib/Dockerfile` as the CI job body. Consider NDK 27+ later for a
  16 KB default; the current binaries already have 16 KB LOAD alignment.
- `flutter build apk --debug --target-platform android-x64` plus `adb install` is faster to iterate
  on than `flutter run` when driving the app from scripts; logs arrive on logcat tag `flutter`.
