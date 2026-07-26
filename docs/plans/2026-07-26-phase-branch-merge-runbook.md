# Phase-Branch Merge Runbook

Date: 2026-07-26
Purpose: everything needed to merge the seven phase branches into `master` **yourself**, from scratch, without relying on the pre-built `integration/all-phases` branch. Use this if you want to review/redo the integration, or if `integration/all-phases` turns out to have a bad resolution.

All branches are based on `master` @ `7a3d70e` (one docs-only commit behind `2ad3344`). Merging into current master is clean with respect to that gap.

## Branch inventory

| Branch | Head | Commits | Tests on branch | What it contains |
|--------|------|---------|-----------------|------------------|
| `refactor/r0-r1-safety` | `2eb33a8` | 11 | 376/376 | Fail-closed cleanup re-verify gates; ExclusionList checked at cleanup time; transaction persisted before/during trash loop; rule de-dup (catalog 36→35, `ProjectArtifactRule` removed); stale-totals/undo-honesty/silent-failure fixes; typed `CleanupError` skip reasons; per-rule failure + unreadable-location channels on `ScanReport`; markers/ages consolidated into ScanPolicy; ScanPolicy split into `+Markers/+Safety/+Age/+Platform/+Docker` (digest snapshot test proves pure movement) |
| `refactor/r2-dedup-dead-code` | `3ad9030` | 7 | 364/364 | `ScanFindingBuilder` (7 call sites, adds missing gates to Python/Ruby/JavaBuild); shared `ProcessStreamer`; `ScanReportPresenter` (CLI + 3 VMs, consistent TB units); dead code deleted (~977 lines: ProjectRootsView+VM, DockerLogsReviewRequiredRule, 3 unused row components, `resultsVisible`, `largeFilesByCategory` pipeline, profile statics); `nil`-vs-`[]` customScan contract fix |
| `refactor/r3-viewmodels` | `80c2b4f` | 4 | 371/371 | ScanDashboardViewModel 1,163→589 (Core `FolderRollup`, `ScanSelectionModel`, `CleanupCoordinator` + `PendingCleanup`, `PermissionCoachingModel`, `CandidateStats`); Homebrew `TabState` + batched operation log + Migrate loading state; `UpdateInfoMerger`; `.id(selection)` removed + `AppModelStore` (tab-switch state loss fixed) |
| `refactor/r4-performance` | `f67ac12` | 5 | 371/371 | Per-scan `DirectorySizeIndex` memoization via `ScanEnvironment`; cancellation checks in `directorySize`; `ScanMetadataCache` one-flush-per-scan (kills O(N²) writes); persona-marker hoist in CleanupEngine; precomputed reveal/folder flags (no FileManager in SwiftUI bodies); single-directory traversal overload |
| `refactor/r5-testability-ci` | `17ca70f` | 5 | 410/410 | `ProcessRunning` seam + `SystemProcessRunner` (BrewRunner/MaintenanceRunner/BrewOutdatedChecker); URLSession + clock injection; four `.first!` crash fixes; `PareAppTests` target (34 VM tests); strict concurrency `complete` (20→9 warnings; `MetadataQueryRunner` fixes the Spotlight double-resume; `SpotlightQueryRunner` lock-guarded); `.github/workflows/ci.yml` (macOS 13/14/15 + coverage); stale docs/plist reconciled |
| `design/d0-design-system` | `c74ca17` | 5 | 360/360 | AppTheme mapped to brand-guide palette (`AppTheme.Brand`); hairline/fill/radius/sheet tokens; one category palette (`CategoryStyle`); `.system(size:)` 170→0; env key renamed `\.displayScale` → `\.pareDisplayScale`; component library with previews: `CleanConfirmationSheet`, `StatusBanner`, `EmptyStateView`, `ErrorBanner`, `TableHeaderRow`, `Badge`, `.hoverableRow()`, `DisclosureSelectRow` |
| `feature/u4-uv-cache-phase-a` | `d3688d8` | 3 | 389/389 | `CacheRootResolver` (platform/XDG/`uv cache dir`), `ToolCacheDescriptor` (uv/pip/Poetry/pyenv), `ToolCommandRunner` (3s timeout, output validation), `UvCacheRule` (report-only `.advanced`, catalog 36→37 from its base), `ScanPolicy.isEqualToOrDescendant` exact-component matching |

Reference integration: `integration/all-phases` contains all seven merges already resolved (481/481 tests green). Each merge commit's message documents its resolutions — `git log --merges integration/all-phases` — and you can inspect any resolution with `git show <merge-commit>`.

## Merge order (dependency-driven)

```
git checkout -b integration/mine master
git merge refactor/r0-r1-safety      # 1 — clean (or trivial)
git merge refactor/r2-dedup-dead-code # 2
git merge refactor/r4-performance     # 3
git merge refactor/r3-viewmodels      # 4
git merge design/d0-design-system     # 5
git merge refactor/r5-testability-ci  # 6
git merge feature/u4-uv-cache-phase-a # 7
```

Run `make build && make test` after **every** merge before starting the next. Expected passing totals at each step: 376 → 380 → 391 → 402 → 402 → 452 → 481.

## Global resolution principles

1. **Safety semantics always win.** Where r0-r1 changed behavior (fail-closed age gates, typed skip reasons, exclusion checks, transaction-before-trash), every other branch's version of the same code must inherit that behavior, not overwrite it.
2. **r3's decomposed architecture wins for the app layer.** When a hunk pits the old monolithic VM shape against r3's extracted models, keep r3's shape and port the other branch's *semantic* change into it.
3. **d0's components win for the view layer**, wired to r3's APIs (item-driven sheet, selection-model expansion).
4. **Deletions by r2 stay deleted** even when a later branch (based on old master) re-introduces the code (`largeFilesByCategory`, `resultsVisible`, `totalAllocatedSize`, dead views, `ProjectArtifactRule`).
5. When two branches fix the same bug differently, keep the more thorough fix (see step 6: `MetadataQueryRunner` over the inline lock; `ProcessRunning` over `ProcessStreamer`).

## Per-merge conflict guide

### 1. `refactor/r0-r1-safety`
Merges clean against master.

### 2. `refactor/r2-dedup-dead-code`
- `Tests/PareCoreTests/ScanRunnerTests.swift` (2 hunks):
  - Baseline-count test: use r2's `RuleCatalog.baseline` API with r0-r1's count **11**.
  - Delete the `DockerLogsReviewRequiredRule` test (r2 deleted the rule); keep r0-r1's new R1.2/R1.3 tests that follow it.

### 3. `refactor/r4-performance`
- `ProjectArtifactRule.swift` — modify/delete: **delete** (`git rm`; r0.5 removed the rule).
- `PythonCachesRule` / `RubyCachesRule` / `JavaBuildCachesRule` / `PackageManagerCachesRule`: keep the `ScanFindingBuilder` call (r2) and give the builder an optional `sizeIndex: DirectorySizeIndex? = nil` parameter used as `sizeIndex?.directorySize(url:) ?? FileSystemUtils.directorySize(url:)`; call sites pass `environment.sizeIndex`. Delete the old `directoryFindings` r4 re-adds to `PackageManagerCachesRule`.
- `ScanRule.swift` / `FileSystemTraversal.swift` / `CachedFileTraversal.swift`: keep **both** features — r0-r1's `collectFilesReportingErrors` and r4's single-directory overload. Add a single-directory `collectFilesReportingErrors(in directory:)` protocol variant (default forwards to the array overload) so `CachedFileTraversal` gets r4's no-task-group path **without losing** unreadable-path reporting.
- `ScanRunner.swift`: `runRule(rule, environment: runEnvironment, traversal:)` returning r0-r1's `RuleOutcome`.
- `ScanDashboardViewModel.swift`: `PreparedScanResults` keeps r0-r1's `scanWarnings` **and** r4's `revealablePaths`/`folderFindingPaths`; drop r4's `largeFilesByCategory` line (r2 deleted the pipeline).

### 4. `refactor/r3-viewmodels`
The heaviest merge (10 hunks in `ScanDashboardViewModel.swift`). Keep r3's structure; port semantics:
- Nested types (SummaryItem, FindingItem, CategoryFolderRow, FolderAggregate, CleanupState, ToolRollupItem): take r3's side (moved to `ScanDashboardItems.swift`, Core `FolderRollup.swift`, `CleanupCoordinator`).
- `PreparedScanResults` fields: `toolRollups: [ToolRollup]` + `candidateStats: CandidateStats` (r3) + `scanWarnings`/`revealablePaths`/`folderFindingPaths` (already there); **no** `largeFilesByCategory`.
- Published block: r3's `selection = ScanSelectionModel()` side, minus `largeFilesByCategory` and `resultsVisible`.
- Private state: keep only r4's `revealablePaths`/`folderFindingPaths` sets (folder maps live in `ScanSelectionModel`; engine lives in `CleanupCoordinator`).
- Keep the `largestItemsSorted` helper that delegates to r2's `ScanReportPresenter`.
- `prepareScanResults` return: r3's `FolderRollup.makeToolRollups` + `CandidateStats.compute` + the warnings/reveal fields.
- Undo: take r3's `cleanup.undoLastCleanup()` delegation, then **port R0.7 into `CleanupCoordinator`**: `case undone(restoredCount: Int, failedCount: Int)` and `let (restored, failed) = await engine.restore(...)` → `.undone(restoredCount: restored.count, failedCount: failed.count)`. (`ScanDashboardView` already pattern-matches the two-value case.)
- `HomebrewManagerViewModel.reloadFormulae`: r3's `tabSelections.clear(...)` + r0.9's `reloadError` catch (never `catch {}`).
- `ScanDashboardView.isLikelyFolderFinding`: r3's top-level `FindingItem` signature + r4's precomputed `viewModel.isFolderFinding(path:)` body.

### 5. `design/d0-design-system`
- `LargeFileRow` / `TopFileRow` / `CategorySummaryRow` / `ProjectRootsView` — modify/delete: **delete** (d0 only migrated fonts in files r2 removed).
- Five view headers (`PareApp`, `AppManagerView`, `DiskAnalyzerView`, `MaintenanceView`, `HomebrewManagerView`): r3's injected-VM line (`@ObservedObject var viewModel:` / `let models: AppModelStore`) + d0's `@Environment(\.pareDisplayScale)`.
- `ScanDashboardView` (8 hunks):
  - Sheet presentation: `.sheet(item: $viewModel.pendingCleanup)` (r3) driving **one** `CleanConfirmationSheet` (d0) — switch `pending` to pick `quickCleanConfig`/`deepCleanConfig`/`selectedCleanConfig`, actions `cancelPendingCleanup()`/`confirmPendingCleanup()`.
  - `.undone` banner: d0's `StatusBanner` carrying R0.7's restored/failed message (kind `.error` when `failedCount > 0`).
  - Category/tool rows: d0's `DisclosureSelectRow` with r3's expansion API (`viewModel.toggleCategoryExpanded(...)` / `toggleToolGroupExpanded(...)`) instead of d0's view-local `expandedCategories` state.
  - `triState(_:)`: d0's function, r3's top-level `CategorySelectState` type.
  - Three big trailing hunks (old sheet structs vs d0's config extension): take d0's side.

### 6. `refactor/r5-testability-ci`
- `ScanPolicy.swift`: keep the post-split stub; **port** r5's `now: Date = Date()` parameters into `ScanPolicy+Age.swift` — but keep r0.3's fail-closed `return false` guards (r5's copies were still fail-open `return true`).
- `BrewRunner.swift` / `MaintenanceRunner.swift`: take r5's side wholesale (`ProcessRunning` seam supersedes r2's `ProcessStreamer` — then `git rm Sources/PareCore/ProcessStreamer.swift` as orphaned). Re-apply r2.7's tiny fix: `err.localizedDescription ?? ""` → `err.localizedDescription`.
- `AppInventory.swift`: take r5's `MetadataQueryRunner` (supersedes r0.8's inline lock fix — same race, better cure). Do **not** take the `totalAllocatedSize` function r5's side re-adds (r2 deleted it in favor of `FileSystemUtils.directorySize` — no remaining callers).
- `CleanupEngine.swift` (3 hunks): init carries **both** r0's `projectRootsProvider`/`exclusionsProvider` and r5's `now` clock; both age-gate sites use `now()` with r0's typed `CleanupSkippedItem` reasons and the fail-closed `attributesUnreadable` guard.
- `Tests/PareAppTests/*`: replace `AppManagerViewModel.LoadState` / `HomebrewManagerViewModel.LoadState` with the shared top-level `LoadState` (r2/r3 moved it). Everything else compiles as-is.

### 7. `feature/u4-uv-cache-phase-a`
- `UserCachesRule.swift`: keep the ScanPolicy-owned set (`ScanPolicy.userCachesExcludedTopLevelFolderNames` — it already contains `"uv"`).
- `ScanPolicy.swift`: keep the stub; **port** `isEqualToOrDescendant(candidate:root:)` into `ScanPolicy+Safety.swift` (u4's only policy change).
- `ScanRunnerTests.swift`: unified catalog count = **36** (35 after r0.5's removal + `UvCacheRule`).
- `CLAUDE.md`: "**36 unique rules**".

## Verification after the final merge

```
make build                                  # clean
make test                                   # 481 tests, 0 failures
swift run pare-cli --profile developer --top 5   # completes; ADVANCED banner fires if ~/.cache/uv exists
make run-app                                # manual pass: tab switching, scan, clean+undo, Homebrew tabs, ⌘+ zoom
npx gitnexus analyze                        # refresh the code-intelligence index
```

Post-merge housekeeping: `git worktree prune` (agent worktrees already removed), and delete `integration/all-phases` once your own integration (or a fast-forward of it) lands on master.
