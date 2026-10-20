#!/bin/bash
# Runs production feature sources with an in-memory test host and synthetic data.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/asspp-features.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Sources/AssppFeatureChecks" "$stage/fixtures"
for source in \
    Asspp/Backend/AppStore/AccountBackupCrypto.swift \
    Asspp/Backend/AppStore/AccountTransfer.swift \
    Asspp/Backend/AppStore/UserAccount.swift \
    Asspp/Backend/AppStore/AppPackage.swift \
    Asspp/Backend/AppStore/AppPackageArchive.swift \
    Asspp/Backend/Downloader/LocalIPA.swift \
    Asspp/Backend/Downloader/Downloads+LocalIPA.swift \
    Asspp/Backend/Downloader/PackageManifest.swift \
    Asspp/Backend/Downloader/PackageState.swift \
    Tests/Features/TestHost.swift \
    Tests/Features/HistoryChecks.swift \
    Tests/Features/FeatureChecks.swift; do
    cp "$repo/$source" "$stage/Sources/AssppFeatureChecks/"
done
cat > "$stage/Package.swift" <<'MANIFEST'
// swift-tools-version: 5.9
import Foundation
import PackageDescription
let package = Package(name: "AssppFeatureChecks", platforms: [.macOS("15.0")], dependencies: [
    .package(path: ProcessInfo.processInfo.environment["ASSPP_VENDOR_PATH"]!),
    .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
], targets: [.executableTarget(name: "AssppFeatureChecks", dependencies: [
    .product(name: "ApplePackage", package: "ApplePackage"),
    .product(name: "ZIPFoundation", package: "ZIPFoundation"),
])])
MANIFEST
"${ASSPP_NODE_BIN:-node}" "$repo/Tests/Features/backup-interop.mjs" prepare "$stage/fixtures"
python3 "$repo/Tests/Features/make_fixtures.py" "$stage/fixtures"
cp "$repo/Asspp.xcworkspace/xcshareddata/swiftpm/Package.resolved" "$stage/Package.resolved"
ASSPP_VENDOR_PATH="$repo/Vendor/ApplePackage" swift run --skip-update --force-resolved-versions --package-path "$stage" --scratch-path "${ASSPP_FEATURE_BUILD_DIR:-$repo/.build/feature-checks}" --jobs 3 AssppFeatureChecks "$stage/fixtures"
"${ASSPP_NODE_BIN:-node}" "$repo/Tests/Features/backup-interop.mjs" verify "$stage/fixtures"
