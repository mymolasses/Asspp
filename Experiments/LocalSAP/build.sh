#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/asspp-sap.XXXXXX")"
output="${1:?output directory required}"
mkdir -p "$output"
git clone --quiet https://github.com/majd/ipatool.git "$stage/ipatool"
git -C "$stage/ipatool" checkout --quiet a9bd16c9a211c556650e206245ff34115c725e12
git clone --quiet https://github.com/Naville/unicorn.git "$stage/unicorn"
git -C "$stage/unicorn" checkout --quiet 53471ef9cf480fab094bf13db3e5d2f9e2c30dc5
# Stage only SAP packages: no desktop keychain, CLI or subprocess dependencies.
mkdir -p "$stage/module/internal/sap" "$stage/module/bridge"
cp "$stage/ipatool/go.mod" "$stage/ipatool/go.sum" "$stage/module/"
for entry in "$stage/ipatool/internal/sap/"*; do
    [ "$(basename "$entry")" = unicorn ] && continue
    cp -R "$entry" "$stage/module/internal/sap/"
done
cp -R "$repo/Experiments/LocalSAP/unicorn" "$stage/module/internal/sap/"
cp "$repo/Experiments/LocalSAP/bridge/main.go" "$stage/module/bridge/"
cmake -S "$stage/unicorn" -B "$stage/host" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DUNICORN_BUILD_TESTS=OFF -DUNICORN_ARCH=x86 -DUNICORN_INTERPRETER=ON
cmake --build "$stage/host" --parallel 3
export CGO_ENABLED=1
export CGO_CFLAGS="-I$stage/unicorn/include"
export CGO_LDFLAGS="$stage/host/libunicorn.a -lpthread -lm"
cd "$stage/module"
go test ./internal/sap/machine ./internal/sap/machimage ./internal/sap/cpio -timeout 10m
# Real Apple setup/signing smoke test with dummy bytes, no Apple ID or password.
go test ./internal/sap -run '^TestSignerIntegration$' -v -timeout 12m
cmake -S "$stage/unicorn" -B "$stage/ios" -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DUNICORN_BUILD_TESTS=OFF -DUNICORN_ARCH=x86 -DUNICORN_INTERPRETER=ON
cmake --build "$stage/ios" --parallel 3
export GOOS=ios GOARCH=arm64
export CC="$(xcrun --sdk iphoneos --find clang)"
export CGO_CFLAGS="-isysroot $(xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -miphoneos-version-min=16.0 -I$stage/unicorn/include"
export CGO_LDFLAGS="-isysroot $(xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -miphoneos-version-min=16.0 $stage/ios/libunicorn.a"
go build -buildmode=c-archive -o "$output/libasspp-sap.a" ./bridge
cp "$stage/ios/libunicorn.a" "$output/libunicorn.a"
