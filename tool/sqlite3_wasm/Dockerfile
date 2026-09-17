# Builds sqlite3.wasm (SQLite compiled for package:sqlite3, which drift uses on the web) from
# the sqlite3.dart sources at a pinned tag, with the same recipe as that project's own CI.
# We do not download the prebuilt release asset (see docs/ARCHITECTURE.md section 10).
#
#   docker build --build-arg TAG=sqlite3-3.6.0 --output build/sqlite3-wasm-out -f tool/sqlite3_wasm/Dockerfile tool/sqlite3_wasm
#
# Output: build/sqlite3-wasm-out/sqlite3.wasm (plus sqlite3.debug.wasm and sqlite3mc.wasm)
FROM dart:stable AS build

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -yq \
      binaryen cmake curl git ca-certificates gnupg \
 && rm -rf /var/lib/apt/lists/*

# Toolchain, as in sqlite3.dart's own CI: clang 21 from apt.llvm.org (the sources need
# builtins newer than the WASI SDK's clang 20) plus the WASI SDK sysroot and wasm32 builtins.
ARG LLVM=21
ARG WASI_SDK=27
RUN curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor -o /usr/share/keyrings/llvm.gpg \
 && . /etc/os-release \
 && echo "deb [signed-by=/usr/share/keyrings/llvm.gpg] http://apt.llvm.org/$VERSION_CODENAME/ llvm-toolchain-$VERSION_CODENAME-$LLVM main" > /etc/apt/sources.list.d/llvm.list \
 && apt-get update && apt-get install -yq "clang-$LLVM" "lld-$LLVM" && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK}/wasi-sdk-${WASI_SDK}.0-x86_64-linux.deb" -o /tmp/wasi-sdk.deb \
 && dpkg -i /tmp/wasi-sdk.deb && rm /tmp/wasi-sdk.deb \
 && cp -r /opt/wasi-sdk/lib/clang/*/lib/* "/usr/lib/llvm-$LLVM/lib/clang/$LLVM/lib/"

ARG TAG=sqlite3-3.6.0
RUN git clone --depth 1 --branch "$TAG" https://github.com/simolus3/sqlite3.dart /src \
 && cd /src && dart pub get

WORKDIR /src/sqlite3_wasm_build
RUN cmake -Dclang="/usr/lib/llvm-$LLVM/bin/clang" -Dwasi_sysroot=/opt/wasi-sdk/share/wasi-sysroot -S src -B build \
 && cmake --build build -t output -j"$(nproc)" \
 && ls -la out

FROM scratch
COPY --from=build /src/sqlite3_wasm_build/out /
