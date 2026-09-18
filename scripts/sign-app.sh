#!/bin/bash
# sign-app.sh <app-bundle> — codesign a dev build with a stable identity.
#
# An ad-hoc signature's designated requirement is just the cdhash, so it changes
# on every rebuild and macOS drops the app's Full Disk Access grant with it.
# Signing with a real certificate produces an identifier + anchor requirement
# instead, which survives rebuilds — grant FDA once and it stays.
#
# Falls back to the linker's ad-hoc signature when no identity is available
# (CI, a fresh machine) so the build still runs.
set -euo pipefail

APP=${1:?usage: sign-app.sh <app-bundle>}
SCRIPTS_DIR=$(cd "$(dirname "$0")" && pwd)
ENTITLEMENTS="$SCRIPTS_DIR/PareApp.entitlements"

# Developer ID first (matches release builds), then a local dev certificate.
find_identity() {
	local identities
	identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
	for prefix in "Developer ID Application" "Apple Development"; do
		local hash
		hash=$(printf '%s\n' "$identities" \
			| grep -F "\"$prefix" \
			| head -1 \
			| awk '{print $2}')
		if [ -n "$hash" ]; then
			echo "$hash"
			return 0
		fi
	done
	return 1
}

IDENTITY=${SIGN_IDENTITY:-$(find_identity || true)}
if [ -z "$IDENTITY" ]; then
	cat >&2 <<MSG
note: no code signing identity found — keeping the ad-hoc signature.
      Full Disk Access will have to be re-granted after every rebuild.
MSG
	exit 0
fi

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")

# --identifier pins the requirement to the bundle ID rather than the binary.
if ! codesign --force --sign "$IDENTITY" \
	--identifier "$BUNDLE_ID" \
	--options runtime \
	--entitlements "$ENTITLEMENTS" \
	"$APP" 2>&1; then
	echo "warning: signing failed — restoring an ad-hoc signature so the app still launches." >&2
	codesign --force --sign - "$APP" >/dev/null 2>&1 || true
	exit 0
fi

codesign --verify --strict "$APP"
codesign -d --requirements - "$APP" 2>&1 | grep '^designated' || true
