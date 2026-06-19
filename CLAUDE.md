# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: Pare (Pure Swift)

macOS 13+ disk cleanup tool with three targets sharing a single core library.

## Stack

Swift 5.9 | SwiftUI + AppKit | Swift Package Manager | XCTest | macOS 13+

## Architecture

```
Sources/
  PareCore/       # Library — no UI dependencies
    Models/             # ScanFinding, ScanReport, ScanCategory, RiskLevel
    Scanning/           # ScanRule protocol, ScanRunner, FileSystemTraversal, RuleCatalog, ScanPolicy, FileSystemUtils
    Rules/              # One file per ScanRule implementation
    Cleanup/            # CleanupEngine (actor), CleanupTransaction, ExclusionList
    ScanReportAnnotator.swift  # App-to-findings attribution (sourceApp, appRollups, TopFile)
  PareApp/        # SwiftUI macOS app target
    ViewModels/         # ScanDashboardViewModel (@MainActor ObservableObject)
    Views/              # ScanDashboardView + Components/
    Theme/              # AppTheme
  PareCLI/        # CLI diagnostic runner — secondary tool for fast testing only
    main.swift          # @main struct, argparse, formatted output
Tests/
  PareCoreTests/  # XCTest — ScanRunnerTests, ScanIntegrationTests,
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

**ScanProfile / RuleCatalog** — four profiles (`baseline`, `developer`, `designer`, `video-builder`) exist for the CLI. The SwiftUI app uses `RuleCatalog.all`, which unions all profiles (20 unique rules, deduplicated by rule ID) so every category is always scanned in one pass. There is no profile picker in the app.

**ScanPolicy** — static guardrail layer shared by scanning and cleanup. Defines protected/sensitive path markers, app-state-sensitive paths (VS Code settings, SSH keys, and all major JetBrains IDEs: IntelliJ, PyCharm, WebStorm, PhpStorm, Rider, CLion, RubyMine, Android Studio, Fleet, Aqua, DataSpell, RustRover), persona path markers, per-category minimum ages (logs: 1 day; build artifacts: none; caches: 3 days default), and the large-file threshold (50 MB). Every path must pass `isLowImpactPath`, `matchesPersonaPath`, or `isWrongPlatformBinary` before it can be cleaned. `isWrongPlatformBinary` is a narrow bypass for Windows/Linux binaries at the top level of `~/Downloads` only. `effectiveAgeDate(from:)` returns the oldest of creation/modification date for directories so that JetBrains migration activity (which resets mtime) cannot defeat the age gate.

**CleanupEngine (actor)** — `quickClean` (safe only), `deepClean` (safe + review, requires `confirmed: true`), `clean` (generic). Always moves to Trash (never permanent delete). Re-verifies ScanPolicy on every item at cleanup time as a belt-and-suspenders check. Persists `CleanupTransaction` JSON records to `~/Library/Application Support/Pare/transactions/` for undo/restore.

**ExclusionList** — user-defined path exclusions (prefix or exact). Loaded by `ScanRunner` and checked after rule matching; persisted to `~/Library/Application Support/Pare/exclusions.json`.

**ScanReportAnnotator** — maps `ScanFinding` paths to source apps (`sourceApp(for:)`) using ordered path-pattern matching plus reverse-DNS bundle ID extraction from `~/Library/Caches/`. `appRollups(from:)` returns per-app totals with the top 10 files ≥ 1 MB each; apps below 1 MB total are folded into "Other".

## Verification (after any code change)

```bash
make build        # must compile clean
make test         # must pass
make run-app      # launch the SwiftUI app and exercise the changed feature manually
```

## Priorities

**The SwiftUI app (`PareApp`) is the primary deliverable.** The CLI is a secondary diagnostic/fast-testing tool. When implementing features, focus on the app experience first. CLI updates are optional and only warranted when trivial (e.g. already using a shared core utility).

## Conventions

- New scan rules go in `Sources/PareCore/Rules/` and must be registered in `RuleCatalog`.
- Rules that need sibling-directory comparison (e.g. version deduplication) implement `customScan` instead of `include`.
- `ScanPolicy` is the only place path safety logic lives — never inline path checks in rules or the engine.
- Shared filesystem utilities (e.g. `directorySize`) live in `FileSystemUtils` — don't duplicate them in individual rules.
- `CleanupEngine` is an `actor`; `ScanDashboardViewModel` is `@MainActor`. All core types are `Sendable`.
- Tests use `MockTraversal: FileTraversing` and `TestRule: ScanRule` to inject deterministic file lists without hitting the filesystem.

## Known State

See `docs/checklist.md` for phase completion status. Phases 1–6 are complete. Phase 7 (code signing/notarization) remains open.

The app runs a single unified scan using `RuleCatalog.all`; the CLI retains profile-based scanning. Parallel rule execution was attempted and reverted — Swift 5.9 nested `withTaskGroup` + actor calls caused empty results. The sequential `runRule` loop is the stable approach; `CachedFileTraversal` already parallelises I/O within each individual rule call.

`JetBrainsStaleVersionRule` risk level is `.safe` (older duplicate IDE versions are safe to auto-remove). Its 90-day age gate uses `ScanPolicy.effectiveAgeDate` (oldest of creation/mtime) so that JetBrains migration activity — which updates a settings directory's mtime to today — cannot hide a genuinely stale version. `LogsAndCrashReportsRule` applies a 1-day minimum age gate so fresh logs are never flagged. `XcodeSimulatorCachesRule` targets only `CoreSimulator/Caches` (not `Devices`) to avoid touching active simulator data. `ScanReportAnnotator` filters generic component names (app, helper, daemon, etc.) from app attribution to reduce noise.

`WrongPlatformBinariesRule` (developer profile) detects two kinds of non-macOS content: `.exe`/`.msi`/`.dll`/`.deb`/`.rpm`/`.AppImage` files at the top level of `~/Downloads` (`.review`, `downloadsMinBytes` = 512 KB threshold), and `win/`/`linux/`/`win32/`/etc. native plugin stub directories inside JetBrains plugin trees (`.review`, `.developerPackageCaches`). These are never executable on macOS. Extension sets (`windowsExecutableExtensions`, `linuxExecutableExtensions`) are defined once in `ScanPolicy` and referenced by the rule to avoid duplication. The wrong-platform bypass in `CleanupEngine` is anchored to `~/Downloads` top-level only — project `downloads/` subdirectories are not matched. Wrong-platform binaries are exempt from the category-level minimum age gate (they are inert from day zero).

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **pare** (351 symbols, 338 relationships, 0 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## When Debugging

1. `gitnexus_query({query: "<error or symptom>"})` — find execution flows related to the issue
2. `gitnexus_context({name: "<suspect function>"})` — see all callers, callees, and process participation
3. `READ gitnexus://repo/pare/process/{processName}` — trace the full execution flow step by step
4. For regressions: `gitnexus_detect_changes({scope: "compare", base_ref: "main"})` — see what your branch changed

## When Refactoring

- **Renaming**: MUST use `gitnexus_rename({symbol_name: "old", new_name: "new", dry_run: true})` first. Review the preview — graph edits are safe, text_search edits need manual review. Then run with `dry_run: false`.
- **Extracting/Splitting**: MUST run `gitnexus_context({name: "target"})` to see all incoming/outgoing refs, then `gitnexus_impact({target: "target", direction: "upstream"})` to find all external callers before moving code.
- After any refactor: run `gitnexus_detect_changes({scope: "all"})` to verify only expected files changed.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Tools Quick Reference

| Tool | When to use | Command |
|------|-------------|---------|
| `query` | Find code by concept | `gitnexus_query({query: "auth validation"})` |
| `context` | 360-degree view of one symbol | `gitnexus_context({name: "validateUser"})` |
| `impact` | Blast radius before editing | `gitnexus_impact({target: "X", direction: "upstream"})` |
| `detect_changes` | Pre-commit scope check | `gitnexus_detect_changes({scope: "staged"})` |
| `rename` | Safe multi-file rename | `gitnexus_rename({symbol_name: "old", new_name: "new", dry_run: true})` |
| `cypher` | Custom graph queries | `gitnexus_cypher({query: "MATCH ..."})` |

## Impact Risk Levels

| Depth | Meaning | Action |
|-------|---------|--------|
| d=1 | WILL BREAK — direct callers/importers | MUST update these |
| d=2 | LIKELY AFFECTED — indirect deps | Should test |
| d=3 | MAY NEED TESTING — transitive | Test if critical path |

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/pare/context` | Codebase overview, check index freshness |
| `gitnexus://repo/pare/clusters` | All functional areas |
| `gitnexus://repo/pare/processes` | All execution flows |
| `gitnexus://repo/pare/process/{name}` | Step-by-step execution trace |

## Self-Check Before Finishing

Before completing any code modification task, verify:
1. `gitnexus_impact` was run for all modified symbols
2. No HIGH/CRITICAL risk warnings were ignored
3. `gitnexus_detect_changes()` confirms changes match expected scope
4. All d=1 (WILL BREAK) dependents were updated

## Keeping the Index Fresh

After committing code changes, the GitNexus index becomes stale. Re-run analyze to update it:

```bash
npx gitnexus analyze
```

If the index previously included embeddings, preserve them by adding `--embeddings`:

```bash
npx gitnexus analyze --embeddings
```

To check whether embeddings exist, inspect `.gitnexus/meta.json` — the `stats.embeddings` field shows the count (0 means no embeddings). **Running analyze without `--embeddings` will delete any previously generated embeddings.**

> Claude Code users: A PostToolUse hook handles this automatically after `git commit` and `git merge`.

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
