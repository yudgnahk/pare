# App Manager Feature

Scan all installed macOS apps, sort/filter, multi-select uninstall, detect outdated and duplicate versions.

## Goals

- Show every installed app with size, install date, last-used date
- Multi-select uninstall with complete leftover removal
- Detect apps with available updates (Sparkle + MAS)
- Detect duplicate app installs (same app, multiple versions) and flag older copies
- Highlight Apple SIP-protected apps and skip gracefully

---

## Discovery

Combine three sources to cover all install locations:

```swift
let locations: [URL] = [
    URL(fileURLWithPath: "/Applications"),
    URL(fileURLWithPath: "/System/Applications"),
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
]
```

Use `FileManager.enumerator` at depth 1 per directory; filter for `.app` bundles. Supplement with `NSMetadataQuery` (`kMDItemContentType == 'com.apple.application-bundle'`) to catch apps indexed outside those paths (e.g. Setapp installs in `~/Library/`).

---

## Per-App Metadata

| Field | Source |
|-------|--------|
| Name | `CFBundleDisplayName` / `CFBundleName` from `Info.plist` |
| Bundle ID | `CFBundleIdentifier` |
| Version | `CFBundleShortVersionString` |
| Size | Recursive `FileManager.enumerator` with `totalFileAllocatedSizeKey` (not `kMDItemFSSize` — that's single-file only) |
| Install date | `URLResourceKey.creationDateKey` on the `.app` bundle |
| Last used | `kMDItemLastUsedDate` via `NSMetadataItem` (no FDA required for `/Applications`) |
| MAS app | `kMDItemAppStoreHasReceipt == true` or receipt at `Contents/_MASReceipt/receipt` |
| SIP-protected | Bundle path starts with `/System/` |

Fetch metadata concurrently using `withTaskGroup` — one task per app.

---

## Sorting & Filtering

Default sort: size descending (biggest first). Allow user to switch:

- Size (asc/desc)
- Name (asc/desc)
- Install date (newest/oldest)
- Last used (most/least recent)
- Never used (last-used == nil)

Filter: free-text search on app name; toggle to hide SIP-protected apps; toggle to show only outdated; toggle to show only duplicate versions.

---

## Uninstall

### What to remove

Beyond the `.app` bundle, remove all per-app leftovers keyed by bundle ID (`com.example.appname`):

| Location | Pattern |
|----------|---------|
| `~/Library/Application Support/` | `{bundleID}/` or `{appName}/` |
| `~/Library/Caches/` | `{bundleID}/` |
| `~/Library/Preferences/` | `{bundleID}.plist` and `{bundleID}.*.plist` |
| `~/Library/Logs/` | `{bundleID}/` and `{appName}/` |
| `~/Library/Containers/` | `{bundleID}/` |
| `~/Library/Group Containers/` | `*.{bundleID}/` — **DO NOT delete** (shared across app suite; preview only) |
| `~/Library/WebKit/` | `{bundleID}/` |
| `~/Library/Cookies/` | `{bundleID}.binarycookies` |
| `~/Library/HTTPStorages/` | `{bundleID}/` |
| `~/Library/Saved Application State/` | `{bundleID}.savedState/` |
| `~/Library/LaunchAgents/` | `*{bundleID}*.plist` |
| `/Library/LaunchAgents/` | `*{bundleID}*.plist` |
| `/Library/LaunchDaemons/` | `*{bundleID}*.plist` |
| `~/Library/Application Scripts/` | `{bundleID}/` |
| `~/Library/Biometric Database/` | `{bundleID}.*` |

Always move to Trash (`NSWorkspace.recycle`), never `FileManager.removeItem`.

### Group Containers warning

If `~/Library/Group Containers/` entries are found, show them in a separate "Shared Data" section with a warning: "This data may be used by other apps in the same suite. Remove only if you are uninstalling all related apps." Never auto-select for deletion.

### SIP guard

For apps in `/System/Applications/`, show the app but disable the uninstall action. Tooltip: "System apps cannot be removed (SIP-protected)."

### Homebrew-managed apps

Before trashing the `.app` bundle, check if the app is managed by Homebrew:
```
$(brew --caskroom)/<token>/<version>/  # receipt directory existence
```
If managed: prefer `brew uninstall --zap <cask>` (runs the cask's zap stanza which removes additional leftovers defined by the maintainer). Fall back to manual removal if `brew` is not found.

---

## Stale App Version Detection

Generalises `JetBrainsStaleVersionRule` to every installed app using `CFBundleIdentifier` as the grouping key instead of a directory name prefix.

### Algorithm

1. Collect all `.app` bundles from discovery (see above)
2. For each bundle, read `CFBundleIdentifier` and `CFBundleVersion` from `Info.plist`
3. Group by `CFBundleIdentifier`
4. Any group with more than one entry has duplicate installs
5. Within a group, sort by version (see below) then by `effectiveAgeDate` as tiebreaker
6. Flag every entry below the highest as a stale duplicate candidate

### Version comparison

`CFBundleVersion` is freeform — split on `.` and compare segments numerically left-to-right, falling back to lexicographic when a segment is non-numeric:

```swift
func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
    let aParts = a.split(separator: ".").map { Int($0) ?? -1 }
    let bParts = b.split(separator: ".").map { Int($0) ?? -1 }
    let maxLen = max(aParts.count, bParts.count)
    for i in 0..<maxLen {
        let av = i < aParts.count ? aParts[i] : 0
        let bv = i < bParts.count ? bParts[i] : 0
        if av != bv { return av < bv ? .orderedAscending : .orderedDescending }
    }
    return .orderedSame
}
```

### Risk level

Always `.review` — never `.safe`. Dual-version installs are sometimes intentional (e.g. keeping an older Xcode for a legacy project). The user must explicitly confirm before anything is moved to Trash.

### Edge cases

| Scenario | Handling |
|----------|---------|
| Same bundle ID at `/Applications` and `~/Applications` | Treated as duplicates; flag the older one |
| Beta alongside stable (same bundle ID, e.g. `com.apple.dt.Xcode`) | Grouped together; stable version is typically newer by build number |
| Apps with missing or empty `CFBundleIdentifier` | Fall back to normalised display name (strip trailing version numbers/`beta`/`dev` suffix) |
| Apps with identical `CFBundleVersion` | Neither flagged — no clear winner; show as "duplicate" without recommending removal |
| SIP-protected apps (`/System/Applications/`) | Excluded entirely — can't be removed anyway |

### ScanRule integration

Implemented as `StaleAppVersionRule` in `Sources/PareCore/Rules/`, using `customScan` (same pattern as `JetBrainsStaleVersionRule`) because it needs to compare siblings rather than evaluate files individually. Registered in `RuleCatalog.all` under `.applications` category.

The shared version-comparison logic lives in `FileSystemUtils` so `JetBrainsStaleVersionRule` and `StaleAppVersionRule` both use it.

---

## Outdated Detection

Two channels, run in parallel:

### Sparkle (most third-party apps)

1. Read `SUFeedURL` from `Info.plist`
2. Fetch the appcast XML
3. Parse `<sparkle:version>` (build number) and `<sparkle:shortVersionString>` (display version) from the latest `<item>`
4. Compare with installed `CFBundleVersion`

Skip apps without `SUFeedURL`. Network fetch with 5-second timeout.

### Mac App Store apps

1. Read `CFBundleIdentifier`
2. Check for MAS receipt: `Contents/_MASReceipt/receipt` exists
3. Fetch: `https://itunes.apple.com/lookup?bundleId={ID}&entity=macSoftware&country=us`
4. Parse `results[0].version`
5. Compare with installed `CFBundleShortVersionString`

Rate-limit: batch up to 25 requests at a time to avoid Apple throttling.

### UI

Show a "Updates available" badge count in the section header. Each outdated app shows current vs available version. "Update" button:
- Sparkle apps: open the app (Sparkle checks on launch) or launch the direct download URL from the appcast
- MAS apps: open `macappstore://` deep link to the app's store page
- Homebrew apps: offer `brew upgrade <cask>` via the Homebrew Manager

---

## Architecture

New module: `Sources/PareCore/AppManager/`

```
AppManager/
  AppInventory.swift          # Discovery + metadata fetch
  AppUninstaller.swift        # Leftover scan + Trash logic
  OutdatedChecker.swift       # Sparkle + MAS version check
  Models/
    InstalledApp.swift        # Value type: name, bundleID, version, size, dates, source
    AppLeftover.swift         # Path + category + shared flag
    UpdateInfo.swift          # currentVersion, availableVersion, channel

# Registered in RuleCatalog, not in AppManager/ — lives alongside other rules
Sources/PareCore/Rules/StaleAppVersionRule.swift
```

`AppInventory` is an `actor` (same pattern as `CleanupEngine`).
`InstalledApp` is `Sendable`.

---

## SwiftUI Integration

New tab in `ScanDashboardView` or a separate sheet triggered from the sidebar. Mirrors the existing scan result list pattern:

- `AppManagerViewModel` (`@MainActor ObservableObject`)
- `AppManagerView` with sortable table (`List` + `Table` on macOS 13+)
- `AppUninstallConfirmSheet` for multi-select confirmation with leftover preview

---

## ScanPolicy Integration

Add `isSystemApp(_ url: URL) -> Bool` to `ScanPolicy` to centralize the SIP-path check. Add `isGroupContainer(_ url: URL) -> Bool`. Both used by `AppUninstaller` and any future rules.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Removing shared Group Container data | Never auto-select; show warning with list of sibling apps that also use it |
| Wrong app matched by name (not bundle ID) | Always key by bundle ID; fall back to name only when bundle ID is unavailable |
| Sparkle fetch triggers UI (sheet, modal) | Fetch in background; never launch app during check |
| MAS throttling | Batch ≤25 requests; retry with exponential backoff |
| Homebrew not installed | Guard all `brew` calls; show "Not Homebrew-managed" gracefully |
| `kMDItemLastUsedDate` missing for new apps | Show "Never used" rather than crashing |
| Intentional dual-version installs flagged as stale | Risk level `.review` ensures nothing is auto-deleted; user confirms each removal |
| Apps with identical `CFBundleVersion` | Do not recommend either for removal — surface as informational "duplicate" only |
| Beta/stable sharing the same bundle ID | Treated as duplicates by design; user sees both and chooses which to keep |
