# User Stories — Remaining Work

Each story is a self-contained unit of user-visible value. Stories are sized to be meaningful PRs (multiple files, end-to-end feature), not individual rule additions or test tweaks.

> **Priority note:** The SwiftUI app is the primary deliverable. The CLI (`PareCLI`) is a secondary diagnostic/testing tool. CLI sub-tasks in each story are optional — implement them only when they are trivial or reuse shared core utilities already needed for the app.

---

## US-1 — Scan Dashboard "By Tool" Breakdown ✅

**As a user running a scan, I want to see exactly how much space each tool or app is consuming, so I know where to focus my cleanup effort without digging through individual findings.**

### What was delivered

- **SwiftUI**: "By Tool" section always visible (not profile-gated). Collapsible row per app showing total reclaimable bytes, share percentage, and file count. Expand to see the top 10 files ≥ 1 MB for that app.
- **CLI**: Per-app rollup section on developer/designer/video-builder profiles with sizes and percentages.
- **Core**: `ScanReportAnnotator` in `PareCore` — `sourceApp(for:)` maps findings to apps via ordered path-pattern matching + reverse-DNS bundle ID extraction from `~/Library/Caches/`. `appRollups(from:)` returns `AppRollup` structs with `topFiles: [TopFile]`; apps below 1 MB total fold into "Other".

### Attribution coverage

Xcode, JetBrains, VS Code, Docker, Package Managers, Safari, Chrome, Firefox, Adobe, Figma, DaVinci Resolve, Final Cut Pro, Slack, Zoom, Spotify, Teams, Discord, Telegram, 1Password, Notion, Arc, Mail, Music, Photos, iMovie, System Logs, Temp Files, and any app via bundle-ID extraction from cache paths.

### UX notes

- Rows with < 1 MB total are folded into "Other" to avoid noise from hundreds of tiny bundle-ID entries.
- Expand animation uses `.clipped()` + `.opacity` transition to prevent content overflowing adjacent rows.

### Key files

- `Sources/PareCore/` — new `ScanReportAnnotator.swift`
- `Sources/PareCLI/main.swift` — use shared annotator
- `Sources/PareApp/ViewModels/ScanDashboardViewModel.swift` — expose per-tool rollups
- `Sources/PareApp/Views/ScanDashboardView.swift` — "By Tool" section

### Session prompt

```text
Implement US-1 (Developer Scan Dashboard) from docs/user-stories.md.

1. Create Sources/PareCore/ScanReportAnnotator.swift:
   - Move sourceApp(for:) logic from main.swift into a public struct ScanReportAnnotator
   - Add appRollups(from:) → [(app: String, totalBytes: Int64, fileCount: Int)] sorted by size

2. Update main.swift to use ScanReportAnnotator instead of its local helpers.
   Format the "By Tool" section as a labelled block, profile-gated (skip on baseline).

3. Update ScanDashboardViewModel to compute and expose perToolRollups using ScanReportAnnotator.

4. Add a collapsible "By Tool" breakdown section to ScanDashboardView for the developer profile.

5. Add unit tests for ScanReportAnnotator attribution and rollup aggregation.

Run swift test. Launch the app (make run-app), switch to Developer profile, run a scan, and verify the "By Tool" breakdown card appears with collapsible rows.
```

---

## Unified Scan (app architecture change) ✅

**Profile picker removed.** The SwiftUI app now always runs `RuleCatalog.all` — the union of all **36 unique rules** across every former profile (baseline + developer + designer + video-builder), deduplicated by rule ID. Results are organised by `ScanCategory` (Category Overview, By Tool, Large Files by Category). The CLI retains profile-based scanning for targeted diagnostic use.

---

## US-2 — Scan Performance

**As a user who re-scans frequently, I want the second scan of the same profile to complete significantly faster than the first, so I can check for new junk without waiting for a full directory crawl.**

### What it covers

- **Incremental metadata cache**: `ScanMetadataCache` actor persists per-directory modification timestamps to `~/Library/Application Support/Pare/scan-cache.json`. On subsequent runs, `FileSystemTraversal` skips directories whose `contentModificationDate` hasn't changed.
- **Cache invalidation**: cache entry is invalidated when the directory's `contentModificationDate` changes, or when the profile changes. Manual "Force rescan" clears the cache.
- **Benchmark**: add `ScanBenchmarkTests` that measures traversal time on the real home directory and asserts the second run is ≥ 30% faster.
- **Reliability**: add tests that simulate a scan being cancelled mid-run and verify that a subsequent scan completes correctly without stale state.

### Out of scope

- Caching scan *findings* (only filesystem traversal metadata)
- Cross-profile cache sharing

### Acceptance criteria

- Second scan of the same profile is measurably faster (manual benchmark, documented)
- Cache file is written to `~/Library/Application Support/Pare/scan-cache.json`
- Changing profile or calling "Force rescan" triggers a full traversal
- Cancelled scan followed by a new scan produces correct results
- `swift test` passes including new benchmark and reliability tests

### Key files

- `Sources/PareCore/Scanning/` — new `ScanMetadataCache.swift`
- `Sources/PareCore/Scanning/FileSystemTraversal.swift` — integrate cache check
- `Sources/PareCore/Scanning/ScanRunner.swift` — pass cache to traversal
- `Sources/PareApp/ViewModels/ScanDashboardViewModel.swift` — expose "Force rescan"
- `Tests/PareCoreTests/` — new `ScanBenchmarkTests.swift`, `ScanReliabilityTests.swift`

### Session prompt

```text
Implement US-2 (Scan Performance) from docs/user-stories.md.

1. Create Sources/PareCore/Scanning/ScanMetadataCache.swift:
   - actor ScanMetadataCache
   - Loads/saves a [String: Date] dictionary (directory path → last-seen mtime) to
     ~/Library/Application Support/Pare/scan-cache.json
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
- Lists past cleanup sessions from `CleanupTransaction` JSON records in `~/Library/Application Support/Pare/transactions/`
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

- `Sources/PareApp/Views/Components/` — new `ExcludeButton.swift`, swipe action on `LargeFileRow`/`TopFileRow`
- `Sources/PareApp/Views/` — new `ExclusionListView.swift`, `HistoryView.swift`
- `Sources/PareApp/ViewModels/` — new `ExclusionListViewModel.swift`, `HistoryViewModel.swift`
- `Sources/PareApp/Views/ScanDashboardView.swift` — Settings sheet trigger, History tab

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
   from ~/Library/Application Support/Pare/transactions/, exposes restore(item:) and
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

- **Code signing**: add entitlements file (`PareApp.entitlements`) with `com.apple.security.files.user-selected.read-write` and hardened runtime enabled in `Package.swift` or Xcode project settings
- **Notarization workflow**: document or automate the `xcrun notarytool` steps (can be a `make notarize` target with instructions)
- [x] **Diagnostics export**: `DiagnosticsExporter` in core that produces a JSON bundle containing: app version, macOS version, last scan report summary, rule catalog for the active profile, and anonymised path prefixes. Exposed as "Export Diagnostics…" menu item in the app.
- **Distribution decision** (pending from Phase 0): document whether direct distribution or App Store is chosen and what entitlements that requires

### Out of scope

- App Store submission itself (requires developer account decisions)
- Automatic update mechanism

### Acceptance criteria

- App builds with hardened runtime and a valid signing identity
- `make notarize` (or documented steps) successfully submits to Apple notarization
- [x] "Export Diagnostics…" produces a readable JSON file the user can attach to a GitHub issue
- All existing tests pass on a signed build

### Key files

- `Package.swift` / Xcode project — signing settings, entitlements
- `PareApp.entitlements` — new file
- `Sources/PareCore/` — new `DiagnosticsExporter.swift`
- `Sources/PareApp/` — "Export Diagnostics…" menu item
- `Makefile` — new `notarize` target

### Session prompt

```text
Implement US-4 (Distribution Readiness) from docs/user-stories.md.

1. Create PareApp/PareApp.entitlements with:
   - com.apple.security.app-sandbox = true (if targeting App Store) OR
     com.apple.security.cs.allow-unsigned-executable-memory = false (direct distribution)
   - com.apple.security.files.user-selected.read-write = true
   - com.apple.security.files.downloads.read-write = true
   Wire entitlements into Package.swift or the Xcode target.

2. Create Sources/PareCore/DiagnosticsExporter.swift:
   - struct DiagnosticsBundle: Codable — appVersion, macOSVersion, scanDate,
     profileUsed, categorySummaries (no file paths), ruleIds
   - func export(report: ScanReport, profile: ScanProfile) -> DiagnosticsBundle
   Add tests for DiagnosticsExporter serialisation.

3. Add "Export Diagnostics…" to the app's menu/toolbar that writes DiagnosticsBundle
   as pretty-printed JSON to a user-chosen location via NSSavePanel.

4. Add `make notarize` to Makefile with documented xcrun notarytool steps
   (substituting $APPLE_ID, $TEAM_ID, $APP_PASSWORD env vars).

Run swift test. Build and verify the entitlements are embedded in the binary
with `codesign -d --entitlements - .build/release/PareApp`.
```

---

## US-5 — Leave Homebrew (Detach Cask, Keep App)

**As a user who installed browsers/IDEs via Homebrew Cask, I want to stop Homebrew from managing selected apps without deleting them, so terminal `brew upgrade --greedy` (or accidental upgrades) cannot replace a running app bundle and break my session.**

### Problem

Casks like Google Chrome and VS Code set `auto_updates: true`. When Brew upgrades them it replaces `/Applications/….app` on disk. A process that is already open becomes unusable until quit/relaunch. Users may still run greedy upgrades outside Pare; the durable fix is to detach ownership while keeping the app.

### What it covers

- **Core**: `CaskLeaveHomebrew` — resolve installed `.app` paths, refuse (or force-quit) if running, stage apps aside, `brew uninstall --cask` **without** `--zap`, restore apps to `/Applications` (or `~/Applications`).
- **Orphaned casks** (receipt but no app): leave = plain `brew uninstall --cask` (cleanup only).
- **SwiftUI**: per-cask **Leave Homebrew** action with confirmation explaining: app stays; Brew no longer upgrades/uninstalls it; prefs/data are not wiped; re-adopt later via Migrate.
- **Copy for auto-update casks**: hint that the app will update itself after leaving.

### Out of scope

- Bulk multi-select leave (v1 is one cask at a time)
- Deleting Caskroom receipts without going through `brew uninstall`
- Changing formula unlink behavior (formulae use real `brew unlink`)

### Acceptance criteria

- Leaving a cask keeps the `.app` on disk and removes the cask from `brew list --cask`
- User data / prefs are not removed (no `--zap`)
- If the app is running, leave fails with a clear message unless the user chooses force-quit
- After leave, the cask disappears from the Casks tab; the app may appear under Migrate
- Unit tests cover path resolution, stage/restore, and orphaned short-circuit

### Key files

- `Sources/PareCore/Homebrew/CaskLeaveHomebrew.swift` — new
- `Sources/PareApp/ViewModels/HomebrewManagerViewModel.swift` — leave action
- `Sources/PareApp/Views/HomebrewManagerView.swift` — button + confirm
- `Tests/PareCoreTests/HomebrewTests.swift` — leave helpers
- `docs/features/homebrew-manager.md` — document Leave operation

### Session prompt

```text
Implement US-5 (Leave Homebrew) from docs/user-stories.md.
```

---

## US-6 — Safer Homebrew Upgrade All (Non-Greedy Default)

**As a user upgrading packages from Pare, I want “Upgrade All” to skip self-updating casks by default, so Chrome/VS Code are not force-replaced mid-session while Zalo-style casks still get Brew updates.**

### Problem

Pare previously ran `brew upgrade --greedy` for Upgrade All, which upgrades `auto_updates: true` casks (Chrome, VS Code, Slack, …) and can break running apps. Homebrew’s default `brew upgrade` already skips those casks.

### What it covers

- **Upgrade All** → `brew upgrade` (no `--greedy`)
- Outdated list still uses `--greedy` discovery so self-updating apps remain visible
- Split counts: packages Brew will upgrade vs self-updating (auto) casks
- UI: Upgrade All button uses the non-greedy count; outdated auto-update rows show clearer “updates itself” help and optional single-package upgrade still allowed with warning in help text
- Optional secondary action: **Upgrade self-updating too** → `brew upgrade --greedy` with an explicit confirmation warning

### Out of scope

- Auto quit/relaunch around individual cask upgrades (future polish)
- Changing terminal Homebrew behavior outside Pare

### Acceptance criteria

- Upgrade All does not pass `--greedy`
- Self-updating outdated casks are still listed and labeled
- User can still upgrade a single auto-update cask explicitly
- Docs/user story and feature doc match the new default

### Key files

- `Sources/PareApp/ViewModels/HomebrewManagerViewModel.swift`
- `Sources/PareApp/Views/HomebrewManagerView.swift`
- `docs/features/homebrew-manager.md`

### Session prompt

```text
Implement US-6 (Safer Upgrade All) from docs/user-stories.md together with US-5.
```
