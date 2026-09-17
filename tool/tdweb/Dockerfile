# Builds the tdweb npm package (TDLib compiled to WebAssembly) from a pinned TDLib commit,
# using TDLib's own example/web scripts and the emsdk version they require.
#
#   docker build --build-arg COMMIT_HASH=<sha> --output build/tdweb-out -f tool/tdweb/Dockerfile tool/tdweb
#
# Output: build/tdweb-out/tdweb/ (package.json, dist/, README.md)
FROM emscripten/emsdk:3.1.1 AS build

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -yq gperf php-cli && rm -rf /var/lib/apt/lists/*

WORKDIR /home
ARG COMMIT_HASH=master
RUN git clone https://github.com/tdlib/td.git && cd td && git checkout "$COMMIT_HASH"

WORKDIR /home/td/example/web
RUN sed -i 's/emmake make -j 4/emmake make -j$(nproc)/' build-openssl.sh && ./build-openssl.sh
RUN sed -i 's#cmake --build build/generate#cmake --build build/generate --parallel $(nproc)#; s#cmake --build build/wasm --target td_wasm#cmake --build build/wasm --target td_wasm --parallel $(nproc)#' build-tdlib.sh \
 && ./build-tdlib.sh
RUN ./copy-tdlib.sh && ./build-tdweb.sh && ls -la tdweb/dist

FROM scratch
COPY --from=build /home/td/example/web/tdweb /tdweb
