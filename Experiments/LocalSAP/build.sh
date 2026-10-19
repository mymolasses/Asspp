#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
stage="${ASSPP_SAP_BUILD_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/asspp-sap.XXXXXX")}"
output="${1:?output directory required}"
mkdir -p "$stage" "$output"
stage="$(cd "$stage" && pwd)"
output="$(cd "$output" && pwd)"
fetch_source() {
    local url="$1" revision="$2" directory="$3"
    if [ "$(git -C "$directory" rev-parse HEAD 2>/dev/null || true)" = "$revision" ]; then return; fi
    if [ ! -d "$directory/.git" ]; then
        git init --quiet "$directory"
        git -C "$directory" remote add origin "$url"
    fi
    git -C "$directory" -c http.version=HTTP/1.1 fetch --quiet --depth=1 origin "$revision"
    git -C "$directory" checkout --quiet --detach FETCH_HEAD
}
fetch_source https://github.com/majd/ipatool.git 4484b55d366e177ae6c89758c61588712c572fad "$stage/ipatool"
fetch_source https://github.com/Naville/unicorn.git 53471ef9cf480fab094bf13db3e5d2f9e2c30dc5 "$stage/unicorn"
python3 "$repo/Experiments/LocalSAP/unicorn_ios.py" "$stage/unicorn/CMakeLists.txt"
# Stage only SAP packages: no desktop keychain, CLI or subprocess dependencies.
mkdir -p "$stage/module/internal/sap" "$stage/module/bridge"
mkdir -p "$stage/module/pkg"
cp -R "$stage/ipatool/pkg/http" "$stage/module/pkg/"
cp "$stage/ipatool/go.mod" "$stage/ipatool/go.sum" "$stage/module/"
for entry in "$stage/ipatool/internal/sap/"*; do
    [ "$(basename "$entry")" = unicorn ] && continue
    cp -R "$entry" "$stage/module/internal/sap/"
done
cp "$repo/Experiments/LocalSAP/assets/"*.go "$stage/module/internal/sap/assets/"
patch -d "$stage/module" -p1 < "$repo/Experiments/LocalSAP/assets-cache.patch"
cp "$repo/Experiments/LocalSAP/protocol/protocol.go" "$stage/module/internal/sap/"
cp "$repo/Experiments/LocalSAP/signer/signer_local.go" "$stage/module/internal/sap/"
cp -R "$repo/Experiments/LocalSAP/unicorn" "$stage/module/internal/sap/"
cp "$repo/Experiments/LocalSAP/bridge/"*.go "$stage/module/bridge/"
cp "$repo/Experiments/LocalSAP/machine/"*.go "$stage/module/internal/sap/machine/"
cmake -S "$stage/unicorn" -B "$stage/host" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DUNICORN_BUILD_TESTS=OFF -DUNICORN_ARCH=x86 -DUNICORN_INTERPRETER=ON
cmake --build "$stage/host" --parallel 3
export CGO_ENABLED=1
export CGO_CFLAGS="-I$stage/unicorn/include"
export CGO_LDFLAGS="$stage/host/libunicorn.a -lpthread -lm"
cd "$stage/module"
go test ./internal/sap/machine ./internal/sap/machimage ./internal/sap/cpio -skip '^TestKBSyncIntegration$' -timeout 10m
go test ./bridge ./internal/sap/unicorn
go test ./internal/sap/assets -run '^TestExplicitSandboxCacheDirectory$' -v
# Real Apple setup/signing smoke test with dummy bytes, no Apple ID or password.
go test ./internal/sap -run '^TestSignerIntegration$' -v -timeout 12m
go test ./internal/sap/machine -run '^TestKBSyncIntegration$' -v -timeout 12m
# The fork probes compiler macros directly. A target compiler wrapper keeps
# those probes on arm64 even when cross-compiling from an Intel Mac.
cat > "$stage/ios-clang" <<'COMPILER'
#!/bin/sh
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
exec xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -isysroot "$sdk" "$@"
COMPILER
chmod +x "$stage/ios-clang"
ARCHFLAGS="-arch arm64" cmake -S "$stage/unicorn" -B "$stage/ios-arm64" -DCMAKE_C_COMPILER="$stage/ios-clang" -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DUNICORN_BUILD_TESTS=OFF -DUNICORN_ARCH=x86 -DUNICORN_INTERPRETER=ON
cmake --build "$stage/ios-arm64" --parallel 3
export GOOS=ios GOARCH=arm64
export CC="$(xcrun --sdk iphoneos --find clang)"
export CGO_CFLAGS="-isysroot $(xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -miphoneos-version-min=16.0 -I$stage/unicorn/include"
export CGO_LDFLAGS="-isysroot $(xcrun --sdk iphoneos --show-sdk-path) -arch arm64 -miphoneos-version-min=16.0 $stage/ios-arm64/libunicorn.a"
go build -buildmode=c-archive -o "$output/libasspp-sap.a" ./bridge
cp "$stage/ios-arm64/libunicorn.a" "$output/libunicorn.a"
