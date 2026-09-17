# tdweb build (TDLib for the browser)

The npm package `tdweb` is stuck at 1.8.0 (2021) and does not work, so we build it ourselves
from the same pinned TDLib commit as the Android library, using TDLib's own `example/web`
scripts inside the official `emscripten/emsdk:3.1.1` image.

```bash
docker build --build-arg COMMIT_HASH=<tdlib sha> --output build/tdweb-out -f tool/tdweb/Dockerfile tool/tdweb
```

Output `build/tdweb-out/tdweb/dist/`: `tdweb.js`, `<hash>.worker.js`, `1.<hash>.worker.js`,
`<hash>.wasm`. The worker chunks and the `.wasm` must be served from the web root (webpack public
path `/`); `tdweb.js` can be referenced from anywhere. No COOP/COEP headers are needed (single
threaded wasm). See `docs/spikes/tdweb.md`.
