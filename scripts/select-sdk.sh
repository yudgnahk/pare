#!/bin/bash
# Prints an SDKROOT the active Swift toolchain can actually compile SwiftUI
# against, or nothing when the default SDK already works.
#
# macOS 27+ SDKs turned @State into a macro expanded by libSwiftUIMacros.dylib,
# a plugin that ships only inside Xcode.app. On a Command Line Tools-only
# machine every SwiftUI view then fails to compile, so fall back to the newest
# installed SDK where the property wrappers are still plain structs.
set -euo pipefail

PLUGIN_LIB=libSwiftUIMacros.dylib
# The State* macro family is what makes an SDK unbuildable without the plugin;
# @Entry / @Animatable macros exist in older SDKs too and are avoidable.
MACRO_MARKER='type: "State[A-Za-z]*Macro"'

developer_dir=$(xcode-select -p 2>/dev/null || true)
[ -n "$developer_dir" ] || exit 0

toolchain_bin=$(xcrun --find swift-frontend 2>/dev/null || true)
[ -n "$toolchain_bin" ] || exit 0
plugin_dir="$(dirname "$(dirname "$toolchain_bin")")/lib/swift/host/plugins"

# Toolchain ships the plugin — the default SDK is fine.
[ -f "$plugin_dir/$PLUGIN_LIB" ] && exit 0

needs_plugin() {
	local interfaces
	interfaces=$(find "$1/System/Library/Frameworks/SwiftUICore.framework" \
		-name 'arm64e-apple-macos.swiftinterface' 2>/dev/null || true)
	[ -n "$interfaces" ] || return 1
	grep -qE "$MACRO_MARKER" $interfaces 2>/dev/null
}

default_sdk=$(xcrun --show-sdk-path 2>/dev/null || true)
if [ -n "$default_sdk" ] && ! needs_plugin "$default_sdk"; then
	exit 0
fi

for sdk_dir in "$developer_dir/SDKs" "$developer_dir/Platforms/MacOSX.platform/Developer/SDKs"; do
	[ -d "$sdk_dir" ] || continue
	# Newest version first; the unversioned MacOSX.sdk alias is skipped.
	while read -r candidate; do
		[ -d "$candidate" ] || continue
		if ! needs_plugin "$candidate"; then
			echo "$candidate"
			exit 0
		fi
	done < <(ls -d "$sdk_dir"/MacOSX*.sdk 2>/dev/null | grep -E 'MacOSX[0-9]' | sort -Vr)
done

cat >&2 <<MSG
warning: every installed SDK needs $PLUGIN_LIB and this toolchain has none.
         SwiftUI targets will fail to build — install Xcode.app, or set
         SDKROOT to an older SDK by hand.
MSG
exit 0
