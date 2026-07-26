# Pare — Refactoring, Upgrade & Redesign Master Plan

Date: 2026-07-26
Status: Approved — execution in progress (per-phase branches from `master`)
Source: full-project audit (PareCore 78 files / ~8k LOC, PareApp 41 files / ~7.7k LOC, 360 tests green, docs/roadmap/review corpus).

Baseline at time of writing: `make build` clean, `make test` 360/360 passing on `master` (7a3d70e).

---

## Audit summary (why these plans)

**Safety:** `CleanupEngine`'s re-verification gate is weaker than scan-time gates — `ScanPolicy.isProjectArtifact` passes *any* directory named `build`/`dist`/`target` anywhere on disk; `isUnderWrongPlatformNativeDirectory` passes anything with a `linux`/`win` path component. The engine never consults `ExclusionList`; three age gates fail open when file attributes are unreadable; the undo transaction is saved only *after* files are trashed.

**Correctness:** `ProjectArtifactRule` + `ProjectArtifactsRule` are both registered and double-count; `UserCachesRule.excludedTopLevelNames` misses entries other rules also report (Edge, Opera, pip, pypoetry, uv, copilot-for-xcode, TemporaryItems); excluding a finding leaves `totalReclaimableBytes` stale; undo reports success even when restores failed; `AppInventory` has a Spotlight double-resume race.

**Structure:** `ScanDashboardViewModel` is a 1,163-line god object (24 `@Published`, 13 nested types, ~200 lines of domain logic belonging in PareCore); ~800 lines of dead code (`CleanupError` never constructed, orphaned `ProjectRootsView`+VM, unused row components, `resultsVisible`, `largeFilesByCategory` pipeline); the "stat dir → finding" helper is re-implemented 7×; process streaming duplicated between `BrewRunner` and `MaintenanceRunner`.

**UI/UX:** `.id(selection)` in `PareApp.swift` destroys every screen's state on tab switch; two clashing sheet design languages (dark themed vs `.regularMaterial` system); ~170 hardcoded `.system(size:)` fonts defeat the app's own text zoom on ~40% of screens; near-zero accessibility (18 modifiers app-wide, no VoiceOver labels on result rows, no reduce-motion, no Dynamic Type); 4 empty-state designs and 5 error mechanisms coexist; two category color palettes disagree between list and donut chart.

**Ship-readiness:** Phase 9 (signing/notarization) is the only wholly open roadmap phase; no CI; zero view-model test coverage.

---

# Plan 1 — Refactoring

Every phase must end with `make build` clean and `make test` green, plus new regression tests for behavior it changes.

## Phase R0 — Safety & correctness hotfixes

| # | Fix | Where |
|---|-----|-------|
| R0.1 | Tighten `CleanupEngine` re-verify gate: `isProjectArtifact` must require project-root evidence (sibling `package.json`/`.git`/`Cargo.toml`/etc., or path under a registered project scan root), not a bare directory-name match. Restrict `isWrongPlatformPath` to the scan roots `ScanPolicy` already defines for `WrongPlatformBinariesRule`. | `Sources/PareCore/Scanning/ScanPolicy.swift` (~L464, ~L657), `Sources/PareCore/Cleanup/CleanupEngine.swift` (~L155) |
| R0.2 | `CleanupEngine` must consult `ExclusionList` at cleanup time (currently scan-time only). | `CleanupEngine.swift` `clean(...)` |
| R0.3 | Close the three fail-open age gates: unreadable resource values block cleanup instead of skipping the check. | `CleanupEngine.swift` ~L181, `ScanPolicy.swift` ~L93 (`passesUnusedAge`), ~L586 (`passesMinimumAge`) |
| R0.4 | Persist `CleanupTransaction` incrementally (write before/during trash loop, finalize after); a failed save must never lose the undo record; surface save failure in `CleanupResult` instead of throwing after deletion. | `CleanupEngine.swift` ~L222 |
| R0.5 | De-dupe findings: unregister one of `ProjectArtifactRule`/`ProjectArtifactsRule` (keep Spotlight-backed v2; fold manual paths in); complete `UserCachesRule.excludedTopLevelNames` (Microsoft Edge, com.operasoftware.Opera, pip, pypoetry, uv, com.github.copilot-for-xcode, TemporaryItems); move rule-ownership policy into `ScanPolicy`. | `RuleCatalog.swift` L34/L62, `Rules/UserCachesRule.swift` L17 |
| R0.6 | Recompute `totalReclaimableBytes` + category sums when a finding is excluded. | `Sources/PareApp/ViewModels/ScanDashboardViewModel.swift` ~L1081 (`exclude(path:)`) |
| R0.7 | Undo honesty: propagate restore-failure counts; never report `.undone(restoredCount:)` when restores failed; stop discarding errors in `restore`/`restoreItem`. | `ScanDashboardViewModel.swift` ~L1061, `CleanupEngine.swift` ~L264/~L289 |
| R0.8 | Fix `AppInventory` Spotlight double-resume race with a locked finished flag. | `Sources/PareCore/AppManager/AppInventory.swift` L98–152 |
| R0.9 | Kill silent failures: `catch {}` in `HomebrewManagerViewModel.reloadFormulae` (~L274); `try?` on History JSON/CSV export (`HistoryView.swift` ~L141/159); `ExclusionListViewModel` load/remove `try?` (~L16/20) — each gets an error surface. | PareApp |

## Phase R1 — Error handling & policy consolidation

1. Construct the dead `CleanupError` enum on all 8 string-reason skip paths; change `CleanupResult.skipped` to typed reasons.
2. Add a per-rule error channel to `ScanRunner`/`ScanReport` ("rule failed" ≠ "rule found nothing"); surface as a scan warning in the VM.
3. Wire `FullDiskAccessChecker` into traversal: count permission errors swallowed by `FileSystemTraversal.swift` ~L44 and report "N locations unreadable" on `ScanReport`.
4. Consolidate inline safety markers into `ScanPolicy`: `BrowserCachesRule.swift` ~L28 (divergent copy missing `session`/`cookies`/`keychain`), `VSCodeReviewRequiredStateRule.swift` ~L14, `JetBrainsReviewRequiredRule.swift` ~L22, `ProjectRootDiscovery.swift` ~L132.
5. Move per-rule hardcoded age thresholds into `ScanPolicy.defaultMinimumAgeSeconds` (MobileSync 30/180d, OrphanedLaunchAgents 30d, BrowserReviewData 30d ×2, JetBrains 90d, Installer 7d).
6. Add the search-index guard to `matchesPersonaPath` (parity with `isLowImpactPath`).
7. Split `ScanPolicy.swift` (693 lines) into `ScanPolicy+Markers` (data; ideally JSON resource), `+Safety`, `+Age`, `+Platform`, `+Docker`. Snapshot-test marker lists before the split.

## Phase R2 — Deduplication & dead-code removal

1. Extract `ScanFindingBuilder` (the "stat dir → size → mtime → finding" helper) into `FileSystemUtils`; migrate all 7 call sites; the three gate-free copies (`PythonCachesRule`, `RubyCachesRule`, `JavaBuildCachesRule`) gain the age/safety gate as a side effect.
2. Extract a shared `ProcessStreamer` for `BrewRunner.stream`/`MaintenanceRunner.shellStream` (one `LockedBuffer`; use the non-blocking `terminationHandler` pattern from `BrewRunner.run`).
3. Unify: version comparison (`FileSystemUtils.compareVersionStrings` vs `VSCodeDuplicateExtensionsRule.compareVersion`), directory sizing (`FileSystemUtils.directorySize` vs `AppInventory.totalAllocatedSize`), `LoadState` (copied between two VMs).
4. Move CLI/VM-duplicated presentation into PareCore (`ScanReportPresenter`: large-file groups, largest-items sort, byte formatting w/ consistent units incl. TB, risk tags). CLI + app consume it.
5. Delete dead code: `LargeFileRow`, `TopFileRow`, `CategorySummaryRow`, `resultsVisible`, `largeFilesByCategory` pipeline, `ScanRunner` profile extensions, vestigial `ScanReportAnnotator` instance init, `AppManagerView.emptyIcon` dead branch. Wire-or-delete: `ScanPolicy.isLargeFile`/`isSystemApp`/`isGroupContainer` (currently re-implemented inline in `AppInventory`/`AppUninstaller`).
6. Decide-and-resolve: keep ONE project-roots model (`ProjectRootsView`+VM is fully built but unwired; `ProjectScanPathsView` is wired) — default: delete `ProjectRootsView`/`ProjectRootsViewModel`, keep `ProjectScanPathsView`. Register-or-delete `DockerLogsReviewRequiredRule` — default: delete (tests assert it absent from catalog).
7. Fix wrong docs-in-code: `AppUninstaller` doc claims `NSWorkspace.recycle` (uses `FileManager.trashItem`); `MaintenanceRunner` no-op `localizedDescription ?? ""`; three `customScan` rules returning `nil` instead of `[]` (`MobileSyncBackupsRule`, `ProductivityCachesRule`, `OrphanedLaunchAgentsRule`).

## Phase R3 — View-model decomposition

1. Split `ScanDashboardViewModel` (1,163 lines → ≤300-line files):
   - Move to PareCore: `rollupFolderPath` (cache-path taxonomy), `buildFolderAggregate`, `makeToolGroups`, `makeToolRollups`.
   - Extract `ScanSelectionModel` (selection sets + counters + tri-state + expansion state, absorbing view-local `expandedCategories`/`expandedToolGroups`).
   - Extract `CleanupCoordinator`: one confirm method + a `PendingCleanup` enum replacing 3 `@Published Bool` sheet flags and 3 duplicate `confirm*Clean` bodies.
   - Extract `PermissionCoachingModel` (FDA state machine, shared with Settings — today two independent probes/observers).
   - Cache candidate count/bytes computed properties (currently ~8 full findings-array passes per sheet render).
2. `HomebrewManagerViewModel`: one `TabState` struct replacing 4 parallel selection sets + 8 `switch selectedTab` dispatchers; batch `operationLog` updates; a real loading state for migration candidates; move filter/sort predicates next to `BrewBulkPlanning` in Core.
3. `AppManagerViewModel`: extract `UpdateInfoMerger` (merge duplicated between `loadApps`/`updateApp`); actually assign `LoadState.error`.
4. Fix navigation state loss: remove `.id(selection)` (`PareApp.swift` ~L80); own all VMs at app level (or a router-held cache) so tab switches stop re-running inventory scans and losing state.

## Phase R4 — Performance

1. Per-scan memoized directory-size index (8 rules independently re-walk `~/Library/Caches`); add cancellation checks inside `FileSystemUtils.directorySize`.
2. `ScanMetadataCache`: batch the manifest save (currently O(N²) bytes/scan — full rewrite per directory); move blocking I/O off the actor hot path.
3. Hoist `CleanupEngine.isPersonaPath`'s ~250-element marker concatenation into a `static let`.
4. Remove filesystem calls from SwiftUI body: precompute `canReveal`/`isLikelyFolderFinding` flags in the existing background `PreparedScanResults` pass.
5. Remove the redundant inner task group in `CachedFileTraversal` (wraps exactly one task). Do NOT re-attempt parallel rule execution (known Swift 5.9 failure; revisit after strict-concurrency migration).

## Phase R5 — Testability, strictness, CI

1. Injection seams: `ProcessRunning` protocol (`BrewRunner`/`MaintenanceRunner`/`OutdatedChecker`), clock injection for age gates, `URLProtocol` stubs for network checkers; replace the four crash-prone `.first!` on `FileManager.urls(for:in:)` (`ExclusionList.swift:94`, `CleanupTransaction.swift:81`, `ProjectRootDiscovery.swift:25`, `MigrationAdvisor.swift:126`) with the safe-fallback pattern from `ScanMetadataCache.defaultURL()`.
2. New `PareAppTests` target covering view models (required by US-8/US-9; coverage currently zero).
3. Enable `StrictConcurrency` upcoming feature in `Package.swift` and fix fallout (`SpotlightQueryRunner` `@unchecked Sendable`, `AppInventory` race).
4. GitHub Actions CI: `swift build` + `swift test` (macOS 13/14/15 matrix) + coverage report.
5. Reconcile stale docs: 2026-07-13 action checklist (tests now green), `checklist.md` vs `roadmap.md` distribution-decision contradiction, `scripts/AppInfo.plist` © 2025, roadmap's stale `docker system prune` checkbox.

---

# Plan 2 — Upgrade

## U1 — Ship v1.0 (Phase 9 gate)
1. Obtain Developer ID Application cert + app-specific password (human-only step).
2. Run `scripts/release.sh` end-to-end: universal build → sign (hardened runtime) → DMG → `notarytool` → staple → Gatekeeper pass on a clean machine.
3. Add `make notarize` (US-4); update bundle IDs across targets; fix © year.
4. Tag `v1.0.0`, publish signed DMG on GitHub Releases; CI release workflow on tag push.
5. Post-1.0: in-app auto-update via Sparkle 2.

## U2 — "Safe Care" one-button journey
1. Single hero CTA: Scan → auto-select `.safe` → one confirmation (count + bytes + Trash/undo promise) → clean → optional light maintenance (DNS-safe subset). Never auto-include `.review`/`.advanced`.
2. Build on R3's `CleanupCoordinator`.
3. Completion summary: space freed, undo, "review N more items" pointer.
4. "Space freed over time" ledger on History fed by `CleanupTransactionStore`.

## U3 — Scan progress & perceived performance
1. Full "3-step scan theater": current rule title + index/total; streaming per-category partials as rules complete.
2. Determinate progress + cancel for cleanup and undo.
3. Cap/prioritize huge project-root walks (~500 roots); directory-level rollups for pathological trees (e.g. Chrome caches).
4. (R4's size index is the biggest wall-clock win.)

## U4 — uv & tool-cache intelligence
Execute `docs/plans/2026-07-25-pare-uv-cache-scan-plan.md`:
- Phase A: `CacheRootResolver` (platform + XDG absolute-only + `uv cache dir`) + `ToolCacheDescriptor` (uv, pip, Poetry, pyenv); report-only findings; exact path-component matching (never `contains` — `uvicorn` hazard); uv findings must never pass Trash cleanup.
- Phase B: Maintenance action `uv cache prune` (native cleanup only), streaming output, rescan-and-report.
- Phases C–E follow-ups (CACHEDIR.TAG discovery → more adapters → user roots).
- The plan's 17 named TDD cases are the acceptance suite.

## U5 — Finish open user stories
1. US-8 App Manager: exclude system apps by default, checkbox multi-select, bulk uninstall/update with eligible/skipped batch confirmation, confirm single updates.
2. US-9 Maintenance polish (product question open; regardless: cancellation for running actions, unified log-color scheme, auto-dismissing done states).
3. Category-level whitelist: extend `ExclusionList` with category entries + "never scan this category" UI.

## U6 — Selective breadth (respect the "do not build" list)
Build: large & old files UX ("clutter lite"), read-only login-items browser (extends orphaned-LaunchAgents detection), Mail-attachments detection as `.review` report-only.
Skip (per `docs/features/comparison-app-b.md`): malware engine, menu-bar monitor, cloud connectors, photo/duplicate AI, macOS update install, sudo System Optimizer.

## U7 — Machine-wide storage intelligence (long-term)
Execute `docs/plans/2026-07-25-pare-machine-wide-storage-intelligence-plan.md` in its 9 phases post-1.0; uv slice (U4) is the pilot. Requires R1's data-driven policy substrate first. No big-bang rewrite.

---

# Plan 3 — UI/UX redesign

## D0 — Design-system foundation
1. Reconcile `AppTheme` with `docs/brand-guide.html` palette (`ink #0D1520`, `marine #152030`, `surface #1A2D40`, `seafoam #5CC8BC`/`#8DE8E0`/`#238C82`, `chalk #E4EDF2`, `fog #7A9BB0`).
2. Complete tokens for everything hardcoded: hairline strokes (9 ad-hoc white alphas → ~3 tokens), row/chip radii, card paddings, sheet widths, table-header background. Delete or wire the 8 unused tokens.
3. One category palette: `ScanCategory.tint` in one place; list AND donut consume it (today two disagreeing palettes).
4. Typography through `DisplayScale` only: replace ~170 `.system(size:)` literals with `scale.*` roles (fixes text-zoom dead zones on History/Settings/sheets). Rename the environment key that shadows SwiftUI's `\.displayScale`.
5. Component library (each with `#Preview`): `StatusBanner` (replaces 6 banner variants), `CleanConfirmationSheet` (3 × 85%-identical sheets + thrice-duplicated `infoRow`), `EmptyStateView` (4 designs), `ErrorBanner` (5 mechanisms), `TableHeaderRow` (4 copies), `Badge` (4 copies), `.hoverableRow()` (5 copies), `DisclosureSelectRow` (category+tool sections).

## D1 — App shell & navigation
1. Remove `.id(selection)`; keep per-screen state alive (with R3.4). ⌘1–⌘7 sidebar shortcuts; restore last tab.
2. Real menu bar (Scan ⌘R, Clean Selected, Cancel); fold the custom second "View" menu into the system one.
3. `ModuleChrome` header on all 7 screens (kills verbatim Apps/Homebrew header duplication).
4. Keyboard & focus: `@FocusState` + ⌘F for search fields, Esc/Return on every sheet (Scan's 3 confirmation sheets currently ignore Esc), visible focus rings.

## D2 — One sheet/dialog language
1. All sheets use the dark themed treatment (`AppBackgroundView` + theme colors); eliminate `.regularMaterial`+system-semantic-color sheets in Homebrew/Apps.
2. Pin `.preferredColorScheme(.dark)` at window level (design is dark-only; stops light-mode drift).
3. Unify button roles (black-on-green vs white-on-coral "Move to Trash" inconsistency) via `PrimaryActionButton` roles.
4. Destructive ladder: Deep Clean gets an itemized preview + explicit checkbox.

## D3 — Screen-level redesigns
1. Dashboard: one primary CTA (Safe Care, U2); merge duplicate "Clean selected" buttons into a "Clean ▾" split control; D0 components; scan-warning surface (R1 rule errors / unreadable locations).
2. Cleanup progress: determinate (n/total, bytes) + cancel; success shows freed bytes + prominent undo.
3. Homebrew: one `TabState`-driven list component ×4; Migrate loading state; unified explainer banners.
4. Apps: US-8 batch UI; reachable error state with retry.
5. Disk Analyzer: cancel button; cross-highlight scan findings; aging hints.
6. History: freed-over-time chart; consistent byte units.
7. Settings: single FDA source (`PermissionCoachingModel`); Permissions/Scanning/Appearance/About groups.

## D4 — Accessibility
1. VoiceOver labels/values/`.isSelected` on every result row, checkbox, icon button, sidebar item; `.accessibilityElement(children: .combine)` on composite rows.
2. Respect `accessibilityReduceMotion` for all four infinite animations.
3. Map text zoom onto Dynamic Type (or honor the OS accessibility text size as a floor).
4. WCAG AA contrast audit (`fog` on `ink` is the risky pair).

## D5 — Onboarding & trust
1. First-launch welcome (what Pare does / risk levels & Trash-only promise / FDA grant with live status); handle FDA `.unknown` (today shows nothing).
2. Brand-tone copy pass; remove stale "Select profile and start scan" string.
3. Standard trust footer on destructive sheets; typed skip-reasons shown post-clean (R1).

---

# Execution order

| Wave | Content | Rationale |
|------|---------|-----------|
| 1 | R0 + R1 | Safety first |
| 2 | R3 + D0 + D1 | Decomposition + design system unlock everything |
| 3 | U1 + R5 CI | Ship gate; CI protects later waves |
| 4 | U2 + D2 + D3 | Headline product upgrade |
| 5 | R2 + R4 + D4 + U3 | Cleanup, perf, accessibility, progress |
| 6 | U4 + U5 + D5 | Breadth on a stable base |
| 7 | U6 / U7 | Long-term bets |

## Branch map (initial parallel execution)

| Branch | Phase(s) | Notes |
|--------|----------|-------|
| `refactor/r0-r1-safety` | R0 + R1 | Merge first; others rebase on it |
| `refactor/r2-dedup-dead-code` | R2 | Core rules + dead view code |
| `refactor/r3-viewmodels` | R3 | PareApp decomposition |
| `refactor/r4-performance` | R4 | Core scanning perf |
| `refactor/r5-testability-ci` | R5 | Seams, PareAppTests, CI, doc reconciliation |
| `design/d0-design-system` | D0 | Tokens + component library |
| `feature/u4-uv-cache-phase-a` | U4 Phase A | Self-contained new files |

Phases not branched yet (blocked): U1 (needs cert — human step), U2/D1–D5 (depend on R3/D0 merges), U3 (depends on R4), U5–U7 (later waves).

Suggested merge order: r0-r1 → r2 → r4 → r3 → d0 → r5 → u4. Expect small conflicts in `ScanPolicy`/`CleanupEngine` between r0-r1 and r2/r4 — resolve in favor of r0-r1's safety semantics.
