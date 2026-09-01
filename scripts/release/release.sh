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
# Redistributing the bundled packages without their licenses would breach
# the MIT/BSD/Apache terms they are shipped under.
if [[ ! -f "$FROZEN/THIRD-PARTY-LICENSES.txt" ]]; then
    echo "error: THIRD-PARTY-LICENSES.txt missing — re-run scripts/freeze-markitdown/build.sh" >&2
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

sign() {
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$1"
}

notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$2"
}

echo "==> Signing every Mach-O of the frozen bundle (dylibs, .so, executables)"
# PyInstaller produces hundreds of dylibs; notarization requires each one
# to be signed. Sign inside-out: nested code first, main executable last.
find "$APP/Contents/Resources/markitdown-bin" -type f -print0 |
    while IFS= read -r -d '' f; do
        case "$f" in
            *.dylib|*.so) sign "$f" ;;
            *) file -b "$f" | grep -q "Mach-O" && sign "$f" || true ;;
        esac
    done

echo "==> Signing the app"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

echo "==> Verifying signature"
codesign --verify --strict --deep --verbose=2 "$APP"

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    echo "==> Notarizing"
    ditto -c -k --keepParent "$APP" "$DIST/mdNotch.zip"
    notarize "$DIST/mdNotch.zip" "$APP"

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
    notarize "$DIST/mdNotch.dmg" "$DIST/mdNotch.dmg"
fi

echo "==> Done: $DIST/mdNotch.dmg"
