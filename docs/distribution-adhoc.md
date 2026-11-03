# Ad-hoc distribution (no Apple Developer account)

Pare can be packaged without a Developer ID certificate. The result is **ad-hoc signed and NOT notarized**: macOS Gatekeeper blocks the first launch until the user approves it once. The Developer ID + notarization flow stays in `scripts/release.sh` for when an account exists.

## Build

```bash
make release-adhoc                   # universal arm64 + x86_64
ARCHS=arm64 make release-adhoc       # Apple Silicon only (smaller package; see timings below)
VERSION=1.0.1 BUILD_NUMBER=7 make release-adhoc
bash scripts/test-release-adhoc.sh   # packaging logic against a fake swift, no real build
```

Output in `dist/adhoc/` (git-ignored):

| File | Purpose |
|---|---|
| `Pare.app` | ad-hoc signed bundle |
| `Pare-<version>-adhoc.zip` | `ditto` archive (keeps the signature) |
| `Pare-<version>-adhoc.dmg` | drag-to-Applications image |
| `SHA256SUMS` | checksums for the zip and dmg |

The script refuses to start with < 6 GB free on `/System/Volumes/Data` or while `rustc`/`swift-frontend`/`swift-build` is running (override: `SKIP_DISK_CHECK=1`, `FORCE_BUILD=1`). It verifies `codesign --verify --deep --strict`, the `adhoc` signature, the binary's architectures, `Info.plist` version, the icon, and `app-catalog.json` inside the PareCore resource bundle. It does **not** notarize, staple, or create a GitHub Release.

Bundle layout notes:
- `Pare_PareCore.bundle` lives in `Contents/Resources/` (where SwiftPM's accessor looks for apps and where `codesign` seals it).
- `CFBundleExecutable` is `PareApp`, so the binary is `Contents/MacOS/PareApp`.

## Verify a build

```bash
codesign --verify --deep --strict --verbose=2 dist/adhoc/Pare.app
codesign -dv dist/adhoc/Pare.app 2>&1 | grep -E "Signature|Identifier"   # Signature=adhoc
lipo -archs dist/adhoc/Pare.app/Contents/MacOS/PareApp                   # x86_64 arm64
(cd dist/adhoc && shasum -a 256 -c SHA256SUMS)
spctl -a -vv dist/adhoc/Pare.app                                         # Pare.app: rejected
```

`spctl --assess` says **rejected** (exit 3) for an ad-hoc app. That is expected.

Measured on the 2026-10 release branch (Apple Silicon, Command Line Tools only): arm64-only run 1 min 34 s, universal run 1 min 18 s on a warm `.build`; universal zip 6.9 MB, DMG 7.8 MB. The x86_64 slice is build-verified (`lipo`, `codesign`) but was not executed: the test machine has no Rosetta.

## Install (for the person receiving it)

1. Open the `.dmg` and drag **Pare** to **Applications** (or unzip the `.zip` and move `Pare.app` there).
2. Double-click Pare. macOS shows *"Pare can't be opened"* / *"Apple could not verify…"*. Click **Done**.
3. Open **System Settings → Privacy & Security**, scroll to the *Security* section, and click **Open Anyway** next to "Pare was blocked". Authenticate, then click **Open** in the confirmation dialog. This is needed once per installed build.
4. Alternative (terminal): `xattr -dr com.apple.quarantine /Applications/Pare.app`.

## Full Disk Access — re-grant after every update

Pare needs **System Settings → Privacy & Security → Full Disk Access** to read protected Library paths. macOS ties the grant to the app's *designated requirement*. For an ad-hoc signature that requirement is just the code hash:

```
$ codesign -d -r- Pare.app
# designated => cdhash H"913f381b…"            (universal build lists one cdhash per slice)
```

So **any build whose code changed has a new identity and loses the previous grant.** (Rebuilding identical source reproduced the same cdhash in testing, so only a real update triggers this.) After each update:

1. Open Full Disk Access, remove the old **Pare** entry (select it, click **−**).
2. Click **+**, add `/Applications/Pare.app`, and make sure the toggle is on.
3. Quit and reopen Pare.

To clear a stale entry from the terminal instead: `tccutil reset SystemPolicyAllFiles com.yudgnahk.pare`, then grant again as above. This wipes every Full Disk Access grant for that bundle id, including one held by a `make run-app` build (same id, different signature).

Without a fresh grant, scans of protected folders silently return less data and Pare shows its Full Disk Access coaching banner.

## Upgrading to a proper release later

With a Developer ID certificate, use `scripts/release.sh` (see its header for `CERT_NAME`, `APPLE_ID`, `NOTARY_PASSWORD`, `TEAM_ID`). A Developer ID signature keeps a stable identity, so Full Disk Access and the Gatekeeper approval survive updates.
