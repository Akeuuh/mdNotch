# mdNotch

macOS app living under the notch: drag documents onto the top of the screen,
they're converted to Markdown — copied to the clipboard and saved as `.md`
files. Offline, zero dependencies to install. See `SPEC.md` and `PRD.md`.

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
