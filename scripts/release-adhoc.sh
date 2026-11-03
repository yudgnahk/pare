#!/usr/bin/env bash
# release-adhoc.sh — build Pare.app ad-hoc signed, then zip + DMG + SHA256.
#
# For distribution WITHOUT an Apple Developer account: no Developer ID, no
# notarization, no GitHub Release. Recipients must approve the app once in
# System Settings → Privacy & Security. See docs/distribution-adhoc.md.
# The Developer ID flow stays in scripts/release.sh.
#
# Usage:
#   bash scripts/release-adhoc.sh                  # universal arm64 + x86_64
#   ARCHS=arm64 bash scripts/release-adhoc.sh      # single arch (less disk/RAM)
#   VERSION=1.0.1 BUILD_NUMBER=7 bash scripts/release-adhoc.sh
#
# Env: VERSION, BUILD_NUMBER, ARCHS, DIST_DIR, SWIFT_BIN, SKIP_DISK_CHECK, FORCE_BUILD

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist/adhoc}"

APP_NAME="Pare"
EXECUTABLE="PareApp"
RESOURCE_BUNDLE="Pare_PareCore.bundle"
INFO_PLIST="$SCRIPTS_DIR/AppInfo.plist"
MIN_MACOS="13.0"
MIN_FREE_GB=6

SWIFT_BIN="${SWIFT_BIN:-swift}"
ARCHS="${ARCHS:-arm64 x86_64}"

VERSION="${VERSION:-$(defaults read "$INFO_PLIST" CFBundleShortVersionString 2>/dev/null || echo "1.0")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(defaults read "$INFO_PLIST" CFBundleVersion 2>/dev/null || echo "1")}"

APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-adhoc.zip"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-adhoc.dmg"

die() { echo "❌  $*" >&2; exit 1; }

# CLT-only machines: the macOS 27 SDK breaks @State; same pin as the Makefile.
CLT_FALLBACK_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [[ -z "${SDKROOT:-}" && "$(xcode-select -p 2>/dev/null)" == "/Library/Developer/CommandLineTools" \
      && -d "$CLT_FALLBACK_SDK" ]]; then
    export SDKROOT="$CLT_FALLBACK_SDK"
fi

preflight() {
    if [[ -z "${SKIP_DISK_CHECK:-}" ]]; then
        local free_gb
        free_gb=$(df -g /System/Volumes/Data | awk 'NR==2 {print $4}')
        (( free_gb >= MIN_FREE_GB )) || die "Only ${free_gb} GB free on /System/Volumes/Data (need ≥ ${MIN_FREE_GB}). Free space or set ARCHS=arm64."
    fi
    if [[ -z "${FORCE_BUILD:-}" ]] && pgrep -x rustc swift-frontend swift-build >/dev/null; then
        die "Another heavy build is running (rustc/swift-frontend/swift-build). Wait for it, or set FORCE_BUILD=1."
    fi
}

build_arch() {
    local arch="$1"
    echo "   • swift build -c release --arch $arch"
    (cd "$REPO_ROOT" && "$SWIFT_BIN" build -c release --arch "$arch")
}

bin_path() {
    (cd "$REPO_ROOT" && "$SWIFT_BIN" build -c release --arch "$1" --show-bin-path)
}

build_binaries() {
    local slices=() arch dir slice
    for arch in $ARCHS; do
        build_arch "$arch"
        dir="$(bin_path "$arch")"
        [[ -x "$dir/$EXECUTABLE" ]] || die "Missing $dir/$EXECUTABLE after build."
        # Newer toolchains share one bin path across --arch values; copy before the next build overwrites it.
        slice="$DIST_DIR/$EXECUTABLE-$arch"
        cp "$dir/$EXECUTABLE" "$slice"
        [[ "$(lipo -archs "$slice")" == "$arch" ]] || die "Built slice is not $arch (got: $(lipo -archs "$slice"))."
        slices+=("$slice")
        RESOURCE_SRC="${RESOURCE_SRC:-$dir/$RESOURCE_BUNDLE}"
    done
    [[ -d "$RESOURCE_SRC" ]] || die "Missing $RESOURCE_SRC — PareCore resources (app-catalog.json) would be absent."

    if (( ${#slices[@]} > 1 )); then
        lipo -create "${slices[@]}" -output "$DIST_DIR/$EXECUTABLE-universal"
    else
        cp "${slices[0]}" "$DIST_DIR/$EXECUTABLE-universal"
    fi
    rm -f "${slices[@]}"
}

assemble_bundle() {
    local contents="$APP_BUNDLE/Contents"
    mkdir -p "$contents/MacOS" "$contents/Resources"

    cp "$DIST_DIR/$EXECUTABLE-universal" "$contents/MacOS/$EXECUTABLE"
    chmod +x "$contents/MacOS/$EXECUTABLE"
    rm -f "$DIST_DIR/$EXECUTABLE-universal"

    cp "$INFO_PLIST" "$contents/Info.plist"
    local pb=/usr/libexec/PlistBuddy
    "$pb" -c "Set :CFBundleShortVersionString $VERSION" "$contents/Info.plist"
    "$pb" -c "Set :CFBundleVersion $BUILD_NUMBER" "$contents/Info.plist"
    "$pb" -c "Set :LSMinimumSystemVersion $MIN_MACOS" "$contents/Info.plist" 2>/dev/null \
        || "$pb" -c "Add :LSMinimumSystemVersion string $MIN_MACOS" "$contents/Info.plist"

    if [[ ! -f "$SCRIPTS_DIR/AppIcon.icns" || ! -f "$SCRIPTS_DIR/PareLogo.png" ]]; then
        bash "$SCRIPTS_DIR/generate-icon.sh"
    fi
    cp "$SCRIPTS_DIR/AppIcon.icns" "$contents/Resources/AppIcon.icns"
    cp "$SCRIPTS_DIR/PareLogo.png" "$contents/Resources/PareLogo.png"

    # Contents/Resources is where SwiftPM's accessor looks for apps and where codesign seals it.
    cp -R "$RESOURCE_SRC" "$contents/Resources/$RESOURCE_BUNDLE"
}

sign_bundle() {
    codesign --force --sign - "$APP_BUNDLE/Contents/Resources/$RESOURCE_BUNDLE"
    codesign --force --sign - --identifier com.yudgnahk.pare "$APP_BUNDLE"
}

verify_bundle() {
    local contents="$APP_BUNDLE/Contents" archs sig
    codesign --verify --deep --strict "$APP_BUNDLE" || die "codesign verification failed."
    sig=$(codesign -dv "$APP_BUNDLE" 2>&1)
    grep -q "Signature=adhoc" <<<"$sig" || die "Expected an ad-hoc signature, got: $sig"

    archs=$(lipo -archs "$contents/MacOS/$EXECUTABLE")
    for arch in $ARCHS; do
        grep -qw "$arch" <<<"$archs" || die "Executable lacks $arch slice (has: $archs)."
    done

    [[ -f "$contents/Resources/$RESOURCE_BUNDLE/app-catalog.json" ]] \
        || find "$contents/Resources/$RESOURCE_BUNDLE" -name app-catalog.json | grep -q . \
        || die "app-catalog.json missing from $RESOURCE_BUNDLE."
    [[ -f "$contents/Resources/AppIcon.icns" ]] || die "AppIcon.icns missing."
    plutil -lint "$contents/Info.plist" >/dev/null || die "Info.plist invalid."
    [[ "$(defaults read "$contents/Info" CFBundleExecutable)" == "$EXECUTABLE" ]] \
        || die "CFBundleExecutable does not match the binary name."

    echo "   ✓ codesign: adhoc, archs: $archs"
    echo "   ✓ version $VERSION (build $BUILD_NUMBER), resources + icon present"
}

package() {
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    local staging
    staging=$(mktemp -d)
    cp -R "$APP_BUNDLE" "$staging/"
    ln -s /Applications "$staging/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -ov -format UDZO "$DMG_PATH" >/dev/null
    rm -rf "$staging"

    (cd "$DIST_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$DMG_PATH")" > SHA256SUMS)
    (cd "$DIST_DIR" && shasum -a 256 -c SHA256SUMS >/dev/null) || die "SHA256 self-check failed."
}

main() {
    echo "▶  Pare $VERSION (build $BUILD_NUMBER) — ad-hoc build [$ARCHS]"
    preflight
    rm -rf "$DIST_DIR"
    mkdir -p "$DIST_DIR"

    echo "▶  [1/4] Building…";   build_binaries
    echo "▶  [2/4] Assembling…"; assemble_bundle
    echo "▶  [3/4] Signing (ad-hoc) + verifying…"; sign_bundle; verify_bundle
    echo "▶  [4/4] Packaging…";  package

    echo ""
    echo "✅  Ad-hoc build ready in $DIST_DIR (NOT notarized):"
    (cd "$DIST_DIR" && cat SHA256SUMS && du -sh "$(basename "$ZIP_PATH")" "$(basename "$DMG_PATH")")
}

main "$@"
