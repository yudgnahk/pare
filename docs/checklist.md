# Clean My Mac (Pure Swift) - Checklist

## Phase 0 - Discovery and Guardrails
- [x] Define supported macOS version range: **macOS 13+** (set in `Package.swift`).
- [ ] Decide distribution path (direct notarized app vs App Store constraints) — pending business decision.
- [x] Lock safe-delete policy: **move to Trash first** (implemented in `CleanupEngine`).
- [x] Define protected paths and never-delete zones (implemented in `ScanPolicy` protected/sensitive markers + app-state markers).
- [x] Create persona cleanup matrix: **Baseline / Developer / Designer / Video Builder** (implemented in `RuleCatalog`).

## Phase 1 - Core Scanner MVP
- [x] Define `ScanRule` protocol (id/title/category/risk/path resolver/detector).
- [x] Build async filesystem traversal service.
- [x] Implement baseline rules for user cache folders.
- [x] Implement baseline rules for temp folders.
- [x] Implement baseline rules for logs and crash reports.
- [x] Implement safe subset browser cache rules.
- [x] Compute reclaimable size and file count per category.
- [x] Define result model: category, path, size, last-used, confidence.
- [x] Build a basic scan runner to execute selected rules.
- [x] Add unit tests for rule matching and size aggregation.
- [x] Add local run workflow with `Makefile` commands (`build`, `test`, `start`, profile runs).
- [x] Verify manual baseline run via `make start`.

## Phase 2 - SwiftUI macOS App Target (Core Reuse)
- [x] Create a macOS SwiftUI app target (for example, `PareApp`) in the same package/workspace.
- [x] Reuse `App BCore` directly from the app target (no duplicated scan logic).
- [x] Keep `pare-cli` as a debug/diagnostic runner that uses the same core module.
- [x] Add an app state/view model that wraps `ScanRunner` and `RuleCatalog`.
- [x] Add profile selector UI (Baseline/Developer) wired to existing profile rules.
- [x] Add scan action UI and show loading/progress state.
- [x] Show scan results UI: total reclaimable, category summaries, top files.
- [x] Restrict scan results to low-impact candidates and apply default cache-like minimum age of 3 days.
- [x] Add per-category large-file list (`> 50 MB`) and Finder reveal action.
- [x] Align CLI output with shared large-file grouping policy.
- [x] Add/expand tests for policy guardrails (age threshold, large-file threshold, protected-path exclusion).
- [x] Add a local run command path for the app target in docs/Makefile.
- [x] Manually verify CLI and SwiftUI app produce consistent summary totals for the same profile.

## Phase 3 - Persona Packs
- [x] Add Developer pack (Xcode, package caches, optional simulator cleanup).
- [x] Add Designer pack (Adobe/Figma caches and export temp paths).
- [x] Add Video Builder pack (FCP, Premiere/AE, Resolve cache targets).
- [x] Mark high-risk media paths as review-required.

## Manual Testing Status
- [x] Add quick-start manual test guide in `docs/manual-testing.md`.
- [x] Validate `make build` and `make test` locally.
- [x] Validate `make start` baseline output locally.
- [x] Run developer profile manual validation and record findings.

## Developer Mode Scan Enhancements (App-Specific)
- [x] Add Phase A VS Code safe cache rule (`ShipIt`, `CachedExtensionVSIXs`) into developer profile.
- [x] Exclude VS Code cache paths from baseline `UserCachesRule` to prevent duplicate findings.
- [x] Validate developer profile scan output includes VS Code cache findings in developer category.
- [x] Implement Phase B review rules for VS Code state paths and JetBrains plugin/state paths.
- [x] Implement Phase C Docker review/advanced detect-only paths and guidance.
- [ ] Phase D: Fix `DockerVMDataAdvancedRule` — rule incorrectly targets `Docker.raw` (a monolithic VM disk containing user volumes/databases). Remove the rule; replace with CLI-hint guidance for `docker builder prune`. See `docs/developer-mode-phase-d-plan.md`.

## Phase 4 - Safe Cleanup Engine
- [x] Implement move-to-Trash cleanup pipeline.
- [x] Store cleanup transaction logs (timestamped JSON).
- [x] Add restore/undo flow from transaction logs.
- [x] Add pre-delete checks (in-use path, min-age constraints, ADVANCED-risk guard).
- [x] Add global exclusions list (ExclusionList model + JSON persistence + ScanRunner integration).

## Phase 5 - UX and Trust
- [x] Build dashboard with reclaimable storage and top categories.
- [x] Show explainability for each result (why listed and impact — `reason` field + risk badges).
- [x] Implement dry-run mode.
- [x] Implement Quick Clean mode (safe-risk only, confirmation + undo).
- [x] Implement Deep Clean mode (explicit warnings + confirmations for review-risk items).

## Phase 6 - Performance and Reliability
- [ ] Add incremental scan metadata cache.
- [x] Add progress updates and cancellation support (ScanRunner + ViewModel cancel button).
- [x] Handle symlinks, package bundles, and permission failures safely (FileSystemTraversal).
- [ ] Benchmark large directories and optimize hotspots.
- [ ] Add reliability tests for interrupted scans.

## Phase 7 - QA, Security, Release
- [x] Add unit tests for path safety and risk labeling (PathSafetyTests — 14 assertions).
- [x] Add integration tests with seeded junk datasets (ScanIntegrationTests + CleanupRestoreIntegrationTests).
- [x] Add regression tests for protected path enforcement (PathSafetyTests).
- [ ] Complete code signing, hardened runtime, and notarization.
- [ ] Add diagnostics export bundle for support.
