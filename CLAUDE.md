# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: App B (Pure Swift)

macOS 13+ disk cleanup tool with three targets sharing a single core library.

## Stack

Swift 5.9 | SwiftUI + AppKit | Swift Package Manager | XCTest | macOS 13+

## Architecture

```
Sources/
  App BCore/       # Library — no UI dependencies
    Models/             # ScanFinding, ScanReport, ScanCategory, RiskLevel
    Scanning/           # ScanRule protocol, ScanRunner, FileSystemTraversal, RuleCatalog, ScanPolicy
    Rules/              # One file per ScanRule implementation
    Cleanup/            # CleanupEngine (actor), CleanupTransaction, ExclusionList
  PareApp/        # SwiftUI macOS app target
    ViewModels/         # ScanDashboardViewModel (@MainActor ObservableObject)
    Views/              # ScanDashboardView + Components/
    Theme/              # AppTheme
  App BCLI/        # CLI diagnostic runner
    main.swift          # @main struct, argparse, formatted output
Tests/
  App BCoreTests/  # XCTest — ScanRunnerTests, ScanIntegrationTests,
                        #          CleanupEngineTests, ExclusionListTests
```

## Commands

```bash
make build                          # swift build
make test                           # swift test
make start                          # baseline profile scan via CLI
make run-app                        # launch SwiftUI app
make run PROFILE=developer TOP=50   # profiles: baseline|developer|designer|video-builder
swift test --filter ScanRunnerTests # run a single test class
```

## Core Concepts

**ScanRule protocol** — each rule declares `targetDirectories`, an `include` predicate for per-file matching, and an optional `customScan` for directory-level reasoning (bypasses the traversal loop). All rules are `Sendable`.

**RiskLevel** — `safe` (auto-deletable), `review` (warn user), `advanced` (detect/report only; CleanupEngine hard-blocks deletion).

**ScanProfile / RuleCatalog** — four profiles (`baseline`, `developer`, `designer`, `video-builder`). Each profile extends baseline. `RuleCatalog` is the single source of truth for which rules belong to which profile.

**ScanPolicy** — static guardrail layer shared by scanning and cleanup. Defines protected/sensitive path markers, app-state-sensitive paths (VS Code settings, JetBrains prefs, SSH keys), persona path markers, minimum cache age (3 days), and the large-file threshold (50 MB). Every path must pass `isLowImpactPath` or `matchesPersonaPath` before it can be cleaned.

**CleanupEngine (actor)** — `quickClean` (safe only), `deepClean` (safe + review, requires `confirmed: true`), `clean` (generic). Always moves to Trash (never permanent delete). Re-verifies ScanPolicy on every item at cleanup time as a belt-and-suspenders check. Persists `CleanupTransaction` JSON records to `~/Library/Application Support/App B/transactions/` for undo/restore.

**ExclusionList** — user-defined path exclusions (prefix or exact). Loaded by `ScanRunner` and checked after rule matching; persisted to `~/Library/Application Support/App B/exclusions.json`.

## Conventions

- New scan rules go in `Sources/App BCore/Rules/` and must be registered in `RuleCatalog`.
- Rules that need sibling-directory comparison (e.g. version deduplication) implement `customScan` instead of `include`.
- `ScanPolicy` is the only place path safety logic lives — never inline path checks in rules or the engine.
- `CleanupEngine` is an `actor`; `ScanDashboardViewModel` is `@MainActor`. All core types are `Sendable`.
- Tests use `MockTraversal: FileTraversing` and `TestRule: ScanRule` to inject deterministic file lists without hitting the filesystem.

## Known State

See `docs/checklist.md` for phase completion status. Phase 6 (incremental scan cache, benchmarking) and Phase 7 (code signing/notarization) are incomplete.
