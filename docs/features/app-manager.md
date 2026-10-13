# App Manager

Lists installed apps with size, install date and last use; uninstalls with leftovers; checks for
updates. Code: `Sources/PareCore/AppManager/`, `StaleAppVersionRule`.

## Discovery and metadata

- Depth-1 walk of `/Applications`, `/System/Applications` and `~/Applications`, plus an
  `NSMetadataQuery` for app bundles elsewhere (e.g. Setapp).
- Size uses `totalFileAllocatedSizeKey` over the whole bundle (`kMDItemFSSize` is single-file only).
- Last used is `kMDItemLastUsedDate`; missing means "Never". MAS apps have `Contents/_MASReceipt/receipt`.
- Apps under `/System/` are SIP-protected (`ScanPolicy.isSystemApp`): shown, never removable.

## Uninstall leftovers

Everything goes to the Trash (`FileManager.trashItem`). Leftovers are keyed by bundle ID, never by
name alone:

| Location | Pattern |
|---|---|
| `~/Library/Application Support`, `Caches`, `Containers`, `WebKit`, `HTTPStorages`, `Application Scripts` | `{bundleID}/` |
| `~/Library/Preferences` | `{bundleID}.plist`, `{bundleID}.*.plist` |
| `~/Library/Logs` | `{bundleID}/` |
| `~/Library/Cookies` | `{bundleID}.binarycookies` |
| `~/Library/Saved Application State` | `{bundleID}.savedState/` |
| `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons` | `*{bundleID}*.plist` |
| `~/Library/Group Containers` | `*.{bundleID}/`, listed separately, never preselected |

Group Containers are shared across an app suite (`ScanPolicy.isGroupContainer`), so they get a
"Shared Data" warning: remove only when uninstalling every related app.

Homebrew-managed apps are detected from the caskroom receipt (`HomebrewCaskroom`).

## Stale app versions — `StaleAppVersionRule`

Groups bundles by `CFBundleIdentifier` (falling back to a normalised name), sorts by
`FileSystemUtils.compareVersionStrings` with `effectiveAgeDate` as tiebreaker, and flags all but the
newest as `.review`. Never `.safe`: keeping an older Xcode next to a new one is often intentional.
Identical versions are not flagged, and `/System/Applications` is skipped.

## Update checks — `OutdatedChecker`

Sparkle (`SUFeedURL` appcast) and Mac App Store (iTunes lookup, batches of 25) run in parallel with a
network timeout. The app is never launched to check.
