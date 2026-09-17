# TDLib native build

`Dockerfile` builds `libtdjson.so` (JSON interface, static libc++ and OpenSSL) from a pinned
TDLib commit for `arm64-v8a` and `x86_64`. It is TDLib's own `example/android` build wrapped
in Docker with the ABI list reduced.

```bash
docker build --build-arg COMMIT_HASH=<tdlib sha> --output build/tdlib-out -f tool/tdlib/Dockerfile tool/tdlib
tool/tdlib/install-jnilibs.sh build/tdlib-out/tdlib.zip <app>/android/app/src/main/jniLibs
```

`build/tdlib-out/tdlib.zip` contains `tdlib/libs/<abi>/libtdjson.so`; `tdlib-debug.zip` keeps
the unstripped `.so.debug` files. The helper scripts `check-environment.sh`, `fetch-sdk.sh`
and `build-openssl.sh` are verbatim copies from `tdlib/td` `example/android`.
