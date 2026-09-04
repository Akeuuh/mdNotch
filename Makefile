# mdNotch — entry points for the scripts in scripts/. Thin wrappers: every
# script stays usable on its own, with its own flags and its own README.

SHELL := /bin/bash
.DEFAULT_GOAL := help

FROZEN := scripts/freeze-markitdown/dist/markitdown-bin
DMG := dist/release/mdNotch.dmg

.PHONY: help run run-stub run-release test test-integration project build freeze icon dmg dmg-local bump publish release clean

help:
	@echo "Development"
	@echo "  make run              build Debug and launch (logs in this terminal, Ctrl-C quits)"
	@echo "  make run-stub         same, faking the converter (no 179 MB freeze needed)"
	@echo "  make run-release      launch a Release build"
	@echo "  make test             Core unit tests"
	@echo "  make test-integration Core tests against the real frozen binary (slow)"
	@echo "  make project          regenerate mdNotch.xcodeproj"
	@echo "  make build            Debug build, no launch"
	@echo "  make freeze           freeze the markitdown binary (once per upgrade)"
	@echo "  make icon             regenerate App/Resources/AppIcon.icns"
	@echo
	@echo "Release (see scripts/release/README.md for the one-time setup)"
	@echo "  make dmg              signed + notarized DMG from the current tree"
	@echo "  make dmg-local        same without notarization (local check)"
	@echo "  make bump             set the version in project.yml and commit"
	@echo "  make publish          push, tag and create the GitHub release"
	@echo "  make release          bump + dmg + publish, the whole thing"
	@echo "                        VERSION=x.y.z on any of them, or get asked patch/minor/major"
	@echo
	@echo "  make clean            remove build/ and dist/"

# MARK: - Development

run:
	scripts/run.sh

run-stub:
	scripts/run.sh --stub-converter

run-release:
	scripts/run.sh --release

test:
	cd Core && swift test

test-integration:
	cd Core && MDNOTCH_INTEGRATION=1 swift test --filter MdNotchIntegrationTests

project:
	xcodegen generate

build:
	xcodegen generate --quiet
	xcodebuild -project mdNotch.xcodeproj -scheme mdNotch -configuration Debug \
		-derivedDataPath build/run build

freeze:
	scripts/freeze-markitdown/build.sh

# Every size is rendered at its own resolution rather than resampled, so the
# iconset has to go through the generator, not sips.
icon:
	mkdir -p build
	cd scripts/icon && swiftc -parse-as-library gen_icon.swift -o gen_icon
	scripts/icon/gen_icon build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o App/Resources/AppIcon.icns

# MARK: - Release

dmg:
	scripts/release/release.sh

dmg-local:
	scripts/release/release.sh --skip-notarize

bump:
	scripts/release/bump.sh $(VERSION)

publish:
	scripts/release/publish.sh $(VERSION)

# The order matters: the version has to be in project.yml before the DMG is
# built, or the shipped app reports the previous one.
release:
	@[[ -x "$(FROZEN)/markitdown-bin" ]] || { echo "error: frozen binary missing — run make freeze first" >&2; exit 1; }
	$(MAKE) bump VERSION=$(VERSION)
	$(MAKE) dmg
	$(MAKE) publish

clean:
	rm -rf build dist
