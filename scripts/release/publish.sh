#!/bin/bash
# Publishes a built DMG: pushes main, tags the commit and creates the GitHub
# release with the DMG attached.
#
# Runs last, after scripts/release/bump.sh and scripts/release/release.sh —
# it builds nothing itself, it only ships what is in dist/release.
#
# Usage:
#   scripts/release/publish.sh 0.3.0   # explicit
#   scripts/release/publish.sh         # whatever project.yml says
#
# Env:
#   NOTES=<file>   release notes (default: scripts/release/notes/v<version>.md,
#                  falling back to GitHub's generated notes)
#   DRAFT=1        create the release as a draft
#   YES=1          skip the confirmation prompt (required when not on a tty)

set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    # After a bump, project.yml is the source of truth — and the DMG check
    # below refuses to ship one built against another version anyway.
    VERSION=$(sed -nE 's/.*CFBundleShortVersionString: "(.*)".*/\1/p' project.yml | head -1)
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must look like 0.3.0 (got '$VERSION')" >&2
    exit 1
fi
TAG="v$VERSION"
DMG=dist/release/mdNotch.dmg
APP=dist/release/mdNotch.app

if [[ ! -f "$DMG" ]]; then
    echo "error: $DMG not found — run scripts/release/release.sh first" >&2
    exit 1
fi

# A DMG built before the version bump would ship the wrong number, and the
# only place that shows up is the About panel of an app already in the wild.
BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "")
if [[ "$BUILT_VERSION" != "$VERSION" ]]; then
    echo "error: the built app says version '$BUILT_VERSION', not '$VERSION' — rebuild it" >&2
    exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "main" && "${ALLOW_BRANCH:-0}" != "1" ]]; then
    echo "error: on branch '$BRANCH', releases are cut from main (ALLOW_BRANCH=1 to override)" >&2
    exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "error: working tree has uncommitted changes — the tag would not describe what shipped" >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "error: tag $TAG already exists locally" >&2
    exit 1
fi
if git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
    echo "error: tag $TAG already exists on the remote" >&2
    exit 1
fi

NOTES_FILE="${NOTES:-scripts/release/notes/$TAG.md}"
NOTES_ARGS=(--generate-notes)
if [[ -f "$NOTES_FILE" ]]; then
    NOTES_ARGS=(--notes-file "$NOTES_FILE")
else
    echo "==> No notes file at $NOTES_FILE, falling back to generated notes"
fi
[[ "${DRAFT:-0}" == "1" ]] && NOTES_ARGS+=(--draft)

echo "==> About to publish $TAG from $(git rev-parse --short HEAD) on $BRANCH"
echo "    DMG:   $DMG ($(du -h "$DMG" | cut -f1))"
echo "    Notes: ${NOTES_ARGS[*]}"
if [[ "${YES:-0}" != "1" ]]; then
    if [[ ! -t 0 ]]; then
        echo "error: not a tty, re-run with YES=1 to confirm" >&2
        exit 1
    fi
    read -r -p "Publish this release? [y/N] " reply
    [[ "$reply" == "y" || "$reply" == "Y" ]] || { echo "Aborted."; exit 1; }
fi

echo "==> Pushing $BRANCH"
git push origin "$BRANCH"

echo "==> Tagging $TAG"
git tag -a "$TAG" -m "mdNotch $VERSION"
git push origin "$TAG"

echo "==> Creating the GitHub release"
gh release create "$TAG" "$DMG" --title "mdNotch $VERSION" "${NOTES_ARGS[@]}"

echo "==> Done: $(gh release view "$TAG" --json url -q .url)"
