#!/bin/zsh

set -euo pipefail

SRCROOT=$(realpath "$1")
TARGET_IPA=$2

WORKSPACE="$SRCROOT/Asspp.xcworkspace"
SCHEME="Asspp"
BUILD_PRODUCT="Asspp.app"

cd "$SRCROOT"
BUILD_DIR="${ASSPP_BUILD_DIR:-$SRCROOT/build}"
DERIVED_DATA="${ASSPP_DERIVED_DATA_DIR:-$BUILD_DIR/DerivedDataApp}"
mkdir -p "$BUILD_DIR" "$(dirname "$TARGET_IPA")"
TARGET_IPA="$(cd "$(dirname "$TARGET_IPA")" && pwd)/$(basename "$TARGET_IPA")"
PACKAGE_ARGS=()
if [[ -n "${ASSPP_SOURCE_PACKAGES_DIR:-}" ]]; then
    PACKAGE_ARGS=(-clonedSourcePackagesDirPath "$ASSPP_SOURCE_PACKAGES_DIR" -disableAutomaticPackageResolution)
fi

# Create a CI config only if one does not exist. Command-line build settings
# disable signing without replacing a developer's personal configuration.
if [[ ! -f "$SRCROOT/Configuration/Developer.xcconfig" ]]; then
cat >"$SRCROOT/Configuration/Developer.xcconfig" <<'EOF'
// CI-generated Developer.xcconfig
// Code signing is completely disabled for CI builds
DEVELOPMENT_TEAM =
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY =
CODE_SIGN_IDENTITY[sdk=macosx*] =
CODE_SIGNING_REQUIRED = NO
CODE_SIGNING_ALLOWED = NO
EOF
fi

xcodebuild -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    "${PACKAGE_ARGS[@]}" \
    -destination 'generic/platform=iOS' \
    build \
    LOCAL_SAP_LIBRARY_DIR="${LOCAL_SAP_LIBRARY_DIR:?Build the local SAP libraries first}" \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED="NO" \
    GCC_GENERATE_DEBUGGING_SYMBOLS=YES STRIP_INSTALLED_PRODUCT=NO \
    COPY_PHASE_STRIP=NO UNSTRIPPED_PRODUCT=NO \
    | xcbeautify

BUILD_PRODUCT_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/$BUILD_PRODUCT"
if [[ ! -d "$BUILD_PRODUCT_PATH" ]]; then
    echo "[-] build product not found"
    exit 1
fi

echo "[+] build product path: $BUILD_PRODUCT_PATH"

echo "[+] packaging..."
PACKAGE_STAGE="$(mktemp -d "$BUILD_DIR/package.XXXXXX")"
trap 'rm -rf "$PACKAGE_STAGE"' EXIT
mkdir -p "$PACKAGE_STAGE/Payload"
ditto "$BUILD_PRODUCT_PATH" "$PACKAGE_STAGE/Payload/$BUILD_PRODUCT"
ditto -c -k --norsrc --keepParent "$PACKAGE_STAGE/Payload" "$PACKAGE_STAGE/Asspp.ipa"
mv "$PACKAGE_STAGE/Asspp.ipa" "$TARGET_IPA"

echo "[+] done"
