#!/bin/bash
#
# Builds StrukturExpander.app as a distributable, ad-hoc–signed macOS
# application bundle. Run this on a Mac (Apple Silicon or Intel) with the
# Xcode command-line tools installed.
#
# Usage:
#   ./scripts/build.sh            # release build, universal binary, ad-hoc signed
#   CONFIG=debug ./scripts/build.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="StrukturExpander"
BUNDLE_ID="de.strukturunion.StrukturExpander"
CONFIG="${CONFIG:-release}"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "==> Cleaning previous build"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "==> Compiling Swift package ($CONFIG, universal arm64 + x86_64)"
swift build \
  -c "$CONFIG" \
  --arch arm64 --arch x86_64 \
  --disable-sandbox

BIN_PATH="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)"
cp "$BIN_PATH/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "==> Assembling app bundle"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> Code signing (ad-hoc, hardened runtime, with entitlements)"
# Ad-hoc signing (-) lets the app run locally without a Developer ID.
# For distribution to a colleague, replace "-" with your Developer ID identity.
IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --deep \
  --sign "$IDENTITY" \
  --options runtime \
  --entitlements "$ROOT/Resources/StrukturExpander.entitlements" \
  "$APP_DIR"

echo "==> Verifying signature"
codesign --verify --verbose=2 "$APP_DIR" || true

echo ""
echo "Built: $APP_DIR"
echo ""
echo "Next steps:"
echo "  1. Copy $APP_NAME.app to /Applications."
echo "  2. Launch it. Grant Accessibility permission when asked"
echo "     (System Settings → Privacy & Security → Accessibility)."
echo ""
echo "If macOS blocks it as 'from an unidentified developer', run:"
echo "  xattr -dr com.apple.quarantine \"/Applications/$APP_NAME.app\""
