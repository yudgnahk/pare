#!/usr/bin/env bash
# release.sh — build, sign, notarize, and package Pare for distribution.
#
# Prerequisites:
#   - Xcode command-line tools installed
#   - A "Developer ID Application" certificate in your keychain
#   - An Apple ID app-specific password for notarytool
#     (generate at https://appleid.apple.com → App-Specific Passwords)
#
# Required environment variables (set in your shell or a .env file):
#   CERT_NAME      — exact name of your Developer ID cert in Keychain
#                    e.g. "Developer ID Application: Jane Smith (ABCD1234EF)"
#   APPLE_ID       — your Apple ID email
#   NOTARY_PASSWORD — app-specific password for notarytool
#   TEAM_ID        — your 10-character Apple Developer Team ID
#
# Usage:
#   export CERT_NAME="Developer ID Application: ..."
#   export APPLE_ID="you@example.com"
#   export NOTARY_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#   export TEAM_ID="ABCD1234EF"
#   bash scripts/release.sh
#
# Or pass VERSION to override (default: read from AppInfo.plist):
#   VERSION=1.0.1 bash scripts/release.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
BUILD_DIR="$REPO_ROOT/.build"
DIST_DIR="$REPO_ROOT/dist"

APP_NAME="Pare"
BUNDLE_ID="com.yudgnahk.pare"
ENTITLEMENTS="$SCRIPTS_DIR/PareApp.entitlements"
INFO_PLIST="$SCRIPTS_DIR/AppInfo.plist"

VERSION="${VERSION:-$(defaults read "$INFO_PLIST" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(defaults read "$INFO_PLIST" CFBundleVersion 2>/dev/null || echo "1")}"

APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

# ---------------------------------------------------------------------------
# Validate required env vars
# ---------------------------------------------------------------------------

die() { echo "❌  $*" >&2; exit 1; }
need_env() { [[ -n "${!1:-}" ]] || die "Required env var $1 is not set. See scripts/release.sh header for instructions."; }

need_env CERT_NAME
need_env APPLE_ID
need_env NOTARY_PASSWORD
need_env TEAM_ID

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

echo "▶  Pare $VERSION (build $BUILD_NUMBER) — starting release build"
echo "   Certificate : $CERT_NAME"
echo "   Team ID     : $TEAM_ID"
echo "   Output      : $DIST_DIR"
echo ""

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# 1. Build universal binary (arm64 + x86_64)
# ---------------------------------------------------------------------------

echo "▶  [1/7] Building release binaries…"

swift build -c release --arch arm64
swift build -c release --arch x86_64

echo "   Combining architectures with lipo…"
lipo -create \
    "$BUILD_DIR/arm64-apple-macosx/release/PareApp" \
    "$BUILD_DIR/x86_64-apple-macosx/release/PareApp" \
    -output "$DIST_DIR/PareApp-universal"

echo "   ✓ Universal binary created"

# ---------------------------------------------------------------------------
# 2. Assemble app bundle
# ---------------------------------------------------------------------------

echo ""
echo "▶  [2/7] Assembling app bundle…"

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$DIST_DIR/PareApp-universal" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"

# Copy icon (run scripts/generate-icon.sh first if missing)
if [ -f "$SCRIPTS_DIR/AppIcon.icns" ]; then
    cp "$SCRIPTS_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "   ✓ AppIcon.icns copied"
else
    echo "   ⚠  AppIcon.icns not found — run: bash scripts/generate-icon.sh"
fi

# Update version/build in the bundle's plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER"       "$APP_BUNDLE/Contents/Info.plist"

echo "   ✓ Bundle assembled at $APP_BUNDLE"

# ---------------------------------------------------------------------------
# 3. Code-sign with Hardened Runtime
# ---------------------------------------------------------------------------

echo ""
echo "▶  [3/7] Code-signing with Hardened Runtime…"

codesign \
    --sign "$CERT_NAME" \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    --deep \
    --force \
    "$APP_BUNDLE"

# Verify
codesign --verify --deep --strict "$APP_BUNDLE" && echo "   ✓ Signature verified"

# ---------------------------------------------------------------------------
# 4. Create DMG
# ---------------------------------------------------------------------------

echo ""
echo "▶  [4/7] Creating DMG…"

STAGING=$(mktemp -d)
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

rm -rf "$STAGING"
echo "   ✓ DMG created: $DMG_NAME"

# Sign the DMG itself
codesign \
    --sign "$CERT_NAME" \
    --timestamp \
    "$DMG_PATH"
echo "   ✓ DMG signed"

# ---------------------------------------------------------------------------
# 5. Notarize
# ---------------------------------------------------------------------------

echo ""
echo "▶  [5/7] Submitting to Apple notary service (this can take a few minutes)…"

xcrun notarytool submit "$DMG_PATH" \
    --apple-id     "$APPLE_ID" \
    --password     "$NOTARY_PASSWORD" \
    --team-id      "$TEAM_ID" \
    --wait \
    --timeout 600

echo "   ✓ Notarization approved"

# ---------------------------------------------------------------------------
# 6. Staple
# ---------------------------------------------------------------------------

echo ""
echo "▶  [6/7] Stapling notarization ticket…"
xcrun stapler staple "$DMG_PATH"
echo "   ✓ Stapled"

# ---------------------------------------------------------------------------
# 7. Verify Gatekeeper
# ---------------------------------------------------------------------------

echo ""
echo "▶  [7/7] Verifying Gatekeeper acceptance…"
spctl --assess --type open --context context:primary-signature "$DMG_PATH" && \
    echo "   ✓ Gatekeeper: accepted"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

DMG_SIZE=$(du -sh "$DMG_PATH" | cut -f1)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅  Pare $VERSION release complete"
echo "      $DMG_PATH ($DMG_SIZE)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Next steps:"
echo "  1. Smoke-test on a clean macOS machine (drag to Applications, launch)"
echo "  2. Create a GitHub release tagged v$VERSION"
echo "  3. Upload $DMG_NAME as the release asset"
