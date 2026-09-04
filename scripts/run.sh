#!/bin/bash
# Build and launch mdNotch for development: Debug build, replaces any running
# instance, runs in the foreground so NSLog output lands in this terminal.
# Ctrl-C quits the app.
#
# Usage:
#   scripts/run.sh                    # Debug build, foreground
#   scripts/run.sh --release          # Release configuration instead
#   scripts/run.sh --detach           # launch detached, return to the prompt
#   scripts/run.sh --stub-converter   # fake the frozen binary (see below)
#
# The app bundles the frozen markitdown binary (~179 MB), built once with
# scripts/freeze-markitdown/build.sh. --stub-converter substitutes a
# placeholder so the UI can be exercised without it: conversions then fail
# with "Conversion failed", everything else works.

set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

CONFIGURATION=Debug
DETACH=0
STUB=0
for arg in "$@"; do
    case "$arg" in
        --release) CONFIGURATION=Release ;;
        --detach) DETACH=1 ;;
        --stub-converter) STUB=1 ;;
        *) echo "error: unknown option $arg" >&2; exit 1 ;;
    esac
done

FROZEN=scripts/freeze-markitdown/dist/markitdown-bin
if [[ ! -x "$FROZEN/markitdown-bin" ]]; then
    if [[ $STUB -eq 0 ]]; then
        echo "error: frozen binary missing — run scripts/freeze-markitdown/build.sh," >&2
        echo "       or pass --stub-converter to run without conversion support" >&2
        exit 1
    fi
    echo "==> Stubbing the converter (conversions will fail)"
    mkdir -p "$FROZEN"
    cat > "$FROZEN/markitdown-bin" <<'STUB_EOF'
#!/bin/bash
echo "markitdown error: stub converter, run scripts/freeze-markitdown/build.sh" >&2
exit 1
STUB_EOF
    chmod +x "$FROZEN/markitdown-bin"
fi

DERIVED=build/run

echo "==> Building $CONFIGURATION"
xcodegen generate --quiet
xcodebuild -project mdNotch.xcodeproj -scheme mdNotch -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED" build \
    | grep -E "error:|warning:|BUILD" || true

APP="$DERIVED/Build/Products/$CONFIGURATION/mdNotch.app"
[[ -d "$APP" ]] || { echo "error: build failed, $APP not found" >&2; exit 1; }

# Two instances would fight over the notch, the drop zone and the clipboard
# shortcut — the second registration silently never fires.
if pkill -x mdNotch 2>/dev/null; then
    echo "==> Stopped the running instance"
    # pkill returns before the process is gone; the new one must not race it
    # for the hotkey.
    sleep 1
fi

if [[ $DETACH -eq 1 ]]; then
    open -n "$APP"
    echo "==> Launched $APP (menu bar icon, no Dock icon)"
else
    echo "==> Running $APP — Ctrl-C to quit"
    exec "$APP/Contents/MacOS/mdNotch"
fi
