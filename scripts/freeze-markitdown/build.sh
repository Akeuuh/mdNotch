#!/bin/bash
# Freeze microsoft/markitdown into a standalone arm64 binary with PyInstaller.
#
# Output: dist/markitdown-bin/markitdown-bin (onedir bundle).
# Requires: uv (https://docs.astral.sh/uv/). No system Python needed at runtime.
#
# Usage: ./build.sh [--relock]
#   --relock  Re-resolve requirements.in into requirements.lock (upgrades pins).

set -euo pipefail
cd "$(dirname "$0")"

PYTHON_VERSION="3.12"

if ! command -v uv >/dev/null 2>&1; then
    echo "error: uv is required (brew install uv)" >&2
    exit 1
fi

if [[ "${1:-}" == "--relock" || ! -f requirements.lock ]]; then
    echo "==> Resolving requirements.in -> requirements.lock"
    uv pip compile --python-version "$PYTHON_VERSION" requirements.in -o requirements.lock
fi

echo "==> Creating isolated build env (Python $PYTHON_VERSION)"
uv venv --python "$PYTHON_VERSION" .venv --clear
# shellcheck disable=SC1091
source .venv/bin/activate
uv pip sync requirements.lock

echo "==> Freezing with PyInstaller"
rm -rf build dist
pyinstaller --noconfirm markitdown-bin.spec

echo "==> Collecting third-party licenses"
# MIT/BSD/Apache all require the license text to travel with the binary, so
# it ships inside the frozen bundle (and therefore inside the .app).
python gen_licenses.py dist/markitdown-bin/THIRD-PARTY-LICENSES.txt

echo "==> Smoke test: converting sample PDF (network disabled not enforced here;"
echo "    markitdown offline converters make no network calls)"
OUT="$(./dist/markitdown-bin/markitdown-bin sample/sample.pdf)"
if [[ -z "$OUT" ]]; then
    echo "error: smoke test produced empty markdown" >&2
    exit 1
fi
echo "    OK — sample.pdf converted ($(printf '%s' "$OUT" | wc -c | tr -d ' ') bytes of markdown)"

echo "==> Smoke test: failure path (missing file must exit non-zero with stderr message)"
if ./dist/markitdown-bin/markitdown-bin /nonexistent-file.pdf 2>/dev/null; then
    echo "error: expected non-zero exit for missing file" >&2
    exit 1
fi
echo "    OK — non-zero exit on failure"

SIZE="$(du -sh dist/markitdown-bin | cut -f1)"
echo "==> Done. Bundle size: $SIZE"
echo "    Binary: $(pwd)/dist/markitdown-bin/markitdown-bin"
