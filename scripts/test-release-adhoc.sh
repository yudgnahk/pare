#!/usr/bin/env bash
# Exercises release-adhoc.sh against a fake `swift` (tiny clang binaries) — no Swift build.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/fake-swift" <<FAKE
#!/usr/bin/env bash
arch=""; show=0
while [[ \$# -gt 0 ]]; do
    case "\$1" in --arch) arch="\$2"; shift ;; --show-bin-path) show=1 ;; esac
    shift
done
out="$TMP/bin-\$arch"
if (( show )); then echo "\$out"; exit 0; fi
mkdir -p "\$out/Pare_PareCore.bundle/Contents/Resources"
echo 'int main(void){return 0;}' | clang -x c -arch "\$arch" -o "\$out/PareApp" -
printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>x.Pare-PareCore-resources</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>' > "\$out/Pare_PareCore.bundle/Contents/Info.plist"
echo '{"version":1,"entries":[]}' > "\$out/Pare_PareCore.bundle/Contents/Resources/app-catalog.json"
FAKE
chmod +x "$TMP/fake-swift"

SWIFT_BIN="$TMP/fake-swift" DIST_DIR="$TMP/dist" SKIP_DISK_CHECK=1 FORCE_BUILD=1 \
    bash "$REPO_ROOT/scripts/release-adhoc.sh"

for f in Pare.app Pare-1.0-adhoc.zip Pare-1.0-adhoc.dmg SHA256SUMS; do
    [[ -e "$TMP/dist/$f" ]] || { echo "FAIL: missing $f"; exit 1; }
done
echo "PASS"
