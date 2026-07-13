# Pare — Full Project Review

**Date:** 2026-07-13  
**Branch reviewed:** `phase-9-app-icon` (+ uncommitted local fixes; see §11)  
**Scope:** Architecture, scan correctness, safety, UI/UX, tests, docs drift, distribution  
**Mode:** Review only — no product code changes for this document  

---

## 1. Executive summary

Pare is a solid, phased macOS cleanup product: clear core/app/CLI split, strong safety model (`ScanPolicy` + `CleanupEngine` re-checks + Trash-only), and broad rule coverage for developer/designer workflows.

**Overall health:** **Good foundation, not ship-clean yet.**

| Area | Grade | Notes |
|------|-------|--------|
| Architecture | B+ | Clean layers; a few dual systems and dead surfaces |
| Scan correctness | B | Recent size/hang fixes good; still UX/perf gaps |
| Safety / cleanup | A− | Advanced hard-blocked; age gates; policy re-check |
| UI / product polish | B− | Misleading claims, dead UI, no real scan progress |
| Tests | B | ~301 tests; **2 currently failing** (catalog drift) |
| Docs / changelog | C+ | Counts and features out of date vs code |
| Distribution (Phase 9) | C | Scripts exist; signing/notarization/Gatekeeper still open |

**Top three risks if you ship tomorrow**

1. **Stale catalog tests fail** — CI/local `make test` is red on catalog assertions.  
2. **Scan UX still all-or-nothing** — no per-rule progress; long scans feel “stuck.”  
3. **Docs claim features that aren’t true** (real-time progress, Project Roots card on dashboard, rule counts).

---

## 2. What Pare is (as implemented)

```
Sources/
  PareCore/     Library: models, rules, scan, cleanup, app/homebrew/maintenance
  PareApp/      SwiftUI app — primary product (TabView: Scan, Apps, Homebrew, Disk, Maintenance, History)
  PareCLI/      Diagnostic CLI — profile-based scans (baseline | developer | designer | video-builder)
```

- **App** always runs `RuleCatalog.all` (union of profiles, deduped by rule id).  
- **CLI** uses per-profile catalogs.  
- **Cleanup** always moves to Trash; undo via transactions under `~/Library/Application Support/Pare/transactions/`.  
- **Not sandboxed** — Full Disk Access recommended; privacy strings for Desktop/Documents/Downloads in `scripts/AppInfo.plist`.

---

## 3. Architecture strengths

1. **Clear domain split** — scanning and cleanup live in PareCore with no UI deps.  
2. **`ScanRule` protocol** — `targetDirectories` + `include`, or `customScan` for directory-level logic.  
3. **Centralized safety** — `ScanPolicy` is the intended single place for path/age gates.  
4. **Risk model** — `.safe` / `.review` / `.advanced` with CleanupEngine hard-block on advanced.  
5. **Incremental scan cache** — `ScanMetadataCache` + `CachedFileTraversal` (mtime-based).  
6. **Persona breadth** — Xcode, VS Code, JetBrains, Docker, polyglot caches, browsers, productivity apps.  
7. **Secondary tools** — App Manager, Homebrew Manager, Disk Analyzer, Maintenance, History are real features, not stubs.

---

## 4. Issues by severity

### 4.1 Critical / high (correctness & trust)

#### H1 — Reclaimable totals and sparse files (recently fixed, uncommitted)

| | |
|--|--|
| **Symptom** | Hero total ~1.13 TB on a ~256 GB disk |
| **Cause** | (1) Docker.raw logical size via `attributesOfItem[.size]`; (2) `.advanced` included in summaries |
| **Status** | **Fixed in working tree** (not committed): allocated size in `FileSystemUtils` / `DockerStorageRule`; `ScanRunner` excludes advanced from reclaimable aggregation |
| **Verify** | Developer CLI should report ~tens of GB reclaimable; Docker.raw ~20 GB ADVANCED, not in total |
| **Origin** | PR #14 re-added Docker.raw; Phase 1 totals never filtered by risk |

#### H2 — Scan hang on Spotlight project discovery (recently fixed, uncommitted)

| | |
|--|--|
| **Symptom** | App/developer scan never finished; no results |
| **Cause** | `SpotlightQueryRunner` used `[weak self]` with no retention → continuation never resumed |
| **Status** | **Fixed in working tree** (not committed): self-retain until `finish()` |
| **Verify** | `testDiscoverCompletesWithoutHanging`; developer CLI completes in ~20s |

#### H3 — Failing tests (catalog drift)

```
testBaselineRuleIncludesKnownRules — expected 8 rules, actual 12
testDeveloperRuleCatalogIncludesPersonaRules — expects id "docker-logs-review-required" (not in catalog)
```

Full suite: **301 executed, 2 failures** (as of this review).  
These are assertion drift after Phase 6–8 rule growth, not necessarily runtime bugs — but **`make test` is red**.

---

### 4.2 Medium (product, maintainability, correctness edge cases)

#### M1 — Dual project-root systems

| System | Rule | Config UI |
|--------|------|-----------|
| Phase 5 | `ProjectArtifactRule` (`project-artifacts`) | Header → `ProjectScanPathsView` / `ProjectScanPathStore` |
| Phase 6 | `ProjectArtifactsRule` (`project-artifacts-v2`) | Was Project Roots card; **removed from dashboard** |

Both are still in `RuleCatalog` (v1 in baseline; v2 in developer/`all`).  
Phase 6 comments say v2 “replaces” v1 for developer/`all`, but **v1 remains on baseline**, so `all` still runs both.

**User impact:** Confusing dual config; artifact findings may come from either path model; manual folder button configures only Phase 5.

#### M2 — Dead / orphaned UI and rules

| Item | Status |
|------|--------|
| `ProjectRootsView.swift` + `ProjectRootsViewModel.swift` | No longer referenced from dashboard (dead UI) |
| `DockerLogsReviewRequiredRule` | Source exists; **not registered** in `RuleCatalog`; tests still expect it |
| `PareApp.swift` | Filename legacy; type is `PareApp` |

#### M3 — No real scan progress

- `ScanDashboardViewModel` only updates UI when **entire** `runner.run` finishes.  
- CHANGELOG claims “real-time progress”; code has spinner + cancel only.  
- Long `RuleCatalog.all` scans (project walks, large caches) still feel stuck even when not hung.

#### M4 — Advanced findings still dominate “Top files” / “By Tool”

- Totals correctly exclude advanced (after H1 fix).  
- Top-N and tool rollups still sort/include Docker.raw → user may still read “21 GB Docker” as cleanable unless risk badge is noticed.

#### M5 — `AppInventory` Spotlight path can double-resume

`AppInventory.discoverViaMetadataQuery` can resume the continuation from both the finish notification and a 5s timeout without a shared `finished` guard (race → crash potential). Different code path from ProjectRootDiscovery, same class of bug.

#### M6 — Project root discovery scale

On the review machine: **~495 confirmed roots**, 0 excluded.  
Artifact walks (depth 8) + `directorySize` on large trees can dominate scan time. No UI to manage roots after card removal (only file edit / future Settings).

#### M7 — Large full-tree file rules

`UserCachesRule` enumerates all of `~/Library/Caches` file-by-file then filters. Correct but expensive on large cache trees. Sequential rules re-touch overlapping trees (cache helps second pass only).

#### M8 — Parallel rule execution abandoned

Documented in `CLAUDE.md`: nested `withTaskGroup` + actors caused empty results; sequential `runRule` kept. Performance ceiling until a safe parallel strategy returns.

---

### 4.3 Low (polish, docs, consistency)

#### L1 — Documentation / marketing drift

| Claim | Reality |
|-------|---------|
| CHANGELOG “22 rules / 14 categories” | ~**36** registered constructors in `RuleCatalog`; **37** rule source files |
| CLAUDE “20 unique rules” | Under-count |
| checklist “19 rules” / “profile selector UI” | Out of date (app has no profile picker) |
| CHANGELOG “real-time progress” | Spinner only |
| CHANGELOG “Project Roots card” | Removed from Scan dashboard |
| Roadmap “coverage ≥ 80%” | Not verified in this review |
| Copyright “2025” in AppInfo.plist | Year stale |

#### L2 — Bundle / naming leftovers

- Entry file still `PareApp.swift`.  
- Roadmap still lists some Phase 0/1 checkboxes as open that may already be done (bundle id is in AppInfo.plist).

#### L3 — CLI vs app parity

CLI profiles are useful for diagnostics; app always uses `all`. Fine, but easy to mis-compare “CLI baseline is fast / empty-ish” vs “app is slow / huge.”

#### L4 — Phase 9 distribution still open

Roadmap: code signing, notarization run, staple, Gatekeeper on clean machine, GitHub v1.0.0 release — **not done**. Scripts and entitlements exist.

#### L5 — Privacy / FDA messaging

App is non-sandbox; Full Disk Access is effectively required for real results. No in-app FDA check/guidance was reviewed in depth; worth a first-run prompt before blaming “empty scan.”

---

## 5. Safety model review

**What works well**

- Advanced → `CleanupError.advancedRiskBlocked` always.  
- Quick Clean = safe only; Deep Clean = safe + review with `confirmed: true`.  
- Policy re-checked at cleanup time.  
- Age gates per category.  
- Trash + transaction undo path.

**Residual risks**

- **`.review` Deep Clean** can remove installers, browser personal data (if aged), stale app versions, device backups — confirmation copy must stay strong.  
- **Project artifacts marked `.safe`** (e.g. `node_modules`, `target`) — correct for rebuildable dirs, catastrophic if user points at wrong tree; root scoping is the control (now less visible).  
- **Orphaned Launch Agents / productivity caches** — lower risk but still user-visible side effects.

---

## 6. Test health

| Metric | Value |
|--------|--------|
| Tests executed | 301 |
| Failures | **2** (catalog assertions) |
| Strong areas | Rules unit tests (phases 1–7), cleanup engine, exclusions, VS Code dupes, stale apps |
| Gaps | No automated UI tests; little end-to-end “RuleCatalog.all on fixture home”; Spotlight/AppInventory race untested; sparse-size coverage added only in local uncommitted tests |

**Failing tests to update (when you fix, not part of this review):**

1. `ScanRunnerTests.testBaselineRuleIncludesKnownRules` → count 12 (or list all ids).  
2. `ScanRunnerTests.testDeveloperRuleCatalogIncludesPersonaRules` → expect `docker-storage` (or re-register docker-logs rule).

---

## 7. Feature surface map

| Tab | Role | Notes |
|-----|------|--------|
| Scan | Primary reclaimable UX | Unified all-rules scan; clean/undo; exclusions sheet; project paths sheet (Phase 5) |
| Apps | Inventory / uninstall leftovers | Spotlight supplement for non-standard app locations |
| Homebrew | Formulae/casks/outdated/migrate | Requires brew on PATH |
| Disk | Interactive tree | Separate from rule-based scan |
| Maintenance | One-shot system actions | DNS, Launch Services, Finder, SQLite vacuum, docker prune |
| History | Cleanup audit | JSON/CSV export |

---

## 8. Uncommitted work (as of review)

Local modifications (not committed) that address H1/H2 and UI noise:

| File | Intent |
|------|--------|
| `ProjectRootDiscovery.swift` | Spotlight continuation hang fix |
| `FileSystemUtils.swift` | Allocated size for sparse files |
| `DockerStorageRule.swift` | Use allocated size |
| `ScanRunner.swift` | Exclude advanced from reclaimable summaries |
| `ScanModels.swift` | Comment on total semantics |
| `ScanDashboardView.swift` | Remove Project Roots section |
| Related tests | Regression coverage |

**Recommendation:** Treat as a single “scan correctness + dashboard hygiene” commit (or two) after test catalog fix — when you choose to commit.

---

## 9. Suggested priorities (product, not implementation)

### P0 — Before trusting release builds

1. Fix the 2 failing catalog tests (or restore missing rule intentionally).  
2. Commit/land H1+H2 fixes after re-verify on device.  
3. Smoke `make run-app` full scan + Quick Clean dry path.

### P1 — Trust & clarity

4. Per-rule or fractional scan progress (or at least “Scanning: rule X of N”).  
5. De-emphasize advanced in Top files (section or filter).  
6. Collapse dual project-root systems into one model; optional Settings entry if roots need management.  
7. Delete or re-home dead Project Roots UI; register or delete `DockerLogsReviewRequiredRule`.

### P2 — Hardening

8. Fix AppInventory double-resume.  
9. Cap / prioritize project roots (e.g. largest or recently used) if 100s of roots.  
10. Doc/changelog sync; rename `PareApp.swift`.  
11. Finish Phase 9 signing + notarization on a clean machine.

### P3 — Performance

12. Safe parallel rule execution (after careful actor design).  
13. Smarter UserCaches / large-tree strategies (directory-level rollups where safe).

---

## 10. What’s already in good shape

- Cleanup hard-blocks advanced; Trash + transactions.  
- ScanPolicy age and path markers for many sensitive areas.  
- Force rescan + metadata cache.  
- Breadth of developer ecosystem rules.  
- Maintenance actions gated sensibly (e.g. Docker prune when daemon present).  
- History and exclusions are first-class.  
- Recent investigation of TB totals and hang was real and addressable.

---

## 11. Related documents

| Document | Purpose |
|----------|---------|
| [2026-07-13-action-checklist.md](./2026-07-13-action-checklist.md) | Checkbox list ordered by priority for you to work through |
| [../features/docker-safety.md](../features/docker-safety.md) | **Binding** Docker.raw / no-volumes policy (implemented 2026-07-13) |
| [../roadmap.md](../roadmap.md) | Phase status (Phase 9 still open) |
| [../features/phase-6-developer-breadth.md](../features/phase-6-developer-breadth.md) | Project roots / artifacts design intent |
| [../features/phase-7-platform-completeness.md](../features/phase-7-platform-completeness.md) | Docker / backups / browser review |
| [../CHANGELOG.md](../../CHANGELOG.md) | Public claims (partially stale) |

---

## 12. Reviewer notes

- Review combined **committed history** and **local uncommitted fixes** so the document matches what you have on disk today.  
- No production source was modified for this review pass.  
- Live disk sample (developer CLI after fixes): ~**31 GB** reclaimable; Docker.raw ~**22 GB** advanced; project artifacts ~**24 GB** — plausible on a 256 GB volume, unlike 1.13 TB.
