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

**ScanProfile / RuleCatalog** — four profiles (`baseline`, `developer`, `designer`, `video-builder`) exist for the CLI. The SwiftUI app uses `RuleCatalog.all`, which unions all profiles (**48 unique rules**, deduplicated by rule ID) so every category is always scanned in one pass. There is no profile picker in the app. `FullDiskAccessChecker` heuristics surface first-run coaching when protected Library paths are unreadable.

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

**Command Line Tools-only machines (no Xcode.app):** `make build` and `make run-app` work, but `make test` fails with `no such module 'XCTest'` because Apple's Command Line Tools ship neither XCTest nor swift-testing's `Testing` module. This is an environment limitation, not a regression. On CLT-only machines the Makefile also pins `SDKROOT` to `MacOSX26.sdk` when present, because the macOS 27 SDK turns `@State` into a macro whose plugin ships only with Xcode. Plain `swift build` needs `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk`. To run tests locally, install Xcode or a swift.org toolchain (e.g. via `swiftly`), which bundles XCTest; otherwise rely on CI (`macos-26` runner with Xcode).

**Dev signing (`scripts/sign-app.sh`):** `make run-app` signs the bundle after assembling it. An ad-hoc signature's designated requirement is just the cdhash, so it changes on every rebuild and macOS drops the app's Full Disk Access grant with it. Signing with a real certificate (Developer ID first, else Apple Development; override with `SIGN_IDENTITY`) plus `--identifier com.yudgnahk.pare` yields an identifier + anchor requirement that is stable across rebuilds, so FDA only needs granting once. With no identity available the ad-hoc signature is kept and the script says so; if signing fails it re-applies ad-hoc so the bundle still launches.

## Priorities

**The SwiftUI app (`PareApp`) is the primary deliverable.** The CLI is a secondary diagnostic/fast-testing tool. When implementing features, focus on the app experience first. CLI updates are optional and only warranted when trivial (e.g. already using a shared core utility).

## Conventions

- New scan rules go in `Sources/PareCore/Rules/` and must be registered in `RuleCatalog`.
- Rules that need sibling-directory comparison (e.g. version deduplication) implement `customScan` instead of `include`.
- `ScanPolicy` is the only place path safety logic lives — never inline path checks in rules or the engine.
- Shared filesystem utilities (e.g. `directorySize`) live in `FileSystemUtils` — don't duplicate them in individual rules.
- `CleanupEngine` is an `actor`; `ScanDashboardViewModel` is `@MainActor`. All core types are `Sendable`.
- Tests use `MockTraversal: FileTraversing` and `TestRule: ScanRule` to inject deterministic file lists without hitting the filesystem.
- SwiftUI previews use `struct <Name>_Previews: PreviewProvider`, never the `#Preview` macro. The macro needs the `PreviewsMacros` compiler plugin that only ships inside Xcode.app, so `swift build` breaks on Command Line Tools-only machines. The same applies to any other SwiftUI macro (`@Entry`, `@Animatable`) — avoid them.
- Wrap preview structs — and any helper type that exists only to back a preview — in `#if DEBUG` / `#endif` so they stay out of release builds.
- SPM resource bundles go in `Contents/Resources/` when assembling the `.app` (both `make run-app` and `scripts/release.sh`). `Contents/MacOS/` is **not** a path `ResourceBundle` searches.
- Read PareCore resources through `ResourceBundle.pareCore`, never `Bundle.module` — the generated accessor calls `fatalError` when the bundle is missing, which crashes a scan instead of degrading.

## Known State

See `docs/roadmap.md` for phase completion status. Phases 0–8 and 11 are complete. Phase 9 (code signing, notarization, distribution), Phase 10 (selective Docker manager) and Phase 12 follow-ups remain open.

The app runs a single unified scan using `RuleCatalog.all`; the CLI retains profile-based scanning. Parallel rule execution was attempted and reverted — Swift 5.9 nested `withTaskGroup` + actor calls caused empty results. The sequential `runRule` loop is the stable approach; `CachedFileTraversal` already parallelises I/O within each individual rule call.

`JetBrainsStaleVersionRule` risk level is `.safe` (older duplicate IDE versions are safe to auto-remove). Its 90-day age gate uses `ScanPolicy.effectiveAgeDate` (oldest of creation/mtime) so that JetBrains migration activity — which updates a settings directory's mtime to today — cannot hide a genuinely stale version. `LogsAndCrashReportsRule` applies a 1-day minimum age gate so fresh logs are never flagged. `XcodeSimulatorCachesRule` targets only `CoreSimulator/Caches` (not `Devices`) to avoid touching active simulator data. `ScanReportAnnotator` filters generic component names (app, helper, daemon, etc.) from app attribution to reduce noise.

**Explain-only diagnostics:** `ScanCategory.diagnostics` findings are `.advanced` with `FindingAnnotation.explainOnly(action:)`; they show size and what to do, are excluded from reclaimable totals, and `CleanupEngine` blocks the category whatever its risk label. `DeletedOpenFilesRule` (one `lsof +L1` run, deduped by device+inode, one finding per holding command ≥ 10 MB, "restart X"), `SwapUsageRule` (`sysctl vm.swapusage`, > 1 GB, path `/private/var/vm`), `MemoryPressureRule` (`JetsamEvent-*.ips` within 7 days, read newest first up to a 64 MB byte budget, `maxBytesInspected`, after which the shortage count is a floor; reports only system-wide shortage kill reasons, never `per-process-limit`; size 0; warns when low disk coincides with high swap), `LaunchdRestartLoopRule` (read-only `launchctl print gui/<uid>`, then per candidate label, ≤ 20 calls; `runs` > 1000 with a non-zero last exit or a terminating signal) and `TinyFileQueueRule` (≥ 100k direct-child files, ≥ 90 % under 4 KB, allocated ≥ 4× logical, newest > 30 days; App Support, Caches and `~` dot dirs to depth 3; cheap entry count first, full stats only for candidates, 3M-entry budget, 5 s per folder) are in the baseline profile.

**Upgrade backups (`.review`, never `.safe`):** `StaleUpgradeBackupsRule` walks `~` dot directories and `~/Library/Application Support/*` (depth ≤ 4, 20k entries) for names with a whole `backup`/`bak`/`upgrade`/`migrat*`/`schema` token plus a version or timestamp. `ScanPolicy.isReclaimableUpgradeBackup` requires ≥ 30 days old, a live sibling written after it, and a newer backup of the same store (the newest is always kept); `CleanupEngine` admits backup-named paths only through that predicate.

**Codex staging leftovers:** `CodexStagingRule` (`.safe`, `.aiToolCaches`) reports direct children of exactly `~/.codex/.tmp/bundled-marketplaces` and `~/.codex/.tmp/marketplaces/.staging` named `openai-bundled.staging-*`, `marketplace-upgrade-*` or `marketplace-add-*` (never `marketplace-backup-*`), untouched > 30 days, no symlinks, and nothing while Codex or ChatGPT runs (exact process names / bundle ids). One finding per folder, rolled up to one row per root; `CleanupEngine` re-checks `ScanPolicy.isReclaimableCodexStagingEntry` and the running check, and never trashes a root.

**Old pnpm stores (`.review`):** `PnpmOldStoreRule` (developer profile) asks `pnpm store path` for the active `…/store/v<N>` (pnpm found via PATH, `PNPM_HOME`, `~/Library/pnpm`, `~/.local/share/pnpm`; nothing reported when pnpm is absent) and offers sibling `v<M>` folders with M < N as whole folders. The broad `/library/pnpm` persona marker would admit any store version, so `CleanupEngine` lets `…/pnpm/store/v<N>` paths through only `ScanPolicy.isReclaimableOldPnpmStore`, with the active store re-resolved per batch (unknown = refuse).

**Dependency folders of inactive projects (`.review`):** `ProjectDependenciesRule` (developer profile) walks confirmed and manual project roots (depth 8, entry and time budget) for `node_modules`/`venv`/`.venv`/`.bundle` beside a matching lockfile, never under a `Library` component or inside a `.app`, sized with `directorySizeResult`. `ScanPolicy.isReclaimableProjectDependency` needs the project idle for its disk-pressure tier (14/7/3 days, never under 72 h; tier read through `VolumeFreeSpaceProviding`), judged by the newest file edit in a bounded walk that skips dependency and build folders (budget exhausted = active). `CleanupEngine` runs it as a mandatory arm after the pnpm arm, adds git evidence (only `.ignoredUntracked` or `.notInRepository`), checks the project root for open files and refuses when the open-file snapshot is unavailable.

**Growth snapshots:** each scan saves a `GrowthSnapshot` (per category, plus reclaimable paths ≥ 10 MB; last 30 in `Application Support/Pare/growth`) for the "Grew since last scan" line; only complete scans (no failed or stopped rules, unreadable locations or cut-short sizes) are a baseline.

**Cache activity labels:** display-only "Written to recently / Last written N days ago / Last write unknown" on the shown largest items, from newest write dates; never changes risk or selection. Growth and labels run as concurrent jobs after results appear, dropped if a newer scan started.

**Docker safety:** `Docker.raw` / `…/data/vms/…` is **not** a normal cache and is **not** shown as a scan finding. Cleanup path-blocks that tree; Maintenance runs `docker system prune -f` only (no `--volumes`). See `docs/features/docker-safety.md`.

Reconstructible package/toolchain caches are reported as **whole folders** with no multi-day age gate (`ScanPolicy.reconstructibleCacheMinAgeSeconds` = 0): `~/.npm/_npx` (per extract), `~/.npm/_cacache`, Yarn/pnpm/CocoaPods/SwiftPM/Bun, Cargo registry/git, rustup downloads, Homebrew cache, AI tool caches (e.g. OpenCode). Wrong-platform native folders are only scanned under installed editor/IDE trees (not under fully reclaimable package caches) to avoid double-counting.

**Go caches are a working set (report-only):** `GoCachesRule` reports `GOCACHE` (`~/Library/Caches/go-build`) and the whole `GOMODCACHE` (`~/go/pkg/mod`) as `.advanced` findings with `FindingAnnotation.workingSet(selfTrimDays:)` (build cache: 5 days, module cache: nil — Go never trims it); they are excluded from reclaimable totals. `ScanPolicy.isNeverCleanPath` (`ScanPolicy+NeverClean.swift`) denies those trees by path-component sequence anywhere, plus the custom locations `go env GOCACHE GOMODCACHE` reports (`GoCacheLocations`, resolved once, non-fatal when `go` is absent). It runs first in `isLowImpactPath`, `matchesPersonaPath` and `isReconstructibleCachePath`, and `CleanupEngine` skips matches with `.workingSetProtected` before any allow-list. Go toolchains under `golang.org/toolchain@*` are out of scope.

**uv cache (report-only, Phase A):** `UvCacheRule` discovers uv's cache via `CacheRootResolver` — platform cache root (Foundation `.cachesDirectory`), XDG root (`XDG_CACHE_HOME` absolute-only, else `~/.cache`), `UV_CACHE_DIR`, and `uv cache dir` (timeout-bounded, non-fatal, skipped when uv is absent) — canonicalized and deduplicated, one whole-folder finding per physical root. Findings are `.advanced` so `CleanupEngine` hard-blocks Trash deletion; reclaim arrives in Phase B as a native `uv cache prune/clean` Maintenance action. `~/.cache/uv` is deliberately **not** in `developerPackageCacheMarkers` or `reconstructibleCachePathMarkers`; new cache policies use exact `ScanPolicy.isEqualToOrDescendant(candidate:root:)` component matching, never `path.contains` (which would match `uvicorn`/`uv-backup`). `ToolCacheDescriptor` carries relative child names + discovery/cleanup metadata for uv, pip, Poetry, pyenv (only uv is wired to a rule so far). uv is excluded from `PythonCachesRule` and `UserCachesRule` so no `.safe` finding can double-report it.

`WrongPlatformBinariesRule` (developer profile) detects non-macOS content as **whole folders** when possible: (1) `.exe`/`.msi`/`.dll`/`.deb`/`.rpm`/`.AppImage` files at the top level of `~/Downloads` (`.safe`, `downloadsMinBytes` = 512 KB); (2) multi-platform native trees under npm/npx, Yarn, pnpm, Bun, VS Code/Cursor/Windsurf extensions, and JetBrains — e.g. `win32/`, `linux/`, `win32-x64/`, `linux-arm64/` reported as one finding each (`.safe`, `.developerPackageCaches`), not individual `*.dll` files. Simple names (`win32`, `linux`) require a macOS sibling (`darwin`/`macos`/…) except under JetBrains plugins; compound names (`win32-x64`) always match. `PackageManagerCachesRule` skips files under those platform dirs to avoid double-counting. Platform name sets and scan roots live in `ScanPolicy`. `CleanupEngine` uses `isWrongPlatformPath` (downloads top-level **or** under a non-mac platform dir) for path allow + age exemption.

**UI redesign (Phases 1–3, see `docs/roadmap.md` Phase 11):** every `AppTheme` color is now an adaptive `ThemeSwatch` (light + dark hex) resolved via `NSColor(name:dynamicProvider:)`, gated by `ThemeContrastTests`'s WCAG contrast checks (`ThemeSwatch.swift`, `WCAG.contrastRatio`). Each `ScanCategory` and sidebar `AppDestination` has one `CategoryStyle`/`DestinationStyle` swatch + SF Symbol, rendered by the shared `IconTile` squircle component (18/22/28/56 pt sizes); the sidebar uses `SidebarMaterial` (`NSVisualEffectView` `.sidebar`/`.behindWindow`) with a faint accent tint instead of a solid fill. The Disk Analyzer's "Add to Review" only accepts items a Smart Scan finding actually covers — `DiskReviewResolver.resolve` matches via `ScanPolicy.isCanonicallyEqualToOrDescendant` (case-insensitive component matching, with `/tmp`/`/var`/`/etc` mapped to their `/private` spelling by `ScanPolicy.canonicalPathURL`) against the latest scan's findings (`.covered`/`.insideFinding`/`.notCandidate`/`.noScan`) — and every add flows tray → `CleanupCoordinator` → `CleanupEngine`; there is no direct-delete path (the old `FileManager.trashItem` hover button was removed as a safety fix folded into this redesign).

**UI wow pass (Phase 11.4, `docs/design/ui-wow-audit.md`):** "Tidewater" direction — seafoam primary, apricot (`AppTheme.warm`/`warmText`) marks reclaimable space only. Looping or travelling motion must go through `MotionPolicy`/`motionAwareAnimation` so Reduce Motion is honoured. Smart Scan clean actions live in the floating `CleanActionBar` and still open `CleanConfirmationSheet`. To render screens without screen-recording permission: `make build && PARE_SNAPSHOT_DIR=<dir> [PARE_SNAPSHOT_ONLY=01,03] .build/debug/PareApp` (DEBUG only; scenes in `Sources/PareApp/Debug/SnapshotRenderer.swift`, canned data in `SnapshotFixtures`; run outside the sandbox).

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **pare** (876 symbols, 882 relationships, 0 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

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
