# Builds libtdjson.so for Android from a pinned TDLib commit.
# Based on tdlib/td example/android/Dockerfile, restricted to the ABIs we ship.
#
#   docker build --build-arg COMMIT_HASH=<sha> --output out -f tool/tdlib/Dockerfile tool/tdlib
#
# Output: out/tdlib.zip and out/tdlib-debug.zip (libs/<abi>/libtdjson.so inside).
FROM --platform=linux/amd64 ubuntu:24.04 AS build

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -yq default-jdk g++ git gperf make perl php-cli unzip wget && rm -rf /var/lib/apt/lists/*

WORKDIR /home

ARG ANDROID_NDK_VERSION=23.2.8568313
ARG ABIS="arm64-v8a x86_64"
COPY ./check-environment.sh ./fetch-sdk.sh ./
# The executable bit does not survive every checkout (Windows), so set it here.
RUN chmod +x ./check-environment.sh ./fetch-sdk.sh && ./fetch-sdk.sh SDK "$ANDROID_NDK_VERSION"

ARG OPENSSL_VERSION=OpenSSL_1_1_1w
COPY ./build-openssl.sh ./
RUN chmod +x ./build-openssl.sh
RUN sed -i "s/^for ABI in .* ; do/for ABI in $ABIS ; do/" build-openssl.sh \
 && sed -i 's/make -j4 -s/make -j$(nproc) -s/' build-openssl.sh \
 && ./build-openssl.sh SDK "$ANDROID_NDK_VERSION" openssl "$OPENSSL_VERSION" ""

ARG COMMIT_HASH=master
RUN git clone https://github.com/tdlib/td.git && cd td && git checkout "$COMMIT_HASH"

ARG ANDROID_STL=c++_static
RUN sed -i "s/^for ABI in .* ; do/for ABI in $ABIS ; do/" td/example/android/build-tdlib.sh \
 && td/example/android/build-tdlib.sh SDK "$ANDROID_NDK_VERSION" openssl "$ANDROID_STL" JSON \
 && rm -rf td/example/android/build-*

FROM scratch
COPY --from=build /home/td/example/android/tdlib/tdlib* /
