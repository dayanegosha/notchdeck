#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CURRENT_ARCH=false
for argument in "$@"; do
    case "$argument" in
        --current-arch) CURRENT_ARCH=true ;;
        --help|-h)
            printf 'usage: %s [--current-arch]\n' "$0"
            printf 'builds a universal macOS app by default; --current-arch builds for this Mac.\n'
            exit 0
            ;;
        *) printf 'unknown argument: %s\n' "$argument" >&2; exit 2 ;;
    esac
done

cd "$PROJECT_ROOT"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchdeck-build.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
BUILD_FLAGS=(-c release --scratch-path "$STAGING_DIR/build")
if [[ "$CURRENT_ARCH" == false ]]; then
    BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi

swift build "${BUILD_FLAGS[@]}"
BINARY_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
STAGED_APP="$STAGING_DIR/NotchDeck.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BINARY_DIR/NotchDeck" "$STAGED_APP/Contents/MacOS/NotchDeck"
cp "$PROJECT_ROOT/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
chmod 755 "$STAGED_APP/Contents/MacOS/NotchDeck"

swift "$PROJECT_ROOT/scripts/make-icon.swift" "$STAGING_DIR/AppIcon.iconset"
iconutil -c icns "$STAGING_DIR/AppIcon.iconset" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"
plutil -lint "$STAGED_APP/Contents/Info.plist"
codesign --force --options runtime \
    --entitlements "$PROJECT_ROOT/Resources/NotchDeck.entitlements" \
    --sign "${CODE_SIGN_IDENTITY:--}" "$STAGED_APP"
codesign --verify --strict --deep "$STAGED_APP"

DIST_DIR="$PROJECT_ROOT/dist"
DIST_APP="$DIST_DIR/NotchDeck.app"
ARCHIVE="$DIST_DIR/NotchDeck-macOS.zip"
mkdir -p "$DIST_DIR"
if [[ -e "$DIST_APP" || -L "$DIST_APP" ]]; then
    rm -rf "$DIST_APP"
fi
ditto --norsrc --noextattr "$STAGED_APP" "$DIST_APP"
ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$ARCHIVE"
printf '\n%s\n%s\n' "$DIST_APP" "$ARCHIVE"
