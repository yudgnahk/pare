# Clean My Mac (Pure Swift) - Checklist

## Phase 0 - Discovery and Guardrails
- [ ] Define supported macOS version range (recommended: macOS 13+).
- [ ] Decide distribution path (direct notarized app vs App Store constraints).
- [ ] Lock safe-delete policy (default: move to Trash first).
- [ ] Define protected paths and never-delete zones.
- [ ] Create persona cleanup matrix (Developer, Designer, Video Builder).

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
- [x] Create a macOS SwiftUI app target (for example, `CleanMyMacApp`) in the same package/workspace.
- [x] Reuse `CleanMyMacCore` directly from the app target (no duplicated scan logic).
- [x] Keep `cleanmymac-cli` as a debug/diagnostic runner that uses the same core module.
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
- [ ] Implement Phase C Docker review/advanced detect-only paths and guidance.

## Phase 4 - Safe Cleanup Engine
- [ ] Implement move-to-Trash cleanup pipeline.
- [ ] Store cleanup transaction logs (timestamped JSON).
- [ ] Add restore/undo flow from transaction logs.
- [ ] Add pre-delete checks (file locks, in-use, min-age constraints).
- [ ] Add global and per-profile exclusions.

## Phase 5 - UX and Trust
- [ ] Build dashboard with reclaimable storage and top categories.
- [ ] Show explainability for each result (why listed and impact).
- [ ] Implement dry-run mode.
- [ ] Implement Quick Clean mode (low risk only).
- [ ] Implement Deep Clean mode (explicit warnings + confirmations).

## Phase 6 - Performance and Reliability
- [ ] Add incremental scan metadata cache.
- [ ] Add progress updates and cancellation support.
- [ ] Handle symlinks, package bundles, and permission failures safely.
- [ ] Benchmark large directories and optimize hotspots.
- [ ] Add reliability tests for interrupted scans.

## Phase 7 - QA, Security, Release
- [ ] Add unit tests for path safety and risk labeling.
- [ ] Add integration tests with seeded junk datasets.
- [ ] Add regression tests for protected path enforcement.
- [ ] Complete code signing, hardened runtime, and notarization.
- [ ] Add diagnostics export bundle for support.
