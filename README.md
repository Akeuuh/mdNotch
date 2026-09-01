# mdNotch

macOS app living under the notch: drag documents onto the top of the screen,
they're converted to Markdown — copied to the clipboard and saved as `.md`
files. Offline, zero dependencies to install. See `SPEC.md` and `PRD.md`.

The app embeds a frozen [markitdown](https://github.com/microsoft/markitdown)
binary (~179 MB) — the accepted cost of requiring no Python on the user's
machine (SPEC.md §1).

## Building

```bash
brew install xcodegen uv

# 1. Freeze the markitdown converter (once)
scripts/freeze-markitdown/build.sh

# 2. Generate the Xcode project and build
xcodegen generate
xcodebuild -project mdNotch.xcodeproj -scheme mdNotch -configuration Debug build
```

## Tests

```bash
# Fast unit tests (ConversionPipeline seam, fake converter)
cd Core && swift test

# Slow integration suite against the real frozen binary
cd Core && MDNOTCH_INTEGRATION=1 swift test --filter MdNotchIntegrationTests
```

## Release

Signed, notarized DMG: see `scripts/release/README.md`.

## Licensing

mdNotch itself is MIT (see `LICENSE`).

The app embeds a frozen build of [markitdown](https://github.com/microsoft/markitdown)
(MIT) and its dependencies — 38 packages, all under permissive terms (MIT,
BSD, Apache 2.0, PSF, MPL 2.0 for certifi). No GPL or LGPL code is
redistributed: PyInstaller is a build tool, and only its bootloader ships,
under the Bootloader Exception that explicitly permits embedding in an
application under any license.

`scripts/freeze-markitdown/gen_licenses.py` collects every bundled package's
license into `THIRD-PARTY-LICENSES.txt`, which the freeze build writes into
the frozen bundle so it ships inside the `.app`. The release script refuses
to build without it.
