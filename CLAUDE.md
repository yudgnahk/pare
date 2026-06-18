# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: CleanMyMac (Pure Swift)

macOS 13+ disk cleanup tool with three targets sharing a single core library.

## Stack

Swift 5.9 | SwiftUI + AppKit | Swift Package Manager | XCTest | macOS 13+

## Architecture

```
Sources/
  CleanMyMacCore/       # Library — no UI dependencies
    Models/             # ScanFinding, ScanReport, ScanCategory, RiskLevel
    Scanning/           # ScanRule protocol, ScanRunner, FileSystemTraversal, RuleCatalog, ScanPolicy
    Rules/              # One file per ScanRule implementation
    Cleanup/            # CleanupEngine (actor), CleanupTransaction, ExclusionList
    ScanReportAnnotator.swift  # App-to-findings attribution (sourceApp, appRollups, TopFile)
  CleanMyMacApp/        # SwiftUI macOS app target
    ViewModels/         # ScanDashboardViewModel (@MainActor ObservableObject)
    Views/              # ScanDashboardView + Components/
    Theme/              # AppTheme
  CleanMyMacCLI/        # CLI diagnostic runner — secondary tool for fast testing only
    main.swift          # @main struct, argparse, formatted output
Tests/
  CleanMyMacCoreTests/  # XCTest — ScanRunnerTests, ScanIntegrationTests,
                        #          CleanupEngineTests, ExclusionListTests
```

## Commands

```bash
make build                          # swift build
make test                           # swift test
make start                          # baseline profile scan via CLI
make run-app                        # launch SwiftUI app (runs unified scan — all rules)
make run PROFILE=developer TOP=50   # CLI only: profiles: baseline|developer|designer|video-builder
swift test --filter ScanRunnerTests # run a single test class
```

## Core Concepts

**ScanRule protocol** — each rule declares `targetDirectories`, an `include` predicate for per-file matching, and an optional `customScan` for directory-level reasoning (bypasses the traversal loop). All rules are `Sendable`.

**RiskLevel** — `safe` (auto-deletable), `review` (warn user), `advanced` (detect/report only; CleanupEngine hard-blocks deletion).

**ScanProfile / RuleCatalog** — four profiles (`baseline`, `developer`, `designer`, `video-builder`) exist for the CLI. The SwiftUI app uses `RuleCatalog.all`, which unions all profiles (19 unique rules, deduplicated by rule ID) so every category is always scanned in one pass. There is no profile picker in the app.

**ScanPolicy** — static guardrail layer shared by scanning and cleanup. Defines protected/sensitive path markers, app-state-sensitive paths (VS Code settings, JetBrains prefs, SSH keys), persona path markers, minimum cache age (3 days), and the large-file threshold (50 MB). Every path must pass `isLowImpactPath` or `matchesPersonaPath` before it can be cleaned.

**CleanupEngine (actor)** — `quickClean` (safe only), `deepClean` (safe + review, requires `confirmed: true`), `clean` (generic). Always moves to Trash (never permanent delete). Re-verifies ScanPolicy on every item at cleanup time as a belt-and-suspenders check. Persists `CleanupTransaction` JSON records to `~/Library/Application Support/CleanMyMac/transactions/` for undo/restore.

**ExclusionList** — user-defined path exclusions (prefix or exact). Loaded by `ScanRunner` and checked after rule matching; persisted to `~/Library/Application Support/CleanMyMac/exclusions.json`.

**ScanReportAnnotator** — maps `ScanFinding` paths to source apps (`sourceApp(for:)`) using ordered path-pattern matching plus reverse-DNS bundle ID extraction from `~/Library/Caches/`. `appRollups(from:)` returns per-app totals with the top 10 files ≥ 1 MB each; apps below 1 MB total are folded into "Other".

## Verification (after any code change)

```bash
make build        # must compile clean
make test         # must pass
make run-app      # launch the SwiftUI app and exercise the changed feature manually
```

## Priorities

**The SwiftUI app (`CleanMyMacApp`) is the primary deliverable.** The CLI is a secondary diagnostic/fast-testing tool. When implementing features, focus on the app experience first. CLI updates are optional and only warranted when trivial (e.g. already using a shared core utility).

## Conventions

- New scan rules go in `Sources/CleanMyMacCore/Rules/` and must be registered in `RuleCatalog`.
- Rules that need sibling-directory comparison (e.g. version deduplication) implement `customScan` instead of `include`.
- `ScanPolicy` is the only place path safety logic lives — never inline path checks in rules or the engine.
- `CleanupEngine` is an `actor`; `ScanDashboardViewModel` is `@MainActor`. All core types are `Sendable`.
- Tests use `MockTraversal: FileTraversing` and `TestRule: ScanRule` to inject deterministic file lists without hitting the filesystem.

## Known State

See `docs/checklist.md` for phase completion status. Phases 1–6 are complete. Phase 7 (code signing/notarization) remains open.

The app runs a single unified scan using `RuleCatalog.all`; the CLI retains profile-based scanning. Parallel rule execution was attempted and reverted — Swift 5.9 nested `withTaskGroup` + actor calls caused empty results. The sequential `runRule` loop is the stable approach; `CachedFileTraversal` already parallelises I/O within each individual rule call.
