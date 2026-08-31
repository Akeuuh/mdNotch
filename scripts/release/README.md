# Release

Produces a signed, notarized `mdNotch.dmg` (arm64, macOS 14+). A user
downloads the DMG, drags the app into Applications, and opens it without a
Gatekeeper warning — no Python, Homebrew or terminal required.

## One-time setup

1. **Developer ID Application certificate** in the login keychain
   (Xcode → Settings → Accounts → Manage Certificates, or developer.apple.com).
   Find its exact name with:

   ```bash
   security find-identity -v -p codesigning
   ```

2. **Notarization credentials** stored as a keychain profile (uses an
   app-specific password from appleid.apple.com):

   ```bash
   xcrun notarytool store-credentials mdnotch-notary \
       --apple-id you@example.com --team-id TEAMID
   ```

## Building a release

```bash
# 1. Freeze the converter (once per markitdown upgrade)
scripts/freeze-markitdown/build.sh

# 2. Sign + notarize + DMG
export DEVELOPER_ID_APP="Developer ID Application: Jane Doe (TEAMID)"
export NOTARY_PROFILE="mdnotch-notary"
scripts/release/release.sh
```

Output: `dist/release/mdNotch.dmg` (with the standard Applications link).

`./release.sh --skip-notarize` runs everything except notarization and
stapling — useful for checking the build and signing steps locally.

## What the script does

1. Release build (arm64, hardened runtime), unsigned.
2. Signs **every** Mach-O of the frozen PyInstaller bundle (hundreds of
   dylibs/.so plus embedded executables) with the Developer ID identity,
   hardened runtime, secure timestamp and the entitlements in
   `entitlements.plist` (`allow-unsigned-executable-memory` and
   `disable-library-validation`, required by the frozen Python runtime).
   Notarization rejects the app if any of them is unsigned.
3. Signs the app bundle, verifies with `codesign --verify --strict --deep`.
4. Submits to Apple with `notarytool`, waits, staples the ticket.
5. Checks `spctl --assess` passes.
6. Builds the DMG, notarizes and staples it too.
