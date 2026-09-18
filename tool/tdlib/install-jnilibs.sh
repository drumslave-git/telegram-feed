#!/usr/bin/env bash
# Unpacks tdlib.zip (from the Docker build) into an Android app's jniLibs folder.
#   tool/tdlib/install-jnilibs.sh build/tdlib-out/tdlib.zip spikes/tdlib_ffi/android/app/src/main/jniLibs
set -euo pipefail
ZIP=${1:?tdlib.zip path}
DEST=${2:?jniLibs dir}
TMP=$(mktemp -d)
unzip -qo "$ZIP" -d "$TMP"
for abi in "$TMP"/tdlib/libs/*/ ; do
  name=$(basename "$abi")
  mkdir -p "$DEST/$name"
  cp "$abi/libtdjson.so" "$DEST/$name/libtdjson.so"
  echo "$name: $(du -h "$DEST/$name/libtdjson.so" | cut -f1)"
done
rm -rf "$TMP"
