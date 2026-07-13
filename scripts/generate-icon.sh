#!/usr/bin/env bash
# generate-icon.sh — Rasterise scripts/icon.svg → scripts/AppIcon.icns
#
# Uses only macOS built-in tools (sips + iconutil); no Homebrew required.
# Requires macOS 13+ (sips SVG support).
#
# Usage:
#   bash scripts/generate-icon.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SVG="$SCRIPT_DIR/icon.svg"
ICNS="$SCRIPT_DIR/AppIcon.icns"
TMP_DIR=$(mktemp -d)
ICONSET="$TMP_DIR/AppIcon.iconset"

mkdir -p "$ICONSET"

die() { echo "❌  $*" >&2; rm -rf "$TMP_DIR"; exit 1; }

[[ -f "$SVG" ]]         || die "icon.svg not found at $SVG"
command -v sips         >/dev/null || die "sips not found — macOS only"
command -v iconutil     >/dev/null || die "iconutil not found — macOS only"

echo "▶  Rasterising icon.svg at required icon sizes…"

rasterize() {
  local size=$1 out=$2
  sips -s format png -z "$size" "$size" "$SVG" --out "$out" >/dev/null 2>&1 \
    || die "sips failed at ${size}×${size} — requires macOS 13+"
}

rasterize 16   "$ICONSET/icon_16x16.png"
rasterize 32   "$ICONSET/icon_16x16@2x.png"
rasterize 32   "$ICONSET/icon_32x32.png"
rasterize 64   "$ICONSET/icon_32x32@2x.png"
rasterize 128  "$ICONSET/icon_128x128.png"
rasterize 256  "$ICONSET/icon_128x128@2x.png"
rasterize 256  "$ICONSET/icon_256x256.png"
rasterize 512  "$ICONSET/icon_256x256@2x.png"
rasterize 512  "$ICONSET/icon_512x512.png"
rasterize 1024 "$ICONSET/icon_512x512@2x.png"

echo "   ✓ 10 sizes generated"
echo ""
echo "▶  Compiling AppIcon.icns…"
iconutil -c icns "$ICONSET" -o "$ICNS"
rm -rf "$TMP_DIR"

ICNS_SIZE=$(du -sh "$ICNS" | cut -f1)
echo "   ✓ $ICNS ($ICNS_SIZE)"
echo ""
echo "  Run 'make run-app' to launch with the icon."
echo "  Run 'make release' to include it in the distributable."
