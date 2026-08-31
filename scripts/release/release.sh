#!/bin/bash
# mdNotch release build: arm64 app, Developer ID signature on the app and
# every dylib of the frozen PyInstaller bundle, notarization, DMG.
#
# Requirements (see scripts/release/README.md):
#   - Developer ID Application certificate in the keychain
#   - notarytool credentials stored as a keychain profile
#   - the frozen binary built (scripts/freeze-markitdown/build.sh)
#
# Env:
#   DEVELOPER_ID_APP        signing identity, e.g. "Developer ID Application: Jane Doe (TEAMID)"
#   NOTARY_PROFILE          notarytool keychain profile name (xcrun notarytool store-credentials)
#
# Usage:
#   ./release.sh                 # full release: build, sign, notarize, staple, DMG
#   ./release.sh --skip-notarize # everything but notarization/stapling (local checks)

set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root

SKIP_NOTARIZE=0
[[ "${1:-}" == "--skip-notarize" ]] && SKIP_NOTARIZE=1

IDENTITY="${DEVELOPER_ID_APP:-}"
if [[ -z "$IDENTITY" ]]; then
    echo "error: DEVELOPER_ID_APP is not set (e.g. 'Developer ID Application: Jane Doe (TEAMID)')" >&2
    exit 1
fi
if [[ $SKIP_NOTARIZE -eq 0 && -z "${NOTARY_PROFILE:-}" ]]; then
    echo "error: NOTARY_PROFILE is not set (create one with: xcrun notarytool store-credentials)" >&2
    exit 1
fi

FROZEN=scripts/freeze-markitdown/dist/markitdown-bin
if [[ ! -x "$FROZEN/markitdown-bin" ]]; then
    echo "error: frozen binary missing — run scripts/freeze-markitdown/build.sh first" >&2
    exit 1
fi

ENTITLEMENTS=scripts/release/entitlements.plist
DIST=dist/release
rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Building Release (arm64)"
xcodegen generate --quiet
xcodebuild -project mdNotch.xcodeproj -scheme mdNotch -configuration Release \
    -derivedDataPath "$DIST/DerivedData" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build \
    | grep -E "error:|BUILD" || true

APP_SRC="$DIST/DerivedData/Build/Products/Release/mdNotch.app"
[[ -d "$APP_SRC" ]] || { echo "error: build failed, $APP_SRC not found" >&2; exit 1; }
APP="$DIST/mdNotch.app"
ditto "$APP_SRC" "$APP"

echo "==> Signing every Mach-O of the frozen bundle (dylibs, .so, executables)"
# PyInstaller produces hundreds of dylibs; notarization requires each one
# to be signed. Sign inside-out: nested code first, main executable last.
find "$APP/Contents/Resources/markitdown-bin" -type f \
    \( -name "*.dylib" -o -name "*.so" \) -print0 |
    while IFS= read -r -d '' lib; do
        codesign --force --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$lib"
    done
# Any remaining Mach-O executables in the bundle (incl. Python, markitdown-bin).
find "$APP/Contents/Resources/markitdown-bin" -type f ! -name "*.dylib" ! -name "*.so" -print0 |
    while IFS= read -r -d '' f; do
        if file -b "$f" | grep -q "Mach-O"; then
            codesign --force --options runtime --timestamp \
                --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$f"
        fi
    done

echo "==> Signing the app"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

echo "==> Verifying signature"
codesign --verify --strict --deep --verbose=2 "$APP"

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    echo "==> Notarizing"
    ditto -c -k --keepParent "$APP" "$DIST/mdNotch.zip"
    xcrun notarytool submit "$DIST/mdNotch.zip" \
        --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"

    echo "==> Gatekeeper assessment"
    spctl --assess --type execute --verbose "$APP"
else
    echo "==> Skipping notarization (--skip-notarize)"
fi

echo "==> Building DMG"
DMG_ROOT="$DIST/dmg-root"
mkdir -p "$DMG_ROOT"
ditto "$APP" "$DMG_ROOT/mdNotch.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "mdNotch" -srcfolder "$DMG_ROOT" -ov -format UDZO \
    "$DIST/mdNotch.dmg"
if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    xcrun notarytool submit "$DIST/mdNotch.dmg" \
        --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DIST/mdNotch.dmg"
fi

echo "==> Done: $DIST/mdNotch.dmg"
