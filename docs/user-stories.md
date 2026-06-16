# User Stories — Remaining Work

Each story is a self-contained unit of user-visible value. Stories are sized to be meaningful PRs (multiple files, end-to-end feature), not individual rule additions or test tweaks.

---

## US-1 — Developer Scan Dashboard

**As a developer running a scan, I want to see exactly how much space each tool (Xcode, JetBrains, VS Code, Docker) is consuming, so I know where to focus my cleanup effort without digging through individual findings.**

### What it covers

- **SwiftUI**: Add a "By Tool" section to the developer-profile scan results — a collapsed breakdown card per tool (Xcode, JetBrains, VS Code, Docker, Other) showing total reclaimable bytes and finding count. Tap to expand and see the top findings for that tool.
- **CLI**: Promote the existing per-app rollup (`groupBySourceApp`) from a bare list to a labelled section that only shows on developer/designer/video-builder profiles, and format it with sizes and percentages.
- **Core**: Move `sourceApp(for:)` attribution logic from `main.swift` into `CleanMyMacCore` as a `ScanReportAnnotator` utility so the SwiftUI app and CLI share the same attribution rules.

### Out of scope

- Changing any scan rules or risk levels
- Per-finding app attribution in the SwiftUI finding rows (just the summary cards)

### Acceptance criteria

- Developer CLI output shows a "By Tool" section listing each app with its total size, sorted largest first
- SwiftUI developer scan result shows collapsible per-tool cards above the category breakdown
- Shared attribution covers: Xcode, JetBrains, VS Code, Docker, Package Managers, Browsers, Adobe/Figma, DaVinci Resolve, Final Cut Pro
- Baseline, Designer, and Video Builder profiles continue to work correctly

### Key files

- `Sources/CleanMyMacCore/` — new `ScanReportAnnotator.swift`
- `Sources/CleanMyMacCLI/main.swift` — use shared annotator
- `Sources/CleanMyMacApp/ViewModels/ScanDashboardViewModel.swift` — expose per-tool rollups
- `Sources/CleanMyMacApp/Views/ScanDashboardView.swift` — "By Tool" section

### Session prompt

```text
Implement US-1 (Developer Scan Dashboard) from docs/user-stories.md.

1. Create Sources/CleanMyMacCore/ScanReportAnnotator.swift:
   - Move sourceApp(for:) logic from main.swift into a public struct ScanReportAnnotator
   - Add appRollups(from:) → [(app: String, totalBytes: Int64, fileCount: Int)] sorted by size

2. Update main.swift to use ScanReportAnnotator instead of its local helpers.
   Format the "By Tool" section as a labelled block, profile-gated (skip on baseline).

3. Update ScanDashboardViewModel to compute and expose perToolRollups using ScanReportAnnotator.

4. Add a collapsible "By Tool" breakdown section to ScanDashboardView for the developer profile.

5. Add unit tests for ScanReportAnnotator attribution and rollup aggregation.

Run swift test and make run PROFILE=developer TOP=20 to verify.
```

---

## US-2 — Scan Performance

**As a user who re-scans frequently, I want the second scan of the same profile to complete significantly faster than the first, so I can check for new junk without waiting for a full directory crawl.**

### What it covers

- **Incremental metadata cache**: `ScanMetadataCache` actor persists per-directory modification timestamps to `~/Library/Application Support/CleanMyMac/scan-cache.json`. On subsequent runs, `FileSystemTraversal` skips directories whose `contentModificationDate` hasn't changed.
- **Cache invalidation**: cache entry is invalidated when the directory's `contentModificationDate` changes, or when the profile changes. Manual "Force rescan" clears the cache.
- **Benchmark**: add `ScanBenchmarkTests` that measures traversal time on the real home directory and asserts the second run is ≥ 30% faster.
- **Reliability**: add tests that simulate a scan being cancelled mid-run and verify that a subsequent scan completes correctly without stale state.

### Out of scope

- Caching scan *findings* (only filesystem traversal metadata)
- Cross-profile cache sharing

### Acceptance criteria

- Second scan of the same profile is measurably faster (manual benchmark, documented)
- Cache file is written to `~/Library/Application Support/CleanMyMac/scan-cache.json`
- Changing profile or calling "Force rescan" triggers a full traversal
- Cancelled scan followed by a new scan produces correct results
- `swift test` passes including new benchmark and reliability tests

### Key files

- `Sources/CleanMyMacCore/Scanning/` — new `ScanMetadataCache.swift`
- `Sources/CleanMyMacCore/Scanning/FileSystemTraversal.swift` — integrate cache check
- `Sources/CleanMyMacCore/Scanning/ScanRunner.swift` — pass cache to traversal
- `Sources/CleanMyMacApp/ViewModels/ScanDashboardViewModel.swift` — expose "Force rescan"
- `Tests/CleanMyMacCoreTests/` — new `ScanBenchmarkTests.swift`, `ScanReliabilityTests.swift`

### Session prompt

```text
Implement US-2 (Scan Performance) from docs/user-stories.md.

1. Create Sources/CleanMyMacCore/Scanning/ScanMetadataCache.swift:
   - actor ScanMetadataCache
   - Loads/saves a [String: Date] dictionary (directory path → last-seen mtime) to
     ~/Library/Application Support/CleanMyMac/scan-cache.json
   - API: func isFresh(directory: URL, currentMtime: Date) -> Bool
          func update(directory: URL, mtime: Date)
          func invalidate()

2. Integrate into FileSystemTraversal: before enumerating a directory, check
   isFresh(); if fresh, skip it and return the cached findings for that directory.
   Store results per directory so they can be reused.

3. Add a force-rescan path: ScanRunner.run(rules:forceRescan:Bool=false) that calls
   cache.invalidate() before traversal when forceRescan is true.

4. Wire "Force rescan" button in ScanDashboardViewModel / ScanDashboardView.

5. Add ScanMetadataCacheTests (cache hit/miss, invalidation, persistence round-trip).
   Add ScanReliabilityTests (cancel mid-scan, then run again → correct results).

Run swift test. Run make run PROFILE=developer twice and record the time difference.
```

---

## US-3 — In-App Cleanup Management

**As a user, I want to exclude paths I never want flagged and review what I've previously cleaned — all from within the app — so I can trust the tool and undo mistakes without opening Finder.**

### What it covers

**Exclusion list UI:**
- "Exclude" action on each finding row (long-press / right-click context menu or swipe action) → calls `ExclusionList.add(path:)` and removes the finding from the current results in-place
- Settings/Preferences sheet with a list of excluded paths, each with a "Remove" button → calls `ExclusionList.remove(path:)`
- `ExclusionList` already exists in core; this is purely UI wiring

**Cleanup history UI:**
- New "History" tab in the app
- Lists past cleanup sessions from `CleanupTransaction` JSON records in `~/Library/Application Support/CleanMyMac/transactions/`
- Each session shows: date, total size moved, item count
- Expand a session to see individual items; each item has a "Restore" button → calls `CleanupEngine.restore(transaction:itemPath:)`
- "Clear history" button removes all transaction records
- `CleanupEngine` restore already works in core; this is purely UI

### Out of scope

- Syncing exclusions or history across machines
- Bulk restore of an entire session (future)

### Acceptance criteria

- User can right-click a finding and exclude the path; it disappears immediately and doesn't return on rescan
- Excluded paths list is visible and editable in Settings
- History tab lists all past cleanup sessions loaded from transaction files
- User can restore an individual item from history; the item reappears in its original location
- All existing tests pass

### Key files

- `Sources/CleanMyMacApp/Views/Components/` — new `ExcludeButton.swift`, swipe action on `LargeFileRow`/`TopFileRow`
- `Sources/CleanMyMacApp/Views/` — new `ExclusionListView.swift`, `HistoryView.swift`
- `Sources/CleanMyMacApp/ViewModels/` — new `ExclusionListViewModel.swift`, `HistoryViewModel.swift`
- `Sources/CleanMyMacApp/Views/ScanDashboardView.swift` — Settings sheet trigger, History tab

### Session prompt

```text
Implement US-3 (In-App Cleanup Management) from docs/user-stories.md.

Part A — Exclusion list UI:
1. Add a swipe-to-exclude action on LargeFileRow and TopFileRow that calls
   ExclusionList.shared.add(path:) and removes the finding from the view model's list.
2. Create ExclusionListViewModel (@MainActor ObservableObject): loads paths from
   ExclusionList, exposes remove(path:).
3. Create ExclusionListView: a List of excluded paths, each with a trash/remove button.
4. Add a Settings/gear icon to ScanDashboardView that presents ExclusionListView as a sheet.

Part B — History UI:
1. Create HistoryViewModel (@MainActor ObservableObject): loads CleanupTransaction records
   from ~/Library/Application Support/CleanMyMac/transactions/, exposes restore(item:) and
   clearAll().
2. Create HistoryView: sectioned List by session date, expandable rows showing individual
   items, Restore button per item, Clear History button in toolbar.
3. Add a History tab to ScanDashboardView (TabView or toolbar button).

Run swift test. Launch the app (make run-app) and manually verify exclude and restore flows.
```

---

## US-4 — Distribution Readiness

**As the developer releasing this app, I want a signed and notarized build I can hand to other users, and a diagnostics export users can attach to bug reports.**

### What it covers

- **Code signing**: add entitlements file (`CleanMyMacApp.entitlements`) with `com.apple.security.files.user-selected.read-write` and hardened runtime enabled in `Package.swift` or Xcode project settings
- **Notarization workflow**: document or automate the `xcrun notarytool` steps (can be a `make notarize` target with instructions)
- **Diagnostics export**: `DiagnosticsExporter` in core that produces a JSON bundle containing: app version, macOS version, last scan report summary, rule catalog for the active profile, and anonymised path prefixes. Exposed as "Export Diagnostics…" menu item in the app.
- **Distribution decision** (pending from Phase 0): document whether direct distribution or App Store is chosen and what entitlements that requires

### Out of scope

- App Store submission itself (requires developer account decisions)
- Automatic update mechanism

### Acceptance criteria

- App builds with hardened runtime and a valid signing identity
- `make notarize` (or documented steps) successfully submits to Apple notarization
- "Export Diagnostics…" produces a readable JSON file the user can attach to a GitHub issue
- All existing tests pass on a signed build

### Key files

- `Package.swift` / Xcode project — signing settings, entitlements
- `CleanMyMacApp.entitlements` — new file
- `Sources/CleanMyMacCore/` — new `DiagnosticsExporter.swift`
- `Sources/CleanMyMacApp/` — "Export Diagnostics…" menu item
- `Makefile` — new `notarize` target

### Session prompt

```text
Implement US-4 (Distribution Readiness) from docs/user-stories.md.

1. Create CleanMyMacApp/CleanMyMacApp.entitlements with:
   - com.apple.security.app-sandbox = true (if targeting App Store) OR
     com.apple.security.cs.allow-unsigned-executable-memory = false (direct distribution)
   - com.apple.security.files.user-selected.read-write = true
   - com.apple.security.files.downloads.read-write = true
   Wire entitlements into Package.swift or the Xcode target.

2. Create Sources/CleanMyMacCore/DiagnosticsExporter.swift:
   - struct DiagnosticsBundle: Codable — appVersion, macOSVersion, scanDate,
     profileUsed, categorySummaries (no file paths), ruleIds
   - func export(report: ScanReport, profile: ScanProfile) -> DiagnosticsBundle
   Add tests for DiagnosticsExporter serialisation.

3. Add "Export Diagnostics…" to the app's menu/toolbar that writes DiagnosticsBundle
   as pretty-printed JSON to a user-chosen location via NSSavePanel.

4. Add `make notarize` to Makefile with documented xcrun notarytool steps
   (substituting $APPLE_ID, $TEAM_ID, $APP_PASSWORD env vars).

Run swift test. Build and verify the entitlements are embedded in the binary
with `codesign -d --entitlements - .build/release/CleanMyMacApp`.
```
