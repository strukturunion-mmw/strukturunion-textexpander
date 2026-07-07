#!/bin/bash
#
# Generates Resources/AppIcon.icns from a 1024×1024 PNG (Resources/icon-1024.png)
# if one is present. Optional — the app builds and runs without a custom icon.
#
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Resources/icon-1024.png"
if [ ! -f "$SRC" ]; then
  echo "No $SRC found; skipping icon generation."
  exit 0
fi

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
  sips -z $size $size     "$SRC" --out "$ICONSET/icon_${size}x${size}.png"      >/dev/null
  sips -z $((size*2)) $((size*2)) "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "Resources/AppIcon.icns"
echo "Wrote Resources/AppIcon.icns"
