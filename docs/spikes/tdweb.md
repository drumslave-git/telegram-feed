# Spike P0-4: tdweb in Flutter web

Date: 2026-09-17. Branch: `spike/tdweb` (`spikes/tdweb` Flutter web app, `tool/tdweb` build, QR-confirm
endpoint added to `spikes/tdlib_ffi`).

## Outcome

**Met. Web stays on tdweb; no GramJS gateway.** From a Flutter web build served by a plain static
server (`python -m http.server`, no COOP/COEP headers) in the desktop browser:

| Step | Result |
|---|---|
| `TdClient` created, first TDLib response (`getOption version` = 1.8.67) | 328 ms after page start |
| `setTdlibParameters` to `authorizationStateWaitPhoneNumber` | 80 ms |
| `requestQrCodeAuthentication` to QR link | 1.7 s |
| QR link confirmed by the emulator's logged-in client (`confirmQrCodeAuthentication`), web reaches `authorizationStateReady` | 0.5 s after confirmation |
| `loadChats` + `getChats(50)` | 953 ms (network) |
| `getChatHistory(limit 30)` on a channel: network, then `only_local` twice | 6 ms, 2 ms, 2 ms |
| Live `updateNewMessage` from a channel | received within 1 s of login, and again 4 s later |

The TDLib database lives in IndexedDB (`tdweb_spike` plus `/tdweb_spike/dbfs`); a reload reuses it.

## Findings

1. **The published npm package is unusable.** `tdweb@1.8.0` (December 2021) is the latest on npm.
   It loads and emits updates, but never resolves `send()` promises (verified with a fresh
   `useDatabase: false` instance: `getOption` timed out after 8 s), and its API layer is four years
   old. TDLib's `example/web/tdweb/package.json` at master already says 1.8.67, it is just not
   published.
2. **Building tdweb from source is routine.** `tool/tdweb/Dockerfile` uses the official
   `emscripten/emsdk:3.1.1` image and TDLib's own `example/web` scripts; 8 minutes on 24 cores.
   Output: `tdweb.js` (93 KB), two worker chunks (390 KB), `td_wasm.wasm` (14.4 MB, wasm only,
   no asm.js fallback). P1-4's CI job should build this alongside `libtdjson.so` from the same
   pinned commit so both platforms speak the same TDLib version.
3. **No shared memory, no COOP/COEP.** The 1.8.67 build is single-threaded WebAssembly in a Web
   Worker; the "shared-memory build needs COOP/COEP" note in ARCHITECTURE.md was wrong and is
   removed. Any static host works.
4. **Serving layout.** webpack's public path is `/`, so the worker chunks and the `.wasm` must be
   served from the site root; `tdweb.js` itself can live anywhere. In the spike they are copied
   into `web/` (git-ignored) so `flutter build web` ships them.
5. **Interop.** `dart:js_interop` with a 15-line JS glue (`tdCreate`, `tdSend`) that passes JSON
   strings across the boundary was enough. Phase 3 can pass `JSObject`s directly, but the string
   form is simple and the generated `tdlib_bindings` types (P1-2) serialize to JSON anyway, so
   `TdwebGateway` and `TdlibFfiGateway` can share one JSON codec.
6. **QR login works as the second-device flow.** `requestQrCodeAuthentication` on web plus
   `confirmQrCodeAuthentication` on an already-logged-in client is a clean way to log a new
   platform in without an SMS; the product can offer "log in with QR from the phone app" too.
7. The web session created by the spike shows up as device "Web spike" on the spare account;
   terminate it from the emulator app or a Telegram client when no longer needed.

## Run

```bash
docker build --build-arg COMMIT_HASH=d1085f9cebc5a62379991ae1652673954f229c1f --output build/tdweb-out -f tool/tdweb/Dockerfile tool/tdweb
cd spikes/tdweb
cp ../../build/tdweb-out/tdweb/dist/tdweb.js web/tdweb/ && cp ../../build/tdweb-out/tdweb/dist/*.worker.js ../../build/tdweb-out/tdweb/dist/*.wasm web/
flutter build web --dart-define=TG_API_ID=... --dart-define=TG_API_HASH=...
python -m http.server 8090 --bind 127.0.0.1 --directory build/web
# emulator side: spikes/tdlib_ffi build with TG_TEST_DC=false, logged in, then
adb forward tcp:8765 tcp:8765
```

Open http://127.0.0.1:8090/. The page requests a QR login and POSTs the link to
`QR_CONFIRM_URL` (default `http://localhost:8765/confirm-qr`, served by the emulator app), then
lists chats and fetches history. Log lines are on the page and in the console (`SPIKE ...`).
